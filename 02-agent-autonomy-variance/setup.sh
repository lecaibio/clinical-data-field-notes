#!/usr/bin/env bash
# Collect the run log this entry analyses. Safe to re-run: existing logs are left alone.
set -euo pipefail
cd "$(dirname "$0")"

N="${N:-20}"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

say "API key"
if [ -z "${GEMINI_API_KEY:-}" ] && [ -z "${GOOGLE_API_KEY:-}" ]; then
    cat <<'EOF'
  No GEMINI_API_KEY set. This entry calls a model, so it cannot run without one.
  Free key, no credit card: https://aistudio.google.com  ->  Get API Key

      export GEMINI_API_KEY=AIza...

  Then re-run this script. Nothing else here needs a key: once runs/ exists the
  notebook rebuilds every figure from it offline.
EOF
    exit 1
fi
echo "  key found"

say "Dependencies"
if [ ! -d .venv ]; then
    python3 -m venv .venv
    .venv/bin/pip install -q --upgrade pip
fi
.venv/bin/pip install -q -r requirements.txt
echo "  ok"

say "Runs"
if [ -s runs/rung3.jsonl ]; then
    echo "  runs/ already populated -- delete it to re-collect"
else
    echo "  $N runs per arm; tool returns are cached after the first fetch"
    .venv/bin/python collect.py -n "$N"
fi

say "Done"
echo "Now: .venv/bin/jupyter lab notebook.ipynb"
