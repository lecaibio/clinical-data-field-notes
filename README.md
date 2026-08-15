# clinical data field notes

Rough notebooks that poke at public clinical data and produce a figure or two. Each entry
answers one question: does this data source, or this method, hold up for this particular use?

The write-up is the thing to read; the notebook is here for anyone who wants to run it.

| # | Entry | The finding | Post | Notebook |
|---|---|---|---|---|
| 01 | Depression screening in NHANES vs Synthea | Both sources put 7–8% of adults over the PHQ-9 cutoff, via components that differ eightfold in opposite directions — and in Synthea nothing downstream ever reads the score | [Where Synthetic Clinical Data Gets Its Correlations](https://lecaibio.github.io/2026/08/15/where-synthetic-clinical-data-gets-its-correlations.html) | [notebook](01-synthea-nhanes-screening/notebook.ipynb) |
| 02 | An agent layer is net overhead on fixed-output tasks | For a stable schema and a fixed output shape, orchestration and tool-calling buy nothing over a direct call plus deterministic code | *not yet published* | [repo](https://github.com/lecaibio/cabs-workshop-llm-agents) |

Each directory stands on its own — its own README, its own `requirements.txt`, its own
`setup.sh`, its own figures. Nothing imports anything from anywhere else.

Raw data is never committed; it is downloaded or generated. To run an entry yourself:

```bash
cd 01-synthea-nhanes-screening
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
./setup.sh                      # fetches and generates the inputs; re-runnable
.venv/bin/jupyter lab notebook.ipynb
```

To re-run an entry end to end without opening anything — also the way to check it still
works, since it exits non-zero on the first cell that raises:

```bash
.venv/bin/jupyter nbconvert --to notebook --execute --inplace notebook.ipynb
```

Each entry's README lists what its `setup.sh` needs (entry 01 wants JDK 17 for the Synthea
step) and the numbers you should get back, so you can tell whether you reproduced it.
Notebook outputs are committed, so you can read an entry without running it.

Running one is not free on disk — entry 01 leaves about 2.2 GB under `data/`. It is all
regenerable, so `rm -rf data` once you have your numbers; each entry's README says what
that frees and what is worth keeping.
