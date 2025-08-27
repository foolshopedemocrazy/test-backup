#!/usr/bin/env bash
# fix_codeql_updates.sh
# -----------------------------------------------------------------------------
# Purpose: Apply robust CodeQL workflow fixes:
# - Add required inputs to the language-detection step
# - Switch to per-language CodeQL configs (no mixed dbschemes)
# - Create one custom query pack per language (javascript / python)
# - Keep SARIF filtering + executive summary utilities
# - Migrate old files; back up anything replaced
#
# Usage (run from repo root):
#   bash fix_codeql_updates.sh
#
# Env toggles:
#   DO_GIT_COMMIT=0            # skip git commit
#   BRANCH_NAME=my/codeql-fix  # custom branch name
# -----------------------------------------------------------------------------
set -euo pipefail

# -------- Pretty logging
GRN=$'\033[1;32m'; YLW=$'\033[1;33m'; RED=$'\033[1;31m'; NC=$'\033[0m'
say()  { printf "${GRN}[OK]${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
err()  { printf "${RED}[ERR]${NC} %s\n" "$*" >&2; }

# -------- Settings
BRANCH_NAME="${BRANCH_NAME:-chore/codeql-fix-updates}"
DO_GIT_COMMIT="${DO_GIT_COMMIT:-1}"

BACKUP_ROOT=".github/backups"
TIMESTAMP="$(date -u +'%Y%m%dT%H%M%SZ')"
BACKUP_DIR="${BACKUP_ROOT}/fix-${TIMESTAMP}"

WF_DIR=".github/workflows"
WF_FILE="${WF_DIR}/codeql.yml"

CODEQL_ROOT=".github/codeql"
CFG_DIR="${CODEQL_ROOT}/config"
Q_ROOT="${CODEQL_ROOT}/queries"
Q_JS_DIR="${Q_ROOT}/javascript"
Q_PY_DIR="${Q_ROOT}/python"
TOOL_DIR="${CODEQL_ROOT}/tools"
COMP_DIR="${CODEQL_ROOT}/compliance"

# -------- Guards
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  err "Run this script from your repository root ('.git' not found)."
  exit 1
}

# -------- Prepare dirs
mkdir -p "${WF_DIR}" "${CFG_DIR}" "${Q_JS_DIR}" "${Q_PY_DIR}" "${TOOL_DIR}" "${COMP_DIR}" "${BACKUP_ROOT}"

# -------- Back up legacy/mixed items (we *move* them)
backup_if_exists() {
  local path="$1"
  if [ -e "$path" ]; then
    mkdir -p "${BACKUP_DIR}"
    warn "Backing up: $path -> ${BACKUP_DIR}/"
    mv "$path" "${BACKUP_DIR}/"
  fi
}

# Legacy mixed-case folder
[ -d ".github/CodeQL" ] && backup_if_exists ".github/CodeQL"

# Old single config file (we move it out since we now use per-language configs)
[ -f "${CODEQL_ROOT}/config.yml" ] && backup_if_exists "${CODEQL_ROOT}/config.yml"

# Old mixed-language pack (root cause of dbscheme conflict) → move it out
[ -f "${Q_ROOT}/qlpack.yml" ] && backup_if_exists "${Q_ROOT}/qlpack.yml"

# Backup existing workflow (we overwrite it)
[ -f "${WF_FILE}" ] && backup_if_exists "${WF_FILE}"

