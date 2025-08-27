#!/usr/bin/env bash
set -Eeuo pipefail

# Optional: allow overriding the repo root (default = current dir)
REPO_ROOT="${1:-$(pwd)}"
cd "$REPO_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository. cd into your repo root first." >&2
  exit 1
fi

timestamp() { date +%Y%m%d-%H%M%S; }

echo "==> Ensuring .github layout"
mkdir -p .github/workflows
mkdir -p .github/codeql/{config,queries/javascript,queries/python,compliance,tools,templates}

# Migrate any old mixed-case folder (.github/CodeQL) into lowercase path
if [ -d ".github/CodeQL" ]; then
  echo "==> Migrating '.github/CodeQL' -> '.github/codeql'"
  rsync -a --ignore-existing ".github/CodeQL/" ".github/codeql/" || true
  rm -rf ".github/CodeQL"
fi

# Remove any previous experimental/broken workflow to avoid confusion
if [ -f ".github/workflows/codeql-analysis.yml" ]; then
  mv ".github/workflows/codeql-analysis.yml" ".github/workflows/codeql-analysis.yml.bak.$(timestamp)"
fi

echo "==> Writing .github/workflows/codeql.yml"
cat > .github/workflows/codeql.yml <<'YAML'
name: CodeQL

on:
  push:
    branches: [ "main", "master" ]
  pull_request:
    branches: [ "main", "master" ]
    paths-ignore:
      - '**/*.md'
      - 'docs/**'
  schedule:
    - cron: "14 3 * * 1"
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
        language: [ "python", "javascript" ]

    steps:
      - uses: actions/checkout@v4

      # Optional, for summary script
      - name: Set up Python for tooling
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install tooling deps
        run: |
          if [ -f ".github/codeql/tools/requirements.txt" ]; then
            python -m pip install --upgrade pip
            python -m pip install -r .github/codeql/tools/requirements.txt
          fi

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          config-file: ./.github/codeql/config/config.yml

      - name: Autobuild
        uses: github/codeql-action/autobuild@v3

      # Let analyze upload to Code Scanning (canonical path).
      # Also write SARIF to disk so we can filter or summarize as artifacts.
      - name: Analyze
        uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
          output: sarif-results

      # OPTIONAL post-processing purely for artifacts; does NOT re-upload to code scanning.
      - name: Filter SARIF (artifact-only)
        if: ${{ hashFiles('sarif-results/*.sarif') != '' }}
        uses: advanced-security/filter-sarif@v1
        with:
          input: sarif-results/${{ matrix.language }}.sarif
          output: sarif-results/${{ matrix.language }}.filtered.sarif
          include: |
            +src/**
            +app/**
            +services/**
          exclude: |
            -tests/**
            -test/**
            -third_party/**
            -vendor/**
            -**/*.generated.*

      - name: Upload SARIF artifacts
        if: ${{ hashFiles('sarif-results/*.sarif') != '' }}
        uses: actions/upload-artifact@v4
        with:
          name: sarif-${{ matrix.language }}
          path: |
            sarif-results/${{ matrix.language }}.sarif
            sarif-results/${{ matrix.language }}.filtered.sarif
          if-no-files-found: warn

      - name: Executive summary (Markdown)
        if: ${{ hashFiles('sarif-results/*.sarif') != '' }}
        run: |
          python .github/codeql/tools/sarif_summary.py \
            --sarif "sarif-results/${{ matrix.language }}.sarif" \
            --cwe-map ".github/codeql/compliance/cwe_to_owasp.csv" \
            --out "summary-${{ matrix.language }}.md" || echo "summary script skipped"
      - name: Upload executive summary
        if: ${{ hashFiles('summary-*.md') != '' }}
        uses: actions/upload-artifact@v4
        with:
          name: exec-summary-${{ matrix.language }}
          path: summary-${{ matrix.language }}.md
          if-no-files-found: warn
YAML

echo "==> Writing CodeQL config"
cat > .github/codeql/config/config.yml <<'YAML'
name: answerchain-advanced-config

paths:
  - src/
  - app/
  - services/

paths-ignore:
  - tests/
  - test/
  - third_party/
  - vendor/
  - '**/*.generated.*'

queries:
  - uses: security-extended
  - uses: security-and-quality
  # Include any .ql files we ship (we keep them language-specific to avoid dbscheme conflicts)
  - include: ./.github/codeql/queries/javascript/**/*.ql
  - include: ./.github/codeql/queries/python/**/*.ql
YAML

echo "==> Adding minimal custom queries (per-language) to keep include-globs valid"

# JavaScript example query (official snippet-style)
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

# Python example query (from CodeQL basics pattern)
cat > .github/codeql/queries/python/redundant-pass-if.ql <<'QL'
/**
 * @name Redundant 'if ...: pass' statement
 * @id py/custom/redundant-pass-if
 * @kind problem
 * @problem.severity warning
 * @tags maintainability
 */

