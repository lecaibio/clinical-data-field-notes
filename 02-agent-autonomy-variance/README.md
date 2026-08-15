# 02 — Does a tool-using agent do the same thing twice?

**Status: parked, unfinished.** The collection code runs but has never been executed against a
model, so there are no results, no notebook, and no figures. Nothing here has been used to make
a claim anywhere. Read it as a scaffold, not as an entry.

## The question it was going to ask

Give a model a task whose correct tool order is knowable before the run — to describe a gene
you need its UniProt entry and its ChEMBL activity, and neither depends on the other — then
run the identical request twenty times and count how many distinct tool-call sequences come
back. Anything other than one sequence is variation that was paid for and not needed.

Two arms, in `collect.py`:

- **Rung 1** — our code calls both tools in a fixed order, then one model call formats the
  result. The order was decided once, when the task was understood.
- **Rung 3** — the model gets both tool descriptions and decides for itself.

The headline number would have been **distinct tool-call sequences out of 20**. The
distinction that makes it mean anything: an LLM's *output text* varies at both rungs, so the
claim is only ever about **control-flow** variance, which only rung 3 can have.

Tool returns are cached on first fetch and reused, so the tools are byte-identical across
runs. Without that, an upstream API change would be indistinguishable from a change in the
model's behaviour.

## Running it, if you pick this up

```bash
export GEMINI_API_KEY=...     # free, no card: https://aistudio.google.com
./setup.sh                    # deps, then 20 runs per arm into runs/
```

`setup.sh` stops with instructions rather than a stack trace when no key is set.
`collect.py --list-models` shows what your key supports; `MODEL=...` overrides the default.

`cache/` is gitignored — it re-fetches from UniProt and ChEMBL in seconds. `runs/` is **not**
gitignored, deliberately: unlike entry 01 there is no seed that pins a model's output, so if
this is ever finished the run log is the artifact and the figures should be built from it
rather than from a live call.

## Two things already worth keeping

Both are in `collect.py` and both were bugs in the obvious version of the ChEMBL tool:

- Taking the first search hit for `BRAF` returns the ***Mus musculus*** target. Filter for the
  human `SINGLE PROTEIN` entry, which is `CHEMBL5145`.
- `len(target_components)` counts protein subunits, not bioactivity records. The real count
  comes from the activity endpoint's `page_meta.total_count` — 25,898 at time of writing.

## The honest risk

Rung 3 may well produce the identical sequence all twenty times. That would not be a failed
experiment, but it would mean the write-up has to be the weaker, more careful claim — stable
across twenty runs, with nothing in the API contract promising it stays stable across model
versions — rather than the stronger one. Worth agreeing to report whatever comes out before
running it.
