#!/bin/bash

# CodeQL Enhanced Security Configuration Deployment Script
# Deploys complete CodeQL setup with support for JavaScript, Python, Go, and C/C++

set -e  # Exit on error

echo "🚀 Starting CodeQL Enhanced Security Configuration Deployment..."
echo "⚠️  This will overwrite existing CodeQL configurations"

# Base directory (relative to repository root)
BASE_DIR=".github"

# Create directory structure
echo "📁 Creating directory structure..."
mkdir -p "$BASE_DIR/workflows"
mkdir -p "$BASE_DIR/codeql/config"
mkdir -p "$BASE_DIR/codeql/queries/javascript"
mkdir -p "$BASE_DIR/codeql/queries/python"
mkdir -p "$BASE_DIR/codeql/queries/go"
mkdir -p "$BASE_DIR/codeql/queries/cpp"

# ===== MAIN WORKFLOW =====
echo "📝 Creating main CodeQL workflow..."
cat > "$BASE_DIR/workflows/codeql.yml" << 'EOF'
name: "CodeQL Security Analysis"

on:
  push:
    branches: ["main", "master", "develop"]
    paths-ignore:
      - '**/*.md'
      - 'docs/**'
  pull_request:
    branches: ["main", "master", "develop"]
    paths-ignore:
      - '**/*.md'
      - 'docs/**'
  schedule:
    - cron: '14 3 * * 1'
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
    name: Analyze (${{ matrix.language }})
    runs-on: ubuntu-latest
    timeout-minutes: 45

    strategy:
      fail-fast: false
      matrix:
        language:
          - javascript
          - python
          - go
          - cpp

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          config-file: ./.github/codeql/config/${{ matrix.language }}.yml

      - name: Autobuild
        uses: github/codeql-action/autobuild@v3

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
EOF

# ===== JAVASCRIPT CONFIG =====
echo "📝 Creating JavaScript configuration..."
cat > "$BASE_DIR/codeql/config/javascript.yml" << 'EOF'
name: "CodeQL JavaScript Configuration"

queries:
  - uses: security-extended
  - uses: security-and-quality

paths:
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.mjs"

paths-ignore:
  - "node_modules"
  - "test"
  - "tests"
  - "**/*.test.*"
  - "**/*.spec.*"
  - "**/*.min.js"
  - "dist"
  - "build"

disable-default-path-filters: true
EOF

# ===== PYTHON CONFIG =====
echo "📝 Creating Python configuration..."
cat > "$BASE_DIR/codeql/config/python.yml" << 'EOF'
name: "CodeQL Python Configuration"

queries:
  - uses: security-extended
  - uses: security-and-quality

paths:
  - "**/*.py"

paths-ignore:
  - "test"
  - "tests"
  - "**/*_test.py"
  - "**/test_*.py"
  - "venv"
  - ".venv"
  - "__pycache__"
  - "**/*.egg-info"

disable-default-path-filters: true
EOF

# ===== GO CONFIG =====
echo "📝 Creating Go configuration..."
cat > "$BASE_DIR/codeql/config/go.yml" << 'EOF'
name: "CodeQL Go Configuration"

queries:
  - uses: security-extended
  - uses: security-and-quality

paths:
  - "**/*.go"

paths-ignore:
  - "vendor"
  - "**/*_test.go"
  - "**/*.pb.go"

disable-default-path-filters: true
EOF

# ===== C/C++ CONFIG =====
echo "📝 Creating C/C++ configuration..."
cat > "$BASE_DIR/codeql/config/cpp.yml" << 'EOF'
name: "CodeQL C/C++ Configuration"

queries:
  - uses: security-extended
  - uses: security-and-quality

paths:
  - "**/*.c"
  - "**/*.cpp"
  - "**/*.cc"
  - "**/*.cxx"
  - "**/*.h"
  - "**/*.hpp"

paths-ignore:
  - "build"
  - "vendor"
  - "third_party"
  - "**/*.generated.*"

disable-default-path-filters: true
EOF

# ===== NO-OP QUERIES (Required for custom query dirs) =====
echo "📝 Creating placeholder queries..."

# JavaScript no-op query
cat > "$BASE_DIR/codeql/queries/javascript/noop.ql" << 'EOF'
import javascript
from Expr e
where false
select e, "No-op test query."
EOF

# JavaScript query suite
cat > "$BASE_DIR/codeql/queries/javascript/javascript-custom.qls" << 'EOF'
- queries:
  - noop.ql
EOF

# Python no-op query
cat > "$BASE_DIR/codeql/queries/python/noop.ql" << 'EOF'
import python
from Expr e
where false
select e, "No-op test query."
EOF

# Python query suite
cat > "$BASE_DIR/codeql/queries/python/python-custom.qls" << 'EOF'
- queries:
  - noop.ql
EOF

# Go no-op query
cat > "$BASE_DIR/codeql/queries/go/noop.ql" << 'EOF'
import go
from Expr e
where false
select e, "No-op test query."
EOF

# Go query suite
cat > "$BASE_DIR/codeql/queries/go/go-custom.qls" << 'EOF'
- queries:
  - noop.ql
EOF

# C++ no-op query
cat > "$BASE_DIR/codeql/queries/cpp/noop.ql" << 'EOF'
import cpp
from Expr e
where false
select e, "No-op test query."
EOF

# C++ query suite
cat > "$BASE_DIR/codeql/queries/cpp/cpp-custom.qls" << 'EOF'
- queries:
  - noop.ql
EOF

# ===== OPTIONAL: Keep existing Dependabot if not present =====
if [ ! -f "$BASE_DIR/dependabot.yml" ]; then
  echo "📝 Creating Dependabot configuration..."
  cat > "$BASE_DIR/dependabot.yml" << 'EOF'
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"

  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"

  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
EOF
fi

# ===== VERIFICATION =====
echo ""
echo "✅ CodeQL Enhanced Security Configuration deployed successfully!"
echo ""
echo "📋 Created/Updated files:"
echo "  - $BASE_DIR/workflows/codeql.yml"
echo "  - $BASE_DIR/codeql/config/javascript.yml"
echo "  - $BASE_DIR/codeql/config/python.yml"
echo "  - $BASE_DIR/codeql/config/go.yml"
echo "  - $BASE_DIR/codeql/config/cpp.yml"
echo "  - Query files for all languages"
echo ""
echo "🔍 Configured languages:"
echo "  - JavaScript/TypeScript"
echo "  - Python"
echo "  - Go"
echo "  - C/C++"
echo ""
echo "📌 Next steps:"
echo "  1. Review the configurations"
echo "  2. Commit changes: git add .github/ && git commit -m 'Enhanced CodeQL security configuration'"
echo "  3. Push to trigger analysis: git push"
echo ""
echo "💡 Tips:"
echo "  - If a language isn't in your repo, CodeQL will skip it automatically"
echo "  - You can disable languages by commenting them out in the workflow matrix"
echo "  - Custom security queries can be added to the respective queries/ directories"
echo ""