# -------- Write corrected workflow (Option A + per-language config path)
cat > "${WF_FILE}" <<'YAML'
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
  detect-languages:
    runs-on: ubuntu-latest
    outputs:
      langs: ${{ steps.set.outputs.languages }}
    steps:
      - name: Detect CodeQL languages
        id: set
        uses: advanced-security/set-codeql-language-matrix@v1
        with:
          access-token: ${{ secrets.GITHUB_TOKEN }}
          endpoint: ${{ github.api_url }}/repos/${{ github.repository }}/languages
          # Exclude languages you don't want scanned until you add packs/configs for them
          exclude: "go,cpp,ruby,swift"

  analyze:
    needs: detect-languages
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        language: ${{ fromJson(needs.detect-languages.outputs.langs) }}

    steps:
      - uses: actions/checkout@v4

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          # language-scoped config prevents pack/dbscheme mismatches
          config-file: ./.github/codeql/config/${{ matrix.language }}.yml

      # For compiled languages this may build; for interpreted it's a no-op
      - name: Autobuild
        uses: github/codeql-action/autobuild@v3

      - name: Analyze (defer upload)
        uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
          output: sarif-results
          upload: failure-only

      - name: Filter SARIF (paths & rule IDs)
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

      - name: Upload filtered SARIF
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: sarif-results/${{ matrix.language }}.filtered.sarif

      - name: Persist filtered SARIF (audit trail)
        uses: actions/upload-artifact@v4
        with:
          name: sarif-${{ matrix.language }}
          path: sarif-results/${{ matrix.language }}.filtered.sarif

      - name: Executive summary (Markdown)
        run: |
          python .github/codeql/tools/sarif_summary.py \
            --sarif "sarif-results/${{ matrix.language }}.filtered.sarif" \
            --cwe-map ".github/codeql/compliance/cwe_to_owasp.csv" \
            --out "summary-${{ matrix.language }}.md"
        shell: bash

      - name: Upload executive summary
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: exec-summary-${{ matrix.language }}
          path: summary-${{ matrix.language }}.md
YAML
say "Wrote ${WF_FILE}"

# -------- Per-language configs
cat > "${CFG_DIR}/python.yml" <<'YAML'
name: advanced-repo-config-python
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
  - uses: ./.github/codeql/queries/python
YAML
say "Wrote ${CFG_DIR}/python.yml"

cat > "${CFG_DIR}/javascript.yml" <<'YAML'
name: advanced-repo-config-javascript
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
  - uses: ./.github/codeql/queries/javascript
YAML
say "Wrote ${CFG_DIR}/javascript.yml"

# -------- Per-language packs
cat > "${Q_PY_DIR}/qlpack.yml" <<'YAML'
name: answerchain.python-queries
version: 0.0.1
library: false
dependencies:
  codeql/python-all: "*"
YAML
say "Wrote ${Q_PY_DIR}/qlpack.yml"

cat > "${Q_JS_DIR}/qlpack.yml" <<'YAML'
name: answerchain.javascript-queries
version: 0.0.1
library: false
dependencies:
  codeql/javascript-all: "*"
YAML
say "Wrote ${Q_JS_DIR}/qlpack.yml"

# -------- Seed example queries if none exist
seed_example_if_empty() {
  local dir="$1" lang="$2"
  if ! ls -1 "${dir}"/*.ql >/dev/null 2>&1; then
    case "$lang" in
      python)
        cat > "${dir}/find-todo-comments.ql" <<'QL'
import python
/**
 * Flags TODO/FIXME style comments.
 */
from Comment c, string t
where t = c.getText() and
      (t.regexpMatch("(?i)\\bTODO\\b") or t.regexpMatch("(?i)\\bFIXME\\b"))
select c, "Possible task marker in comment."
QL
        ;;
      javascript)
        cat > "${dir}/find-todo-comments.ql" <<'QL'
import javascript
/**
 * Flags TODO/FIXME style comments.
 */
from Comment c, string t
where t = c.getText() and
      (t.regexpMatch("(?i)\\bTODO\\b") or t.regexpMatch("(?i)\\bFIXME\\b"))
select c, "Possible task marker in comment."
QL
        ;;
    esac
    say "Seeded example query in ${dir}"
  fi
}
seed_example_if_empty "${Q_PY_DIR}" "python"
seed_example_if_empty "${Q_JS_DIR}" "javascript"