import python

from IfStmt ifs
where ifs.getThen().isPass()
select ifs, "Redundant 'if ...: pass' statement."
QL

echo "==> Compliance mapping CSV (minimal placeholder, safe if unused)"
cat > .github/codeql/compliance/cwe_to_owasp.csv <<'CSV'
cwe_id,owasp_top10
CWE-79,A03:2021
CWE-89,A03:2021
CWE-22,A05:2021
CSV

echo "==> Tooling: requirements + defensive sarif summary"
cat > .github/codeql/tools/requirements.txt <<'REQ'
requests==2.32.4
REQ

cat > .github/codeql/tools/sarif_summary.py <<'PY'
import json, sys, argparse, csv, os

def load_map(path):
    m = {}
    try:
        with open(path, newline='', encoding='utf-8') as f:
            r = csv.DictReader(f)
            for row in r:
                m[row.get('cwe_id','').strip()] = row.get('owasp_top10','').strip()
    except FileNotFoundError:
        pass
    return m

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sarif", required=True)
    ap.add_argument("--cwe-map", required=False, default="")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    if not os.path.exists(args.sarif):
        open(args.out,"w",encoding="utf-8").write("# No SARIF found\n")
        return

    with open(args.sarif, encoding="utf-8") as f:
        sarif = json.load(f)
    cwe_map = load_map(args.cwe_map) if args.cwe_map else {}

    runs = sarif.get("runs", [])
    total = 0
    lines = ["# CodeQL Executive Summary\n"]
    for run in runs:
        tool = run.get("tool", {}).get("driver", {}).get("name","unknown")
        results = run.get("results", [])
        total += len(results)
        lines.append(f"## Tool: {tool}, Findings: {len(results)}")
        for r in results[:100]:  # cap
            msg = r.get("message", {}).get("text", "")
            rule_id = r.get("ruleId","")
            tax = r.get("taxa", []) or r.get("partialFingerprints", {})
            cwes = []
            for t in (r.get("properties", {}).get("tags", []) or []):
                if str(t).startswith("CWE-"):
                    cwes.append(t)
            mapped = [f"{cwe}:{cwe_map.get(cwe,'')}" for cwe in cwes]
            lines.append(f"- {rule_id} :: {msg} {' '.join(mapped)}")
    lines.append(f"\n**Total findings across runs:** {total}\n")
    open(args.out,"w",encoding="utf-8").write("\n".join(lines))

if __name__ == "__main__":
    main()
PY

# Clean up any bad mixed-language qlpack lingering from experiments
if [ -f ".github/codeql/queries/qlpack.yml" ]; then
  mv ".github/codeql/queries/qlpack.yml" ".github/codeql/queries/qlpack.yml.bak.$(timestamp)"
fi

echo "==> Repairing broken submodule config if present"
# If .gitmodules contains a stale SECQ_CLI section or a section without url, remove it
if [ -f ".gitmodules" ]; then
  awk '
    BEGIN{skip=0}
    /^\[submodule/{
      skip=0
      sect=$0
    }
    /^\[submodule "SECQ_CLI"\]/{skip=1}
    skip==1 && /^\[submodule/ {skip=0}
    skip==0 {print}
  ' ".gitmodules" > ".gitmodules.new" || true
  mv ".gitmodules.new" ".gitmodules"
  # Remove from local git config as well
  git config -f .git/config --remove-section submodule.SECQ_CLI 2>/dev/null || true
  # De-gitlink the path if it exists as a submodule entry
  if git ls-files -s SECQ_CLI 2>/dev/null | grep -q "160000"; then
    git rm --cached -f SECQ_CLI || true
  fi
fi

echo "==> Staging and committing"
git add .github
[ -f ".gitmodules" ] && git add .gitmodules || true
git commit -m "CodeQL: fix workflow & config; per-language custom queries; artifact summaries; clean broken submodule SECQ_CLI" || echo "(nothing to commit)"

cat <<'EONEXT'
----------------------------------------------------------------
NEXT STEPS
----------------------------------------------------------------
1) git push
2) Open GitHub → Actions → "CodeQL" → watch the run.
   - You should NOT see:
     • “is not a .ql/.qls/dir/pack” errors (fixed by using include:)
     • “multiple dbschemes” errors (we removed mixed qlpack and per-language includes)
     • submodule fatal for SECQ_CLI (we cleaned it)
3) If your repo *does* have other languages, edit:
   .github/workflows/codeql.yml  → matrix.language: [ "python", "javascript", ... ]
4) Once green, if you want to replace raw uploads with filtered uploads:
   - change Analyze → with: upload: false
   - keep Filter SARIF, and call github/codeql-action/upload-sarif to upload filtered.
   See: https://github.com/orgs/community/discussions/32636
----------------------------------------------------------------
EONEXT

echo "==> Done."
