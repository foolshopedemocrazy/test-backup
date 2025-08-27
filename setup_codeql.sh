#!/usr/bin/env bash
set -Eeuo pipefail
GH=".github"; CQ="${GH}/codeql"
need=(
  "${GH}/workflows/codeql.yml"
  "${CQ}/config/python.yml"
  "${CQ}/config/javascript.yml"
  "${CQ}/queries/python/python-custom.qls"
  "${CQ}/queries/python/noop.ql"
  "${CQ}/queries/javascript/javascript-custom.qls"
  "${CQ}/queries/javascript/noop.ql"
  "${CQ}/compliance/cwe_to_owasp.csv"
  "${CQ}/tools/sarif_summary.py"
)
ok=1
for p in "${need[@]}"; do
  [ -f "$p" ] || { echo "MISSING $p"; ok=0; }
done
grep -E '^\s*-\s*uses:\s*\.' "${CQ}/config/"*.yml | while read -r line; do
  ref="${line#*- uses: }"
  if [[ "$ref" == ./* ]]; then
    [ -e "$ref" ] || { echo "Broken uses: $ref"; ok=0; }
    [[ "$ref" == *.ql || "$ref" == *.qls ]] || { echo "Invalid relative uses (must be .ql/.qls): $ref"; ok=0; }
  fi
done
find "${GH}/codeql" -maxdepth 3 -type f -print
[ $ok -eq 1 ] && echo "Verification PASSED." || { echo "Verification FAILED."; exit 2; }
