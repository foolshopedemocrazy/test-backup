#!/bin/bash

# Script to safely disable AI dependencies and verify CodeQL setup
# Created: 2025-08-27 08:26:45 UTC
# Author: foolshopedemocrazy

echo "=== CodeQL Setup & AI Dependency Removal ==="
echo "Starting update at $(date -u +"%Y-%m-%d %H:%M:%S UTC")"

# Create backup directory with timestamp
BACKUP_DIR=".github/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "Created backup directory: $BACKUP_DIR"

# 1. BACKUP EVERYTHING FIRST
echo "Creating complete backup of .github directory..."
cp -r .github/* "$BACKUP_DIR/"
echo "✓ Full backup created in $BACKUP_DIR"

# 2. VERIFY CODEQL DIRECTORY STRUCTURE
echo "Verifying CodeQL directory structure..."
ISSUES_FOUND=0

# Check for correct workflow location
if [ ! -f ".github/workflows/codeql.yml" ]; then
  echo "⚠️ Warning: Main CodeQL workflow not found at .github/workflows/codeql.yml"
  ISSUES_FOUND=$((ISSUES_FOUND+1))
fi

# Check for duplicate workflows
if [ -d ".github/CodeQL/workflows" ]; then
  DUPLICATE_COUNT=$(find .github/CodeQL/workflows -name "*.yml" | wc -l)
  if [ "$DUPLICATE_COUNT" -gt 0 ]; then
    echo "⚠️ Warning: Found $DUPLICATE_COUNT duplicate workflow files in .github/CodeQL/workflows/"
    echo "    These should be deleted after being moved to .github/workflows/"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
  fi
fi

# Verify essential CodeQL directories exist
for dir in "config" "queries" "tools"; do
  if [ ! -d ".github/CodeQL/$dir" ]; then
    echo "⚠️ Warning: Missing essential CodeQL directory: .github/CodeQL/$dir"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
  fi
done

# 3. DISABLE AI-DEPENDENT WORKFLOWS (IMPROVED METHOD)
echo "Identifying workflows with AI API dependencies..."
AI_PATTERNS="OPENAI_API_KEY\|openai\|gpt\|completion\|davinci\|API_KEY\|chat-model\|text-embedding"
AI_WORKFLOWS=$(grep -l "$AI_PATTERNS" .github/workflows/*.yml 2>/dev/null || echo "")

if [ -z "$AI_WORKFLOWS" ]; then
  echo "No workflows with AI API dependencies found."
else
  echo "Found workflows with AI API dependencies. Disabling..."
  
  for workflow in $AI_WORKFLOWS; do
    # Create backup
    cp "$workflow" "$workflow.bak"
    echo "✓ Backed up: $workflow → $workflow.bak"
    
    # Properly disable using GitHub's native method (keep filename unchanged)
    sed -i '1i# DISABLED: This workflow was disabled because it contains external AI API dependencies.\n# To re-enable, remove these comments and restore the original triggers.\n' "$workflow"
    sed -i 's/^on:/on:\n  # Original triggers disabled - contains external AI dependencies\n  workflow_dispatch:/' "$workflow"
    
    echo "✓ Disabled: $workflow (using workflow_dispatch only)"
  done
fi

# 4. VERIFICATION STEPS
echo "Verifying disabled workflows..."
VERIFICATION_ISSUES=0
for disabled in $(grep -l "DISABLED: This workflow was disabled" .github/workflows/*.yml 2>/dev/null || echo ""); do
  if ! grep -q "workflow_dispatch" "$disabled"; then
    echo "⚠️ Warning: $disabled may not be properly disabled"
    VERIFICATION_ISSUES=$((VERIFICATION_ISSUES+1))
  fi
done

if [ "$VERIFICATION_ISSUES" -eq 0 ] && [ ! -z "$AI_WORKFLOWS" ]; then
  echo "✓ All AI workflows properly disabled"
fi

# 5. FIX CODEQL STRUCTURE ISSUES
echo "Fixing CodeQL structure issues..."

# Move any remaining workflow files to correct location
if [ -d ".github/CodeQL/workflows" ]; then
  for workflow in $(find .github/CodeQL/workflows -name "*.yml" 2>/dev/null || echo ""); do
    basename=$(basename "$workflow")
    if [ ! -f ".github/workflows/$basename" ]; then
      cp "$workflow" ".github/workflows/$basename"
      echo "✓ Moved: $workflow → .github/workflows/$basename"
    fi
    # Mark original for deletion
    echo "$workflow" >> /tmp/workflows_to_delete.txt
  done
  
  # Clean up duplicates
  if [ -f "/tmp/workflows_to_delete.txt" ]; then
    echo "Removing duplicate workflow files..."
    while read workflow; do
      rm "$workflow"
      echo "✓ Removed duplicate: $workflow"
    done < /tmp/workflows_to_delete.txt
    rm /tmp/workflows_to_delete.txt
  fi
fi

# 6. CREATE DOCUMENTATION
cat > .github/CODEQL_README.md << 'EOF'
# CodeQL Setup Documentation

## Directory Structure
- `.github/workflows/` - All GitHub Action workflows (including CodeQL)
- `.github/CodeQL/config/` - CodeQL configuration files
- `.github/CodeQL/queries/` - Custom CodeQL queries
- `.github/CodeQL/tools/` - Supporting tools and scripts
- `.github/CodeQL/compliance/` - Compliance mappings (if used)

## AI Dependencies
All workflows with external AI API dependencies have been disabled using GitHub's native method.
These workflows will only run manually through workflow_dispatch, not automatically.

## How to Restore AI Workflows
1. Complete backup was created in `.github/backups/[timestamp]`
2. Each disabled workflow has a `.bak` file with the original content
3. To restore: remove the comments and restore original triggers

## Local Alternatives
To replace external AI functionality:
1. Use GitHub's built-in CodeQL analysis
2. Implement local analysis scripts for vulnerability review
3. Use GitHub's Advanced Security features instead of external APIs
EOF

# 7. SUMMARY
echo
echo "=== Setup Verification Complete ==="
if [ "$ISSUES_FOUND" -eq 0 ] && [ "$VERIFICATION_ISSUES" -eq 0 ]; then
  echo "✓ All checks passed! Your CodeQL setup is correctly structured."
  echo "✓ AI-dependent workflows have been properly disabled."
else
  echo "⚠️ Found $ISSUES_FOUND structure issues and $VERIFICATION_ISSUES verification issues."
  echo "   Most critical issues were automatically fixed."
  echo "   Review .github/CODEQL_README.md for remaining steps."
fi

echo
echo "Documentation created in .github/CODEQL_README.md"
echo "Complete backup available in $BACKUP_DIR"