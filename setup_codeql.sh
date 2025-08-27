#!/usr/bin/env bash
# seed_codeql_minimal.sh
# Creates a minimal, working CodeQL layout and verifies it.
# Run from your repository root:  bash seed_codeql_minimal.sh

set -euo pipefail

ok()  { printf "\033[1;32m[OK]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[ERR]\033[0m %s\n" "$*" >&2; }

# 0) Must be a git repo (sanity)
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  err "Run this from your repo root ('.git' not found)."
  exit 1
}

# 1) Create exact directories (lowercase; runner is case-sensitive)
mkdir -p .github/workflows
mkdir -p .github/codeql/config
mkdir -p .github/codeql/queries/javascript
mkdir -p .github/codeql/queries/python
mkdir -p .github/codeql/compliance
mkdir -p .github/codeql/tools

ok "Folders created."

# 2) Write minimal workflow (points to shared config)
cat > .github/workflows/codeql.yml <<'YAML'
name: CodeQL
on:
  push: { branches: [ "main", "master" ] }
  pull_request: { branches: [ "main", "master" ] }
  schedule: [ { cron: "14 3 * * 1" } ]
  workflow_dispatch:
permissions:
  contents: read
  security-events: write
  actions: read
concurrency:
  group: codeql-${{ github.ref }}
  cancel-in-progress: true
jobs:
  analyze:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        language: [ "javascript", "python" ]
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          config-file: ./.github/codeql/config/config.yml
      - uses: github/codeql-action/autobuild@v3
      - uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
          output: sarif-results
YAML

# 3) Write shared CodeQL config
cat > .github/codeql/config/config.yml <<'YAML'
name: answerchain-config
paths: [ "src/", "app/", "services/" ]
paths-ignore: [ "tests/", "test/", "third_party/", "vendor/", "**/*.generated.*" ]
queries:
  - uses: security-extended
  - uses: security-and-quality
YAML

# 4) Write example queries (one per language)
cat > .github/codeql/queries/javascript/todo-comment.ql <<'QL'
/**
 * @name TODO comments in JS/TS
 * @id js/custom/todo-comment
 * @kind problem
 * @problem.severity warning
 * @tags maintainability
 */
import javascript
from Comment c
where c.getText().regexpMatch("(?i)\\bTODO\\b")
select c, "TODO comment found."
QL

cat > .github/codeql/queries/python/redundant-pass-if.ql <<'QL'
/**
 * @name Redundant 'if ...: pass'
 * @id py/custom/redundant-pass-if
 * @kind problem
 * @problem.severity warning
 * @tags maintainability
 */
import python
from IfStmt s
where s.getThen().isPass()
select s, "Redundant 'if ...: pass' statement."
QL

# 5) Compliance mapping (placeholder)
cat > .github/codeql/compliance/cwe_to_owasp.csv <<'CSV'
cwe_id,owasp_top10
CWE-79,A03:2021
CWE-89,A03:2021
CWE-22,A05:2021
CSV

# 6) Optional helper (exec summary)
cat > .github/codeql/tools/sarif_summary.py <<'PY'
import json, sys, argparse, csv, os
def load_map(path):
    m = {}
    try:
        with open(path, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                m[row.get("cwe_id","").strip()] = row.get("owasp_top10","").strip()
    except FileNotFoundError:
        pass
    return m
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sarif", required=True)
    ap.add_argument("--cwe-map", default="")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    if not os.path.exists(args.sarif):
        open(args.out,"w",encoding="utf-8").write("# No SARIF found\n"); return
    with open(args.sarif, encoding="utf-8") as f: sarif=json.load(f)
    cmap = load_map(args.cwe_map)
    runs = sarif.get("runs",[]); out=["# CodeQL Executive Summary\n"]
    total=0
    for run in runs:
        tool = run.get("tool",{}).get("driver",{}).get("name","unknown")
        res = run.get("results",[]); total += len(res)
        out.append(f"## Tool: {tool}, Findings: {len(res)}")
        for r in res[:100]:
            rid = r.get("ruleId",""); msg=r.get("message",{}).get("text","")
            tags=(r.get("properties",{}) or {}).get("tags",[])
            cwes=[t for t in tags if str(t).upper().startswith("CWE-")]
            mapped=[f"{c}:{cmap.get(c,'')}" for c in cwes]
            out.append(f"- {rid} :: {msg} {' '.join(mapped)}")
    out.append(f"\n**Total findings across runs:** {total}\n")
    open(args.out,"w",encoding="utf-8").write("\n".join(out))
if __name__ == "__main__": main()
PY

ok "Files written."

# 7) Verification: check required items exist and count them
required_files=(
  ".github/workflows/codeql.yml"
  ".github/codeql/config/config.yml"
  ".github/codeql/queries/javascript/todo-comment.ql"
  ".github/codeql/queries/python/redundant-pass-if.ql"
  ".github/codeql/compliance/cwe_to_owasp.csv"
  ".github/codeql/tools/sarif_summary.py"
)
required_dirs=(
  ".github"
  ".github/workflows"
  ".github/codeql"
  ".github/codeql/config"
  ".github/codeql/queries"
  ".github/codeql/queries/javascript"
  ".github/codeql/queries/python"
  ".github/codeql/compliance"
  ".github/codeql/tools"
)

fail=0
for d in "${required_dirs[@]}"; do
  [ -d "$d" ] || { err "Missing directory: $d"; fail=1; }
done
for f in "${required_files[@]}"; do
  [ -f "$f" ] || { err "Missing file: $f"; fail=1; }
done

# Count summary
dir_count=0; file_count=0
while IFS= read -r -d '' d; do dir_count=$((dir_count+1)); done < <(find .github -type d -print0)
while IFS= read -r -d '' f; do file_count=$((file_count+1)); done < <(find .github -type f -print0)

echo "----- STRUCTURE -----"
find .github -maxdepth 4 -print | sed 's#^#  #'
echo "---------------------"
echo "Directory count under .github: $dir_count"
echo "File count under .github:      $file_count"

if [ "$fail" -ne 0 ]; then
  err "Verification FAILED (see missing items above)."
  exit 2
fi

ok "Verification PASSED. CodeQL layout is complete."
echo "Next:"
echo "  git add .github"
echo "  git commit -m 'chore(codeql): seed minimal layout'"
echo "  git push"
echo "  Re-run the CodeQL workflow in GitHub Actions."
