"""Run the same request N times at two rungs of the autonomy ladder, and log what happened.

Rung 1: our code calls both tools in a fixed order, then one model call formats the result.
Rung 3: the model is handed both tool descriptions and decides for itself what to call.

The task is chosen so the correct order is knowable before the run: to describe a gene you
need its UniProt entry and its ChEMBL activity, and neither depends on the other. Any variation
in what rung 3 does is therefore variation we paid for and did not need.

Tool returns are cached on first fetch and reused for every subsequent run, so the tools are
byte-identical across runs. Without that, a change in an upstream API would be indistinguishable
from a change in the model's behaviour.
"""
import argparse
import json
import os
import time
import urllib.parse
import urllib.request
from pathlib import Path

from google import genai
from google.genai import types

HERE = Path(__file__).parent
CACHE, RUNS = HERE / "cache", HERE / "runs"
MODEL = os.environ.get("MODEL", "gemini-2.5-flash")
GENE = os.environ.get("GENE", "BRAF")

PROMPT = (
    f"Produce a one-paragraph summary of the human gene {GENE} for a research brief. "
    "It must state the protein name, the UniProt accession, and how many ChEMBL "
    "bioactivity records exist for it. Use the tools available to you."
)

# ---------------------------------------------------------------- tools


def _cached(name: str, url: str) -> dict:
    """Fetch once, then reuse. Keeps the tools constant across runs."""
    CACHE.mkdir(exist_ok=True)
    path = CACHE / f"{name}.json"
    if path.exists():
        return json.loads(path.read_text())
    with urllib.request.urlopen(url, timeout=30) as r:
        payload = json.load(r)
    path.write_text(json.dumps(payload, indent=1))
    return payload


def uniprot_lookup(gene: str) -> dict:
    q = urllib.parse.quote(f"gene:{gene} AND organism_id:9606 AND reviewed:true")
    raw = _cached(f"uniprot_{gene}",
                  f"https://rest.uniprot.org/uniprotkb/search?query={q}&format=json&size=1")
    e = raw["results"][0]
    return {"accession": e["primaryAccession"],
            "protein_name": e["proteinDescription"]["recommendedName"]["fullName"]["value"]}


def chembl_activity(gene: str) -> dict:
    """Bioactivity record count for the human single-protein target.

    Two things the obvious version gets wrong. Taking the first search hit returns the
    *Mus musculus* target for BRAF, and len(target_components) is a count of protein
    subunits, not of bioactivity records. Filter for the human single-protein target, then
    ask the activity endpoint for a real total.
    """
    search = _cached(f"chembl_search_{gene}",
                     "https://www.ebi.ac.uk/chembl/api/data/target/search.json"
                     f"?q={urllib.parse.quote(gene)}&limit=20")
    hits = [t for t in search.get("targets", [])
            if t.get("target_type") == "SINGLE PROTEIN" and t.get("organism") == "Homo sapiens"]
    if not hits:
        return {"chembl_id": None, "activity_count": 0}
    tid = hits[0]["target_chembl_id"]
    acts = _cached(f"chembl_activity_{gene}",
                   "https://www.ebi.ac.uk/chembl/api/data/activity.json"
                   f"?target_chembl_id={tid}&limit=1")
    return {"chembl_id": tid, "activity_count": acts["page_meta"]["total_count"]}

TOOLS = {"uniprot_lookup": uniprot_lookup, "chembl_activity": chembl_activity}

DECLS = [
    types.FunctionDeclaration(
        name="uniprot_lookup",
        description="Return the reviewed UniProt accession and protein name for a human gene symbol.",
        parameters_json_schema={"type": "object", "properties": {"gene": {"type": "string"}},
                                "required": ["gene"]}),
    types.FunctionDeclaration(
        name="chembl_activity",
        description="Return the ChEMBL target id and bioactivity record count for a human gene symbol.",
        parameters_json_schema={"type": "object", "properties": {"gene": {"type": "string"}},
                                "required": ["gene"]}),
]

# ---------------------------------------------------------------- arms


def rung3(client, max_steps: int = 8) -> dict:
    """The model chooses. Automatic function calling is switched OFF on purpose: left on, the
    SDK executes the tools itself and the raw exchange ends up in a side attribute rather than
    in our hands. We want the sequence and every raw return."""
    cfg = types.GenerateContentConfig(
        temperature=0,
        tools=[types.Tool(function_declarations=DECLS)],
        automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
    )
    contents = [types.Content(role="user", parts=[types.Part.from_text(text=PROMPT)])]
    sequence, raw_returns, tokens = [], [], 0
    t0 = time.time()

    for _ in range(max_steps):
        resp = client.models.generate_content(model=MODEL, contents=contents, config=cfg)
        if resp.usage_metadata:
            tokens += resp.usage_metadata.total_token_count or 0
        calls = resp.function_calls or []
        if not calls:
            sequence.append("answer")
            return {"rung": 3, "sequence": sequence, "steps": len(sequence),
                    "tokens": tokens, "seconds": round(time.time() - t0, 2),
                    "raw_returns": raw_returns, "text": resp.text}
        contents.append(resp.candidates[0].content)
        for call in calls:
            sequence.append(call.name)
            out = TOOLS[call.name](**dict(call.args))
            raw_returns.append({"tool": call.name, "args": dict(call.args), "returned": out})
            contents.append(types.Content(role="user", parts=[
                types.Part.from_function_response(name=call.name, response=out)]))

    sequence.append("hit_step_cap")
    return {"rung": 3, "sequence": sequence, "steps": len(sequence), "tokens": tokens,
            "seconds": round(time.time() - t0, 2), "raw_returns": raw_returns, "text": None}


def rung1(client) -> dict:
    """We decided the order when we understood the task. No tool descriptions are sent."""
    t0 = time.time()
    facts = {"uniprot": uniprot_lookup(GENE), "chembl": chembl_activity(GENE)}
    resp = client.models.generate_content(
        model=MODEL,
        contents=f"{PROMPT}\n\nUse exactly these facts:\n{json.dumps(facts)}",
        config=types.GenerateContentConfig(temperature=0),
    )
    return {"rung": 1, "sequence": ["uniprot_lookup", "chembl_activity", "answer"], "steps": 3,
            "tokens": (resp.usage_metadata.total_token_count if resp.usage_metadata else 0),
            "seconds": round(time.time() - t0, 2),
            "raw_returns": [{"tool": k, "args": {"gene": GENE}, "returned": v}
                            for k, v in facts.items()],
            "text": resp.text}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=20, help="runs per arm")
    ap.add_argument("--list-models", action="store_true")
    args = ap.parse_args()

    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not key:
        raise SystemExit("Set GEMINI_API_KEY first. Free key, no card: https://aistudio.google.com")
    client = genai.Client(api_key=key)

    if args.list_models:
        for m in client.models.list():
            if "generateContent" in (m.supported_actions or []):
                print(" ", m.name)
        return

    RUNS.mkdir(exist_ok=True)
    for arm, fn in (("rung1", rung1), ("rung3", rung3)):
        out = RUNS / f"{arm}.jsonl"
        with out.open("w") as fh:
            for i in range(args.n):
                rec = fn(client) if arm == "rung1" else fn(client)
                rec["run"] = i
                fh.write(json.dumps(rec) + "\n")
                print(f"  {arm} {i + 1}/{args.n}  {'>'.join(rec['sequence'])}")
        print(f"wrote {out}")


if __name__ == "__main__":
    main()
