#!/bin/bash

# CodeQL Configuration Auto-Update Script
# This script safely updates CodeQL files while preserving existing structure
# Compatible with Git Bash on Windows and Linux/Mac

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_DIR=".github"
BACKUP_PREFIX="codeql-update"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${GITHUB_DIR}/backups/${BACKUP_PREFIX}-${TIMESTAMP}"

echo -e "${BLUE}🚀 CodeQL Configuration Auto-Update Script${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Check if we're in the right directory
if [[ ! -d ".git" ]]; then
    echo -e "${RED}❌ Error: Not in a git repository root directory${NC}"
    echo -e "${YELLOW}   Please run this script from your project root (where .git folder exists)${NC}"
    exit 1
fi

# Check for existing .github directory
if [[ ! -d "${GITHUB_DIR}" ]]; then
    echo -e "${YELLOW}⚠️  .github directory not found, creating it...${NC}"
    mkdir -p "${GITHUB_DIR}"
fi

echo -e "${PURPLE}📁 Current directory: $(pwd)${NC}"
echo -e "${PURPLE}📁 GitHub directory: ${GITHUB_DIR}${NC}"
echo ""

# Function to create backup
create_backup() {
    echo -e "${BLUE}💾 Creating backup...${NC}"
    
    # Create backup directory
    mkdir -p "${BACKUP_DIR}"
    
    # Backup existing files if they exist
    if [[ -d "${GITHUB_DIR}/workflows" ]]; then
        cp -r "${GITHUB_DIR}/workflows" "${BACKUP_DIR}/" 2>/dev/null || true
        echo -e "${GREEN}   ✅ Backed up workflows directory${NC}"
    fi
    
    if [[ -d "${GITHUB_DIR}/codeql" ]]; then
        cp -r "${GITHUB_DIR}/codeql" "${BACKUP_DIR}/" 2>/dev/null || true
        echo -e "${GREEN}   ✅ Backed up codeql directory${NC}"
    fi
    
    # Create backup info file
    cat > "${BACKUP_DIR}/backup_info.txt" << EOF
Backup created: $(date)
Script version: Auto-Update v1.0
Original location: $(pwd)
Backed up from: ${GITHUB_DIR}

Files backed up:
$(find "${BACKUP_DIR}" -type f 2>/dev/null | sed 's|^|  - |' || echo "  - No files found")
EOF
    
    echo -e "${GREEN}   ✅ Backup created at: ${BACKUP_DIR}${NC}"
    echo ""
}

# Function to create directory structure
create_directories() {
    echo -e "${BLUE}📁 Creating directory structure...${NC}"
    
    # Create required directories (using lowercase for Linux compatibility)
    mkdir -p "${GITHUB_DIR}/workflows"
    mkdir -p "${GITHUB_DIR}/codeql/config"
    
    # Keep existing additional directories (queries, tools, compliance) if they exist
    # but ensure they're not interfering
    
    echo -e "${GREEN}   ✅ Directory structure created${NC}"
    echo ""
}

