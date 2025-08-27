#!/usr/bin/env bash
set -Eeuo pipefail

here="$(pwd)"
say() { printf '[-] %s\n' "$*"; }
ok()  { printf '[OK] %s\n' "$*"; }

req_files=(
  ".github/workflows/codeql.yml"
  ".github/codeql/config/javascript.yml"
  ".github/codeql/config/python.yml"
  ".github/codeql/config/java.yml"
)

ensure_dirs() {
  mkdir -p ".github/workflows"
  mkdir -p ".github/codeql/config"
}

write_file() {
  local path="$1" ; shift
  local content="$*"
  if [ -f "$path" ]; then
    ok "exists: $path (leaving as-is)"
  else
    say "create: $path"
    printf '%s' "$content" > "$path"
  fi
}

main() {
  say "Repo: $here"
  ensure_dirs

  # --- workflow ---
  write_file ".github/workflows/codeql.yml" "$(cat <<'YML'
name: CodeQL

on:
  push:
    branches: [ "main", "master" ]
  pull_request:
    branches: [ "main", "master" ]
  schedule:
    - cron: "14 3 * * 1"
  workflow_dispatch:

permissions:
  contents: read
  security-events: write

concurrency:
  group: codeql-${{ github.ref }}
  cancel-in-progress: true

jobs:
  analyze:
    name: analyze (${{ matrix.language }})
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        language: [ javascript, python, java ]

    steps:
      - uses: actions/checkout@v4
        with:
          submodules: false

      - name: Setup Java (for Java only)
        if: matrix.language == 'java'
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          config-file: ./.github/codeql/config/${{ matrix.language }}.yml

      - name: Autobuild (Java only)
        if: matrix.language == 'java'
        uses: github/codeql-action/autobuild@v3

      - name: Analyze
        uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
YML
)"

  # --- configs ---
  write_file ".github/codeql/config/javascript.yml" "$(cat <<'YML'
name: codeql-config-javascript
queries:
  - uses: security-extended
  - uses: security-and-quality
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
YML
)"

  write_file ".github/codeql/config/python.yml" "$(cat <<'YML'
name: codeql-config-python
queries:
  - uses: security-extended
  - uses: security-and-quality
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
YML
)"

  write_file ".github/codeql/config/java.yml" "$(cat <<'YML'
name: codeql-config-java
queries:
  - uses: security-extended
  - uses: security-and-quality
paths:
  - src/
paths-ignore:
  - '**/target/**'
  - '**/*.generated.*'
YML
)"

  # --- verify ---
  echo
  say "Verifying expected files exist & basic contents…"
  local missing=0
  for f in "${req_files[@]}"; do
    if [ -f "$f" ]; then ok "$f"; else say "MISSING: $f"; missing=1; fi
  done

  grep -q "language: \[ javascript, python, java \]" ".github/workflows/codeql.yml" \
    && ok "matrix languages present in workflow" \
    || { say "matrix languages not found in workflow"; missing=1; }

  grep -q 'config/\${{ matrix.language }}.yml' ".github/workflows/codeql.yml" \
    && ok "per-language config path wired" \
    || { say "per-language config path missing"; missing=1; }

  if [ $missing -eq 0 ]; then
    ok "Verification passed. Commit & push to run CodeQL."
    exit 0
  else
    say "Verification FAILED — see messages above."
    exit 1
  fi
}

main "$@"
