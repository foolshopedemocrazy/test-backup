#!/bin/bash
set -e

echo "=== CodeQL Setup Optimizer ==="
echo "Starting at $(date)"
echo

# Create backups directory
BACKUP_DIR=".github/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "✓ Backup directory created at $BACKUP_DIR"

# 1. Resolve duplicate workflow files
echo "1. Resolving duplicate CodeQL workflows..."
if [ -f ".github/workflows/codeql.yml" ] && [ -f ".github/workflows/codeql-analysis.yml" ]; then
    echo "   ⚠️  Duplicate workflows detected"
    mkdir -p "$BACKUP_DIR/.github/workflows"
    cp ".github/workflows/codeql-analysis.yml" "$BACKUP_DIR/.github/workflows/"
    mv ".github/workflows/codeql-analysis.yml" ".github/workflows/codeql-analysis.yml.bak"
    echo "   ✓ Kept codeql.yml (newer) and backed up codeql-analysis.yml"
elif [ -f ".github/workflows/codeql.yml" ]; then
    echo "   ✓ Only one CodeQL workflow found (codeql.yml)"
elif [ -f ".github/workflows/codeql-analysis.yml" ]; then
    echo "   ✓ Only one CodeQL workflow found (codeql-analysis.yml)"
    mv ".github/workflows/codeql-analysis.yml" ".github/workflows/codeql.yml"
    echo "   ✓ Renamed codeql-analysis.yml to codeql.yml for consistency"
else
    echo "   ❌ No CodeQL workflow found! This is a critical issue."
    exit 1
fi

# 2. Update workflow to reference config file
echo "2. Adding config-file reference to workflow..."
WORKFLOW_FILE=".github/workflows/codeql.yml"
if [ -f "$WORKFLOW_FILE" ]; then
    if grep -q "config-file:" "$WORKFLOW_FILE"; then
        echo "   ✓ Config file already referenced in workflow"
    else
        cp "$WORKFLOW_FILE" "$BACKUP_DIR/.github/workflows/"
        awk '
        /Initialize CodeQL/ {print; p=1; next}
        p && /with:/ {print; print "        config-file: .github/CodeQL/config/codeql-config.yml  # Added by optimizer"; p=0; next}
        {print}
        ' "$WORKFLOW_FILE" > "$WORKFLOW_FILE.tmp" && mv "$WORKFLOW_FILE.tmp" "$WORKFLOW_FILE"
        echo "   ✓ Added config-file reference to workflow"
    fi
fi

# 3. Verify paths in config match repository structure
echo "3. Verifying repository paths in config..."
CONFIG_FILE=".github/CodeQL/config/codeql-config.yml"
if [ -f "$CONFIG_FILE" ]; then
    paths=$(grep -A10 "paths:" "$CONFIG_FILE" | grep -v "paths:" | grep -v "paths-ignore:" | grep "^  -" | sed 's/  - //')
    
    for path in $paths; do
        if [ -d "$path" ]; then
            echo "   ✓ Path exists: $path"
        else
            echo "   ⚠️  Path in config doesn't exist: $path"
            echo "      Consider updating $CONFIG_FILE with correct paths."
        fi
    done
else
    echo "   ❌ Config file not found at $CONFIG_FILE"
    mkdir -p ".github/CodeQL/config"
    cat > "$CONFIG_FILE" << 'EOF'
name: "CodeQL Configuration"

queries:
  - name: Security and Quality
    uses: security-and-quality
  - name: Security Extended
    uses: security-extended

paths:
  - src
  - lib
paths-ignore:
  - node_modules
  - '**/*.test.js'
  - '**/test/**'
  - '**/tests/**'
  - '**/vendor/**'
EOF
    echo "   ✓ Created basic config file at $CONFIG_FILE (needs path verification)"
fi

# 4. Normalize disabled workflow names
echo "4. Normalizing disabled workflow filenames..."
for workflow in ".github/workflows/"*".yml"; do
    filename=$(basename "$workflow")
    if grep -q "DISABLED: This workflow was disabled" "$workflow" && [[ $filename != *".disabled.yml" ]]; then
        cp "$workflow" "$BACKUP_DIR/.github/workflows/"
        new_name="${workflow%.yml}.disabled.yml"
        mv "$workflow" "$new_name"
        echo "   ✓ Renamed $filename to $(basename $new_name)"
    fi
done

# 5. Verify all required CodeQL directories exist
echo "5. Verifying CodeQL directory structure..."
required_dirs=(
    ".github/CodeQL/compliance"
    ".github/CodeQL/config"
    ".github/CodeQL/queries"
    ".github/CodeQL/tools"
    ".github/CodeQL/templates"
)

for dir in "${required_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        echo "   ✓ Created missing directory: $dir"
    fi
done

# 6. Create summary report
echo
echo "=== CodeQL Setup Summary ==="
echo "✓ Workflow optimization complete"
echo "✓ Configuration file reference added"
echo "✓ Directory structure verified"
echo

echo "Next Steps:"
echo "1. Enable GitHub Advanced Security in repository settings"
echo "2. Verify code paths in .github/CodeQL/config/codeql-config.yml"
echo "3. Run a test CodeQL scan via Actions tab"
echo "4. Review backup files in $BACKUP_DIR if needed"
echo
echo "Completed at $(date)"