# Function to write workflow file
write_workflow_file() {
    local file="${GITHUB_DIR}/workflows/codeql.yml"
    echo -e "${BLUE}📝 Writing workflow file: ${file}${NC}"
    
    cat > "${file}" << 'EOF'
name: "CodeQL Security Analysis"

on:
  push:
    branches: ["main", "master", "develop"]
    paths-ignore:
      - '**/*.md'
      - '**/*.txt'
      - 'docs/**'
  pull_request:
    branches: ["main", "master", "develop"]
    paths-ignore:
      - '**/*.md'
      - '**/*.txt'
      - 'docs/**'
  schedule:
    # Run at 3:14 AM UTC every Monday
    - cron: '14 3 * * 1'
  workflow_dispatch:
    inputs:
      languages:
        description: 'Languages to analyze (comma-separated: javascript,python,java)'
        required: false
        default: 'javascript,python,java'

permissions:
  contents: read
  security-events: write
  actions: read

concurrency:
  group: codeql-${{ github.ref }}-${{ github.workflow }}
  cancel-in-progress: true

env:
  # Fail fast on errors
  CODEQL_EXTRACTOR_JAVA_HEAP_SIZE: 4096
  CODEQL_EXTRACTOR_JAVA_MAX_HEAP: 8192

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
          - java
        include:
          - language: javascript
            build-mode: none
          - language: python
            build-mode: none
          - language: java
            build-mode: autobuild

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 2
          submodules: false

      - name: Setup Java (Java analysis only)
        if: matrix.language == 'java'
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
          cache: 'maven'

      - name: Setup Node.js (JavaScript analysis only)
        if: matrix.language == 'javascript'
        uses: actions/setup-node@v4
        with:
          node-version: '18'
          cache: 'npm'
          cache-dependency-path: '**/package-lock.json'

      - name: Setup Python (Python analysis only)
        if: matrix.language == 'python'
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
          cache: 'pip'

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          config-file: ./.github/codeql/config/${{ matrix.language }}.yml
          # Use latest CodeQL bundle
          tools: latest
          # Disable default setup to use our explicit config
          setup-python-dependencies: false

      - name: Autobuild (compiled languages only)
        if: matrix.build-mode == 'autobuild'
        uses: github/codeql-action/autobuild@v3

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
          # Upload results even if there are errors in other languages
          upload: true
          # Add debugging for troubleshooting
          ram: 6144
          threads: 2

      - name: Upload SARIF results (backup)
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: codeql-results-${{ matrix.language }}
          path: /home/runner/work/_temp/codeql_databases/
          retention-days: 30
EOF
    
    echo -e "${GREEN}   ✅ Workflow file written${NC}"
}

# Function to write JavaScript config
write_javascript_config() {
    local file="${GITHUB_DIR}/codeql/config/javascript.yml"
    echo -e "${BLUE}📝 Writing JavaScript config: ${file}${NC}"
    
    cat > "${file}" << 'EOF'
name: "CodeQL JavaScript Configuration"

# Query suites to run
queries:
  - uses: security-extended
  - uses: security-and-quality

# Paths to include in analysis
paths:
  - "src"
  - "app"
  - "lib" 
  - "services"
  - "components"
  - "pages"
  - "utils"
  - "helpers"
  - "scripts"
  # Include common JS/TS file extensions explicitly
  - "**/*.js"
  - "**/*.jsx"  
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.mjs"
  - "**/*.cjs"

# Paths to exclude from analysis  
paths-ignore:
  # Test directories
  - "test"
  - "tests"
  - "__tests__"
  - "**/*.test.*"
  - "**/*.spec.*"
  - "**/__tests__/**"
  - "**/test/**"
  - "**/tests/**"
  # Build and dependency directories
  - "node_modules"
  - "dist"
  - "build" 
  - "out"
  - ".next"
  - ".nuxt"
  - "coverage"
  # Third-party and vendor code
  - "vendor"
  - "third_party"
  - "external"
  - "vendors"
  # Generated files
  - "**/*.generated.*"
  - "**/*.min.js"
  - "**/*.bundle.js"
  - "**/bundle.*"
  # Configuration files that might contain code but aren't app logic
  - "webpack.config.js"
  - "rollup.config.js"
  - "vite.config.js"
  - ".eslintrc.js"
  - "jest.config.js"
  # Documentation
  - "docs"
  - "documentation"
  - "*.md"

# Disable default paths to use our explicit configuration
disable-default-path-filters: true

# Additional extraction options
extraction:
  javascript:
    # Extract dependencies for better analysis
    externs: true
    # Include TypeScript definition files
    typescript: auto
EOF
    
    echo -e "${GREEN}   ✅ JavaScript config written${NC}"
}