# -------- Migrate any loose top-level queries to language folders
# Heuristic: inspect "import <lang>" to decide destination
shopt -s nullglob
for q in "${Q_ROOT}"/*.ql; do
  if grep -qE '^import[[:space:]]+javascript' "$q"; then
    dest="${Q_JS_DIR}/$(basename "$q")"
    warn "Moving JS query $(basename "$q") -> ${Q_JS_DIR}/"
    mv "$q" "$dest"
  elif grep -qE '^import[[:space:]]+python' "$q"; then
    dest="${Q_PY_DIR}/$(basename "$q")"
    warn "Moving PY query $(basename "$q") -> ${Q_PY_DIR}/"
    mv "$q" "$dest"
  else
    # default to javascript if unknown (safer than leaving it unused)
    dest="${Q_JS_DIR}/$(basename "$q")"
    warn "Unknown language for $(basename "$q"); defaulting to javascript/"
    mv "$q" "$dest"
  fi
done
shopt -u nullglob

# -------- Ensure compliance + tools exist (create minimal if missing)
if [ ! -f "${COMP_DIR}/cwe_to_owasp.csv" ]; then
  cat > "${COMP_DIR}/cwe_to_owasp.csv" <<'CSV'
CWE,OWASP
79,A03: Injection
89,A03: Injection
200,A01: Broken Access Control
22,A05: Security Misconfiguration
CSV
  say "Wrote ${COMP_DIR}/cwe_to_owasp.csv"
fi

if [ ! -f "${TOOL_DIR}/sarif_summary.py" ]; then
  cat > "${TOOL_DIR}/sarif_summary.py" <<'PY'
#!/usr/bin/env python3
import argparse, json, csv
p = argparse.ArgumentParser()
p.add_argument("--sarif", required=True)
p.add_argument("--cwe-map", required=True)
p.add_argument("--out", required=True)
a = p.parse_args()

cwe_map = {}
with open(a.cwe_map, newline="", encoding="utf-8") as f:
    r = csv.DictReader(f)
    for row in r:
        cwe_map[row["CWE"].strip()] = row["OWASP"].strip()

with open(a.sarif, encoding="utf-8") as f:
    sarif = json.load(f)

rows = []
for run in sarif.get("runs", []):
    driver = (run.get("tool") or {}).get("driver") or {}
    rules = {r.get("id"): r for r in (driver.get("rules") or [])}
    for res in run.get("results", []) or []:
        rid = res.get("ruleId") or ""
        sev = (res.get("properties") or {}).get("security-severity") or res.get("level") or "warning"
        msg = (res.get("message") or {}).get("text","")
        tags = (rules.get(rid,{}).get("properties") or {}).get("tags",[])
        cwes = [t.split("-")[-1] for t in tags if t.upper().startswith("CWE-")]
        owasp = "; ".join(sorted({cwe_map.get(c,"") for c in cwes if c in cwe_map})) or "-"
        rows.append((sev, rid, owasp, msg[:120].replace("|","\\|")))

rows.sort(key=lambda x: x[0], reverse=True)
with open(a.out, "w", encoding="utf-8") as f:
    f.write("# Executive security summary\n\n")
    f.write("| Severity | Rule | OWASP | Message |\n|---|---|---|---|\n")
    for sev, rid, owasp, msg in rows:
        f.write(f"| {sev} | `{rid}` | {owasp} | {msg} |\n")
print(f"Wrote {a.out}")
PY
  chmod +x "${TOOL_DIR}/sarif_summary.py"
  say "Wrote ${TOOL_DIR}/sarif_summary.py"
fi

# -------- Git commit (optional)
if [ "${DO_GIT_COMMIT}" = "1" ]; then
  CUR_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [ "${CUR_BRANCH}" != "${BRANCH_NAME}" ]; then
    if git rev-parse --verify "${BRANCH_NAME}" >/dev/null 2>&1; then
      git checkout "${BRANCH_NAME}"
    else
      git checkout -b "${BRANCH_NAME}"
    fi
  fi

  git add "${WF_FILE}" \
          "${CFG_DIR}/python.yml" "${CFG_DIR}/javascript.yml" \
          "${Q_JS_DIR}/qlpack.yml" "${Q_PY_DIR}/qlpack.yml" \
          "${Q_JS_DIR}"/*.ql "${Q_PY_DIR}"/*.ql

  [ -f "${COMP_DIR}/cwe_to_owasp.csv" ] && git add "${COMP_DIR}/cwe_to_owasp.csv"
  [ -f "${TOOL_DIR}/sarif_summary.py" ] && git add "${TOOL_DIR}/sarif_summary.py"
  [ -d "${BACKUP_DIR}" ] && git add "${BACKUP_DIR}"

  if git diff --cached --quiet; then
    warn "Nothing staged for commit (files may already match)."
  else
    git commit -m "fix(codeql): add required language-matrix inputs, per-language configs & packs; keep SARIF filtering/reporting"
    say "Committed changes on branch '${BRANCH_NAME}'."
    say "Next: git push -u origin ${BRANCH_NAME}"
  fi
else
  warn "Skipping git commit (DO_GIT_COMMIT=${DO_GIT_COMMIT}). Files written to working tree."
fi

say "All done. Re-run the CodeQL workflow from GitHub Actions."
