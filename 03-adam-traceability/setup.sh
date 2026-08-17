#!/usr/bin/env bash
# Fetch the files this entry reads from the CDISC SDTM/ADaM Pilot Project.
#
# The full repository is ~400 MB, most of it XPT copies of datasets that also ship as
# Dataset-JSON. This pulls the 13 files the notebook opens, pinned to one commit, and
# skips whatever it already has. Re-runnable.
set -euo pipefail
cd "$(dirname "$0")"

# Pinned so the numbers in the README stay meaningful. master as of 2026-08-16.
REPO="https://raw.githubusercontent.com/cdisc-org/sdtm-adam-pilot-project"
SHA="667511d4b183871d74392ba691c935c38d431d39"
PKG="updated-pilot-submission-package/900172/m5"
ADAM="$PKG/datasets/cdiscpilot01/analysis/adam/datasets"
SDTM="$PKG/datasets/cdiscpilot01/tabulations/sdtm"
CSR="$PKG/53-clin-stud-rep/535-rep-effic-safety-stud/5351-stud-rep-contr/cdiscpilot01"

# local path <TAB> remote path <TAB> sha256
FILES=$(cat <<'EOF'
adam/adsl.json	ADAM/adsl.json	5f8815fc77b65674ce9af5f8b67b08ab7dc5e0c87d439f7d3c2add062a91affa
adam/adae.json	ADAM/adae.json	9bd195ecfde55486cd39f59e485dcc39cfb4b1d62b08befc150a30af4ad15fd3
adam/adlbc.json	ADAM/adlbc.json	e627f3d7cbbb4ffd47342f472ee780caf773785f6de6c402aee7833ceb775694
adam/adlbh.json	ADAM/adlbh.json	bb4e26e612ae394dd543ab3f2f732874bc539675ec9000e780817dd6c7562b34
adam/adlbhy.json	ADAM/adlbhy.json	0ddce08e97e5da1ad988f2cbac8bae9e6cea37c940ab0be8a43091cd9fef9065
adam/adqsadas.json	ADAM/adqsadas.json	a832aa6eae92831d813ac824973a2f58c695b5ed57c534f33815b874251b0285
adam/adqscibc.json	ADAM/adqscibc.json	c40c6eab4c0d7f6b2e82a465e7755c21eec04839586bbdf6572759da0bdd04e5
adam/adqsnpix.json	ADAM/adqsnpix.json	6d80a16ece54d548a8a47bd633f49bb62c810ae85ad215a4315c071f1ab79118
adam/adtte.json	ADAM/adtte.json	40d0213aecde81db8f84980669c1af77c711f888a78da36e46c90bc1030ff85b
adam/define.xml	ADAM/define.xml	7e6d580e0839564f6f119c4ba7e15963d3cf7cd0c88e9f3d7da5ad396221b1cd
sdtm/qs.json	SDTM/qs.json	b22e1acd5b887982fec8d3bc10fb51e2445957bf9dad37259efba2772ef0cdda
sdtm/define.xml	SDTM/define.xml	fbb065b8bb72d609e1a12670940e0d2ef11e6757cbbcd56bf9d0ba55ce1fc76b
csr/cdiscpilot01.pdf	CSR/cdiscpilot01.pdf	0cab016c76abb3dcaef31110611c95dbd9cd00df083b35e6d28fd69fca0d842d
EOF
)

command -v curl >/dev/null || { echo "need curl"; exit 1; }
mkdir -p data/adam data/sdtm data/csr

drift=0
while IFS=$'\t' read -r local remote want; do
  [ -n "$local" ] || continue
  dest="data/$local"
  case "$remote" in
    ADAM/*) url="$REPO/$SHA/$ADAM/${remote#ADAM/}" ;;
    SDTM/*) url="$REPO/$SHA/$SDTM/${remote#SDTM/}" ;;
    CSR/*)  url="$REPO/$SHA/$CSR/${remote#CSR/}" ;;
  esac
  if [ -f "$dest" ]; then
    echo "have    $local"
  else
    echo "fetch   $local"
    curl -fsSL "$url" -o "$dest.part"
    mv "$dest.part" "$dest"
  fi
  got=$(shasum -a 256 "$dest" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then
    echo "  WARNING: checksum differs from the version used for the README numbers"
    echo "           expected $want"
    echo "           got      $got"
    drift=1
  fi
done <<< "$FILES"

echo
du -sh data
if [ "$drift" = "1" ]; then
  echo
  echo "At least one file has drifted. The notebook will still run, but the numbers"
  echo "in the README were produced from the pinned versions."
fi
echo "done."