# Function to write Python config
write_python_config() {
    local file="${GITHUB_DIR}/codeql/config/python.yml"
    echo -e "${BLUE}📝 Writing Python config: ${file}${NC}"
    
    cat > "${file}" << 'EOF'
name: "CodeQL Python Configuration"

# Query suites to run
queries:
  - uses: security-extended  
  - uses: security-and-quality

# Paths to include in analysis
paths:
  - "src"
  - "app" 
  - "lib"
  - "services"
  - "modules"
  - "packages"
  - "scripts"
  - "utils"
  - "helpers"
  - "api"
  - "core"
  # Include Python files explicitly
  - "**/*.py"
  - "**/*.pyx"
  - "**/*.pyi"

# Paths to exclude from analysis
paths-ignore:
  # Test directories  
  - "test"
  - "tests"
  - "__pycache__"
  - "**/*_test.py"
  - "**/*_tests.py"
  - "**/test_*.py"
  - "**/tests/**"
  - "**/test/**"
  # Virtual environments
  - "venv"
  - "env"
  - ".venv"
  - ".env"
  - "virtualenv"
  - "**/.venv/**"
  - "**/venv/**"
  # Build and distribution directories
  - "build"
  - "dist"
  - "*.egg-info"
  - "__pycache__"
  - "**/__pycache__/**"
  - "*.pyc"
  - "*.pyo"
  # Third-party code
  - "vendor"
  - "third_party"
  - "external"
  - "site-packages"
  - "**/site-packages/**"
  # Generated files
  - "**/*.generated.*" 
  # Migration files (often auto-generated)
  - "**/migrations/**"
  - "**/alembic/versions/**"
  # Documentation
  - "docs"
  - "documentation"
  - "*.md"

# Disable default paths to use our explicit configuration  
disable-default-path-filters: true

# Python-specific extraction options
extraction:
  python:
    # Include requirements files for dependency analysis
    setup_py: true
    requirements_txt: true
    # Handle different Python versions
    python2: false
    python3: true
EOF
    
    echo -e "${GREEN}   ✅ Python config written${NC}"
}

# Function to write Java config
write_java_config() {
    local file="${GITHUB_DIR}/codeql/config/java.yml"
    echo -e "${BLUE}📝 Writing Java config: ${file}${NC}"
    
    cat > "${file}" << 'EOF'
name: "CodeQL Java Configuration"

# Query suites to run
queries:
  - uses: security-extended
  - uses: security-and-quality

# Paths to include in analysis
paths:
  - "src/main/java"
  - "src"
  - "app/src/main/java" 
  - "lib"
  - "services"
  - "modules"
  # Include Java files explicitly
  - "**/*.java"
  - "**/*.kt" 
  - "**/*.kts"

# Paths to exclude from analysis
paths-ignore:
  # Test directories
  - "src/test"
  - "src/test/java"
  - "test"
  - "tests"
  - "**/src/test/**"
  - "**/*Test.java"
  - "**/*Tests.java"
  - "**/Test*.java"
  # Build directories
  - "target"
  - "build"
  - "out"
  - "**/target/**"
  - "**/build/**"
  - "**/out/**"
  # Gradle/Maven wrapper and configs
  - ".gradle"
  - ".mvn"
  - "gradlew"
  - "gradlew.bat"  
  - "mvnw"
  - "mvnw.cmd"
  # Generated sources
  - "**/generated/**"
  - "**/generated-sources/**"
  - "**/generated-test-sources/**"
  - "**/*.generated.*"
  # Third-party dependencies
  - "vendor"
  - "third_party"
  - "external"
  - "lib/external"
  # IDE files
  - ".idea"
  - "*.iml"
  - ".eclipse"
  - ".vscode"
  # Documentation
  - "docs"
  - "documentation"
  - "*.md"

# Disable default paths to use our explicit configuration
disable-default-path-filters: true

# Java-specific extraction options  
extraction:
  java:
    # Maven settings
    maven:
      # Use Maven wrapper if available
      wrapper: true
      # Maven goals for compilation
      goals: ["compile", "test-compile"]
    # Gradle settings  
    gradle:
      # Use Gradle wrapper if available
      wrapper: true
      # Gradle tasks for compilation  
      tasks: ["compileJava", "compileTestJava"]
    # JDK version compatibility
    jdk: "17"
EOF
    
    echo -e "${GREEN}   ✅ Java config written${NC}"
}

