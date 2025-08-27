#!/usr/bin/env bash
set -euo pipefail

RED=$'\033[1;31m'; GRN=$'\033[1;32m'; YLW=$'\033[1;33m'; NC=$'\033[0m'
pass() { echo "${GRN}[OK]${NC} $*"; }
warn() { echo "${YLW}[WARN]${NC} $*"; }
fail() { echo "${RED}[FAIL]${NC} $*"; exit 1; }

# Ensure inside a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Run from your repository root (no .git found)."

ROOT="."
GH=".github"
WF="${GH}/workflows/codeql.yml"
CFG="${GH}/codeql/config.yml"
QDIR="${GH}/codeql/queries"
QLPACK="${QDIR}/qlpack.yml"
QEX="${QDIR}/example-javascript.ql"
COMP="${GH}/codeql/compliance/cwe_to_owasp.csv"
COMPREADME="${GH}/codeql/compliance/README.md"
TOOL="${GH}/codeql/tools/sarif_summary.py"
TOPREADME="${GH}/CODEQL_README.md"

# 1) Presence checks
for p in "$GH" "$GH/workflows" "$GH/codeql" "$QDIR" "${GH}/codeql/compliance" "${GH}/codeql/tools"; do
  [ -d "$p" ] || fail "Missing directory: $p"
done
pass "Directories present."

for f in "$WF" "$CFG" "$QLPACK" "$QEX" "$COMP" "$COMPREADME" "$TOOL" "$TOPREADME"; do
  [ -f "$f" ] || fail "Missing file: $f"
done
pass "Files present."

# 2) Content sanity checks (simple greps)
grep -q 'name: CodeQL' "$WF" || fail "Workflow missing 'name: CodeQL'."
grep -q 'github/codeql-action/init@v3' "$WF" || fail "Workflow missing codeql init@v3."
grep -q 'github/codeql-action/analyze@v3' "$WF" || fail "Workflow missing codeql analyze@v3."
grep -q 'advanced-security/set-codeql-language-matrix@v1' "$WF" || fail "Workflow missing language matrix step."
grep -q 'upload-sarif@v3' "$WF" || fail "Workflow missing upload-sarif step."
pass "Workflow content looks correct."

grep -q '^paths:' "$CFG" || fail "config.yml missing 'paths:'"
grep -q '^paths-ignore:' "$CFG" || fail "config.yml missing 'paths-ignore:'"
grep -q 'queries:' "$CFG" || fail "config.yml missing 'queries:'"
grep -q 'security-extended' "$CFG" || fail "config.yml missing 'security-extended' query suite."
grep -q 'security-and-quality' "$CFG" || fail "config.yml missing 'security-and-quality' query suite."
pass "Config content looks correct."

grep -q 'name:' "$QLPACK" || fail "qlpack.yml missing name."
grep -q 'dependencies:' "$QLPACK" || fail "qlpack.yml missing dependencies."
pass "qlpack.yml looks correct."

grep -q '@id js/insecure-sql-concat-demo' "$QEX" || fail "example-javascript.ql missing @id."
grep -q 'external/cwe/cwe-89' "$QEX" || fail "example-javascript.ql missing CWE tag."
pass "Example query content looks correct."

grep -q '\*_default' "$COMP" || fail "cwe_to_owasp.csv missing *_default fallback mapping."
pass "Compliance mapping CSV looks correct."

# 3) Optional YAML validation if tools available
if command -v yq >/dev/null 2>&1; then
  yq '.' "$WF" >/dev/null && pass "Workflow YAML parsed by yq."
  yq '.' "$CFG" >/dev/null && pass "Config YAML parsed by yq."
else
  warn "yq not found; skipping strict YAML parsing."
fi

if command -v yamllint >/dev/null 2>&1; then
  yamllint -d "{extends: default, rules: {line-length: {max: 180}}}" "$WF" "$CFG" && pass "yamllint passed."
else
  warn "yamllint not found; skipping lint."
fi

# 4) Run the sarif_summary.py tool against a synthetic SARIF
PYTHON_BIN="${PYTHON_BIN:-python}"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "Python not found. Install Python or set PYTHON_BIN."

TMP_SARIF="$(mktemp -t demo_sarif.XXXXXX).sarif"
TMP_OUT="$(mktemp -t demo_summary.XXXXXX).md"

cat > "$TMP_SARIF" <<'JSON'
{
  "version": "2.1.0",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "CodeQL",
          "rules": [
            {
              "id": "js/insecure-sql-concat-demo",
              "shortDescription": {"text": "Demo rule"},
              "properties": {
                "security-severity": "7.5",
                "tags": ["external/cwe/cwe-89"]
              }
            }
          ]
        }
      },
      "results": [
        {
          "ruleId": "js/insecure-sql-concat-demo",
          "message": {"text": "Insecure concatenation"},
          "baselineState": "new",
          "properties": {"security-severity": "8.1"}
        }
      ]
    }
  ]
}
JSON

chmod +x "$TOOL" || true
"$PYTHON_BIN" "$TOOL" --sarif "$TMP_SARIF" --cwe-map "$COMP" --out "$TMP_OUT"

[ -s "$TMP_OUT" ] || fail "sarif_summary.py did not produce output."
grep -q '## Alerts by Severity' "$TMP_OUT" || fail "Summary missing severity table."
grep -q '## Alerts by OWASP Group' "$TMP_OUT" || fail "Summary missing OWASP table."
pass "sarif_summary.py produced a valid summary."

# 5) Git checks
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ -n "$BRANCH" ] || fail "Could not determine current branch."
pass "On branch: $BRANCH"

if git log -1 --pretty=%s | grep -qi 'codeql'; then
  pass "Last commit message references CodeQL."
else
  warn "Last commit message does not reference CodeQL (this is OK if you skipped auto-commit)."
fi

# 6) Final
pass "All verification checks passed."
echo "You’re good to go. Open GitHub → Security → Code scanning alerts after your next run."
