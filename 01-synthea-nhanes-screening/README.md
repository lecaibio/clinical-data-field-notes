# 01 — Depression screening in NHANES vs Synthea

Same questionnaire (PHQ-9), two sources. Who gets asked, what share of them score
10 or higher, and — a question only the synthetic EHR can answer — whether a positive
screen leads to anything.

The two sources land within a point of each other on the population rate (8.3% vs 7.4%)
by way of components that differ roughly eightfold in opposite directions. The reason is
readable in about forty lines of Synthea's `encounter/depression_screening.json`.

Unweighted proportions throughout; NHANES's sampling weights are ignored on purpose.

## Running it

Neither dataset is committed — one is a CDC download, the other is generated. From this
directory:

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
./setup.sh
```

Then open it and work through it:

```bash
.venv/bin/jupyter lab notebook.ipynb
```

or re-run every cell headlessly, rewriting the outputs and the three PNGs in `figures/`:

```bash
.venv/bin/jupyter nbconvert --to notebook --execute --inplace notebook.ipynb
```

The second one exits non-zero if any cell raises, so it doubles as the check that the
notebook still runs. Either way, start from this directory — the paths inside are relative
to it. The first code cell prints `all 7 input files present`; if it doesn't, stop there.
The analysis takes well under a minute, most of it spent chunking through the 1.5 GB
`observations.csv`.

Outputs are committed on purpose: running this needs 1.9 GB of data, a JDK, and eleven
minutes, so the rendered notebook is how most people will read it. That only stays honest
if the committed outputs match the committed code — **Restart Kernel and Run All Cells (or
the `nbconvert` line) before committing an edit.** Non-consecutive execution counts in the
committed file mean someone skipped that step and the outputs can't be trusted.

`setup.sh` is re-runnable and skips whatever it already finds. It:

1. downloads `DPQ_J.xpt` (0.5 MB) and `DEMO_J.xpt` (3.4 MB) from `wwwn.cdc.gov` into
   `data/nhanes/`, and warns if either checksum has drifted from the version used here;
2. shallow-clones Synthea at tag **v4.0.0** into `data/synthea-src/` and generates
   **10,000** living patients with seed **20260815** into `data/synthea/`.

It exports only the five CSVs the notebook opens. Exporting everything is also correct
but writes about 8 GB, most of it claims transactions the notebook never reads; the five
come to 1.9 GB.

**Needs JDK 17+** for the Synthea step (`brew install openjdk@17`, or
`apt install openjdk-17-jdk`). The script checks, and stops with instructions rather than
a stack trace if it is missing. NHANES alone needs no Java. If you already have a Synthea
checkout, point at it with `SYNTHEA_SRC=/path/to/synthea ./setup.sh` — but the numbers
below are v4.0.0's; the module JSON changes between releases, which is rather the point of
the exercise.

### A fixed seed is not enough

Synthea defaults to one thread per core, and that is not reproducible. The same
`-s 20260815 -cs 20260815` gave 11,533 patients on one run and 11,548 on the next, moving
the positive rate by about 0.8 points. `setup.sh` therefore passes
`--generate.thread_pool_size=1`, which is byte-identical run to run and takes about
**11 minutes** instead of two. `THREADS=-1 ./setup.sh` buys the speed back if you only
want the shape and not the exact figures.

## What you should get

| | NHANES 2017–2018 | Synthea v4.0.0 |
|---|---|---|
| adults in the denominator | 5,533 | 6,936 |
| given the questionnaire | 91.6% | 11.7% |
| scored 10+, of those given it | 9.1% | 63.8% |
| scored 10+, of all adults | 8.3% | 7.4% |

and, on the Synthea side, 516 adults scoring 10 or higher followed by zero depression
diagnoses and zero antidepressant prescriptions within twelve months.

The analysis itself is the fast part — well under a minute once the data is there.

## Reclaiming the disk afterwards

A full run leaves about **2.2 GB** in this directory, none of which is worth keeping once
you have your numbers:

| | |
|---|---|
| `data/synthea/` | 1.9 GB — the generated CSVs |
| `data/synthea-src/` | ~300 MB — the shallow clone plus its build output |
| `data/nhanes/` | 3.7 MB — the two CDC files |

Everything under `data/` is regenerable, and nothing outside it depends on it once the
notebook has run: the figures (176 KB) and the notebook's own embedded outputs are the
durable artifacts. So:

```bash
rm -rf data
```

Re-running `./setup.sh` rebuilds whatever you removed. If you expect to come back, keep
`data/nhanes/` — it is 3.7 MB and saves a download — and drop only the expensive half:

```bash
rm -rf data/synthea data/synthea-src
```

One thing lands outside this directory and is easy to forget: Gradle caches Synthea's
dependencies in `~/.gradle`, which grew by roughly 400 MB here. Removing it is safe and
costs a re-download the next time you build anything with Gradle.
