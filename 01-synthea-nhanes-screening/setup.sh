#!/usr/bin/env bash
# Fetch NHANES and generate the Synthea population this notebook expects.
# Safe to re-run: anything already present is left alone.
set -euo pipefail
cd "$(dirname "$0")"

SYNTHEA_TAG=v4.0.0          # the screening modules are byte-identical to the build used
SEED=20260815               # same seed -> same patients
POPULATION=10000
SYNTHEA_SRC="${SYNTHEA_SRC:-data/synthea-src}"

# Synthea's default is one thread per core, and that is NOT reproducible: the same seed
# gave 11,533 patients on one run and 11,548 on the next. Single-threaded is byte-identical
# run to run, at roughly six times the wall clock. Set THREADS=-1 if you would rather have
# the speed and don't mind the numbers moving a few tenths of a point.
THREADS="${THREADS:-1}"

# only the five files the notebook opens; the rest (claims especially) run to gigabytes
CSV_FILES=patients.csv,observations.csv,encounters.csv,medications.csv,conditions.csv

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# --------------------------------------------------------------- NHANES
say "NHANES 2017-2018"
mkdir -p data/nhanes
BASE=https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles
# sha256 of the files this notebook's numbers were computed from
EXPECTED_DPQ=1c075f332e79736bd2360b41b0c10ed526883417e0b5996c407b1c564b01ca24
EXPECTED_DEMO=c0b46e0345ea19404928656277c8b0d10b0cca348a9b2fe4fc3c67e8b7ee73ec

for f in DPQ_J DEMO_J; do
    if [ -s "data/nhanes/$f.xpt" ]; then
        echo "  have data/nhanes/$f.xpt"
    else
        echo "  downloading $f.xpt"
        curl -fSL --progress-bar -o "data/nhanes/$f.xpt" "$BASE/$f.xpt"
    fi
done

if command -v shasum >/dev/null; then
    for pair in "DPQ_J $EXPECTED_DPQ" "DEMO_J $EXPECTED_DEMO"; do
        set -- $pair
        got=$(shasum -a 256 "data/nhanes/$1.xpt" | cut -d' ' -f1)
        if [ "$got" != "$2" ]; then
            echo "  NOTE: $1.xpt checksum differs from the one used here."
            echo "        CDC may have reissued the file; numbers may shift slightly."
        fi
    done
fi

# --------------------------------------------------------------- Synthea
say "Synthea $SYNTHEA_TAG"
if [ -s data/synthea/csv/patients.csv ]; then
    echo "  have data/synthea/csv/ -- delete it to regenerate"
    exit 0
fi

if ! java -version >/dev/null 2>&1; then
    cat <<'EOF'
  No Java runtime found. Synthea 4.x needs JDK 17 or newer.
      macOS:  brew install openjdk@17 && export JAVA_HOME=/opt/homebrew/opt/openjdk@17
      Debian: sudo apt install openjdk-17-jdk
  Then re-run this script. (NHANES is already downloaded; nothing is lost.)
EOF
    exit 1
fi

if [ ! -d "$SYNTHEA_SRC" ]; then
    echo "  cloning synthea into $SYNTHEA_SRC"
    git clone --depth 1 --branch "$SYNTHEA_TAG" \
        https://github.com/synthetichealth/synthea.git "$SYNTHEA_SRC"
fi

echo "  generating $POPULATION patients on $THREADS thread(s)"
[ "$THREADS" = "1" ] && echo "  (~15 minutes, reproducible; THREADS=-1 is ~6x faster but is not)"
OUT="$PWD/data/synthea/"
( cd "$SYNTHEA_SRC" && ./run_synthea \
    -p "$POPULATION" -s "$SEED" -cs "$SEED" \
    --exporter.baseDirectory="$OUT" \
    --exporter.csv.export=true \
    --exporter.csv.included_files="$CSV_FILES" \
    --exporter.fhir.export=false \
    --exporter.hospital.fhir.export=false \
    --exporter.practitioner.fhir.export=false \
    --generate.thread_pool_size="$THREADS" )

say "Done"
du -sh data/nhanes data/synthea
echo
echo "Now: jupyter lab notebook.ipynb"