# Function to verify files
verify_files() {
    echo -e "${BLUE}🔍 Verifying created files...${NC}"
    
    local files=(
        "${GITHUB_DIR}/workflows/codeql.yml"
        "${GITHUB_DIR}/codeql/config/javascript.yml"
        "${GITHUB_DIR}/codeql/config/python.yml"
        "${GITHUB_DIR}/codeql/config/java.yml"
    )
    
    local all_good=true
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]] && [[ -s "$file" ]]; then
            echo -e "${GREEN}   ✅ $file exists and is not empty${NC}"
        else
            echo -e "${RED}   ❌ $file is missing or empty${NC}"
            all_good=false
        fi
    done
    
    if [[ "$all_good" == true ]]; then
        echo -e "${GREEN}   🎉 All files verified successfully!${NC}"
    else
        echo -e "${RED}   ❌ Some files are missing or empty${NC}"
        return 1
    fi
}

# Function to show final summary
show_summary() {
    echo ""
    echo -e "${BLUE}📊 Update Summary${NC}"
    echo -e "${BLUE}=================${NC}"
    echo -e "${GREEN}✅ Backup created: ${BACKUP_DIR}${NC}"
    echo -e "${GREEN}✅ Workflow updated: ${GITHUB_DIR}/workflows/codeql.yml${NC}"
    echo -e "${GREEN}✅ JavaScript config: ${GITHUB_DIR}/codeql/config/javascript.yml${NC}"
    echo -e "${GREEN}✅ Python config: ${GITHUB_DIR}/codeql/config/python.yml${NC}"
    echo -e "${GREEN}✅ Java config: ${GITHUB_DIR}/codeql/config/java.yml${NC}"
    echo ""
    echo -e "${PURPLE}🗂️  Your existing files preserved:${NC}"
    if [[ -f "${GITHUB_DIR}/codeql/queries/javascript/javascript-custom.qls" ]]; then
        echo -e "${YELLOW}   📄 Custom JavaScript queries suite preserved${NC}"
    fi
    if [[ -f "${GITHUB_DIR}/codeql/queries/python/python-custom.qls" ]]; then
        echo -e "${YELLOW}   📄 Custom Python queries suite preserved${NC}"
    fi
    if [[ -f "${GITHUB_DIR}/codeql/tools/sarif_summary.py" ]]; then
        echo -e "${YELLOW}   🛠️  SARIF summary tool preserved${NC}"
    fi
    if [[ -f "${GITHUB_DIR}/codeql/compliance/cwe_to_owasp.csv" ]]; then
        echo -e "${YELLOW}   📋 CWE to OWASP mapping preserved${NC}"
    fi
    echo ""
    echo -e "${BLUE}🚀 Next Steps:${NC}"
    echo -e "${PURPLE}   1. Review the changes: git diff${NC}"
    echo -e "${PURPLE}   2. Add files: git add .github${NC}"
    echo -e "${PURPLE}   3. Commit: git commit -m 'Update CodeQL configuration with bulletproof setup'${NC}"
    echo -e "${PURPLE}   4. Push: git push${NC}"
    echo ""
    echo -e "${GREEN}🎉 CodeQL configuration updated successfully!${NC}"
}

# Function to handle script interruption
cleanup() {
    echo ""
    echo -e "${YELLOW}⚠️  Script interrupted. Changes may be incomplete.${NC}"
    echo -e "${YELLOW}   Backup available at: ${BACKUP_DIR}${NC}"
    exit 1
}

# Set up interrupt handler
trap cleanup INT TERM

# Main execution
main() {
    echo -e "${PURPLE}🔧 Starting CodeQL configuration update...${NC}"
    echo ""
    
    # Show current structure
    echo -e "${BLUE}📋 Current .github structure:${NC}"
    if command -v tree &> /dev/null; then
        tree "${GITHUB_DIR}" -a 2>/dev/null || find "${GITHUB_DIR}" -type f 2>/dev/null | sort | sed 's|^|   |'
    else
        find "${GITHUB_DIR}" -type f 2>/dev/null | sort | sed 's|^|   |'
    fi
    echo ""
    
    # Create backup
    create_backup
    
    # Create directory structure
    create_directories
    
    # Write all configuration files
    write_workflow_file
    write_javascript_config
    write_python_config
    write_java_config
    
    # Verify everything was created correctly
    verify_files
    
    # Show summary
    show_summary
}

# Run main function
main "$@"