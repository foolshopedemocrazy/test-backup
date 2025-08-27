# CodeQL Enhanced Security Configuration Deployment Script (PowerShell)
# Deploys complete CodeQL setup with support for JavaScript, Python, Go, and C/C++

Write-Host "🚀 Starting CodeQL Enhanced Security Configuration Deployment..." -ForegroundColor Green
Write-Host "⚠️  This will overwrite existing CodeQL configurations" -ForegroundColor Yellow

# Base directory (relative to repository root)
$BASE_DIR = ".github"

# Create directory structure
Write-Host "📁 Creating directory structure..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "$BASE_DIR\workflows" | Out-Null
New-Item -ItemType Directory -Force -Path "$BASE_DIR\codeql\config" | Out-Null
New-Item -ItemType Directory -Force -Path "$BASE_DIR\codeql\queries\javascript" | Out-Null
New-Item -ItemType Directory -Force -Path "$BASE_DIR\codeql\queries\python" | Out-Null
New-Item -ItemType Directory -Force -Path "$BASE_DIR\codeql\queries\go" | Out-Null
New-Item -ItemType Directory -Force -Path "$BASE_DIR\codeql\queries\cpp" | Out-Null

# ===== MAIN WORKFLOW =====
Write-Host "📝 Creating main CodeQL workflow..." -ForegroundColor Cyan
@'
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
'@ | Set-Content -Path "$BASE_DIR\workflows\codeql.yml" -Encoding UTF8

# ===== JAVASCRIPT CONFIG =====
Write-Host "📝 Creating JavaScript configuration..." -ForegroundColor Cyan
@'
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
'@ | Set-Content -Path "$BASE_DIR\codeql\config\javascript.yml" -Encoding UTF8

# ===== PYTHON CONFIG =====
Write-Host "📝 Creating Python configuration..." -ForegroundColor Cyan
@'
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
'@ | Set-Content -Path "$BASE_DIR\codeql\config\python.yml" -Encoding UTF8

# ===== GO CONFIG =====
Write-Host "📝 Creating Go configuration..." -ForegroundColor Cyan
@'
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
'@ | Set-Content -Path "$BASE_DIR\codeql\config\go.yml" -Encoding UTF8

# ===== C/C++ CONFIG =====
Write-Host "📝 Creating C/C++ configuration..." -ForegroundColor Cyan
@'
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
'@ | Set-Content -Path "$BASE_DIR\codeql\config\cpp.yml" -Encoding UTF8

# ===== NO-OP QUERIES =====
Write-Host "📝 Creating placeholder queries..." -ForegroundColor Cyan

# JavaScript queries
@'
import javascript
from Expr e
where false
select e, "No-op test query."
'@ | Set-Content -Path "$BASE_DIR\codeql\queries\javascript\noop.ql" -Encoding UTF8

@'
- queries:
  - noop.ql
'@ | Set-Content -Path "$BASE_DIR\codeql\queries\javascript\javascript-custom.qls" -Encoding UTF8

# Python queries
@'
import python
from Expr e
where false
select e, "No-op test query."
'@ | Set-Content -Path "$BASE_DIR\codeql\queries\python\noop.ql" -Encoding UTF8

@'
- queries:
  - noop.ql
'@ | Set-Content -Path "$BASE_DIR\codeql\queries\python\python-custom.qls" -Encoding UTF8

# Go queries
@'
import go
from Expr e
where false
select e, "No-op test query."
'@ | Set-Content -Path "$BASE_DIR\codeql\queries\go\noop.ql" -Encoding UTF8

@'
- queries:
  - noop.ql
'@ | Set-Content -Path "$BASE_DIR\codeql\queries\go\go-custom.qls" -Encoding UTF8

# C++ queries
@'
import cpp
from Expr e
where false
select e, "No-op test query."
'@ | Set-Content -Path "$BASE_DIR\codeql\queries\cpp\noop.ql" -Encoding UTF8

@'
- queries:
  - noop.ql
'@ | Set-Content -Path "$BASE_DIR\codeql\queries\cpp\cpp-custom.qls" -Encoding UTF8

# ===== UPDATE DEPENDABOT (preserving existing but adding gomod) =====
Write-Host "📝 Updating Dependabot configuration..." -ForegroundColor Cyan
@'
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "security"

  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "security"

  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "security"

  - package-ecosystem: "composer"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "security"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "security"
'@ | Set-Content -Path "$BASE_DIR\dependabot.yml" -Encoding UTF8

# ===== VERIFICATION =====
Write-Host ""
Write-Host "✅ CodeQL Enhanced Security Configuration deployed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Created/Updated files:" -ForegroundColor Yellow
Write-Host "  - $BASE_DIR\workflows\codeql.yml"
Write-Host "  - $BASE_DIR\codeql\config\javascript.yml"
Write-Host "  - $BASE_DIR\codeql\config\python.yml"
Write-Host "  - $BASE_DIR\codeql\config\go.yml"
Write-Host "  - $BASE_DIR\codeql\config\cpp.yml"
Write-Host "  - Query files for all languages"
Write-Host "  - $BASE_DIR\dependabot.yml (updated with gomod)"
Write-Host ""
Write-Host "🔍 Configured languages:" -ForegroundColor Yellow
Write-Host "  - JavaScript/TypeScript"
Write-Host "  - Python"
Write-Host "  - Go"
Write-Host "  - C/C++"
Write-Host ""
Write-Host "📌 Next steps:" -ForegroundColor Cyan
Write-Host "  1. Review the configurations"
Write-Host "  2. Remove old Java config: Remove-Item .github\codeql\config\java.yml -Force"
Write-Host "  3. Commit changes: git add .github/ && git commit -m 'Enhanced CodeQL security configuration'"
Write-Host "  4. Push to trigger analysis: git push"
Write-Host ""
Write-Host "💡 Tips:" -ForegroundColor Magenta
Write-Host "  - If a language isn't in your repo, CodeQL will skip it automatically"
Write-Host "  - You can disable languages by commenting them out in the workflow matrix"
Write-Host "  - Custom security queries can be added to the respective queries/ directories"
Write-Host ""