#!/bin/bash
# CodeQL Advanced Configuration Cleanup Script
# Removes all files and directories related to the CodeQL implementation
# Usage: chmod +x cleanup-codeql.sh && ./cleanup-codeql.sh

# Set the repository base directory (current directory by default)
REPO_DIR="."
# Change to the repository base directory
cd "$REPO_DIR" || { echo "Error: Could not change to repository directory"; exit 1; }

echo "Starting CodeQL configuration cleanup..."
echo "Repository directory: $(pwd)"

# Remove workflow files
echo "Removing workflow files..."
rm -f .github/workflows/codeql.yml
rm -f .github/workflows/codeql-analysis.yml.bak
rm -f .github/workflows/enhanced-reporting.disabled.yml
rm -f .github/workflows/ai-remediation.disabled.yml
rm -f .github/workflows/bearer-security-scan.disabled.yml

# Remove entire CodeQL directory and all its contents
echo "Removing CodeQL directory structure..."
rm -rf .github/CodeQL/

# Remove documentation files
echo "Removing documentation files..."
rm -f .github/CODEQL_README.md
rm -f .github/AI_DEPENDENCIES_README.md

# Remove any backup directories and their contents
echo "Removing backup directories..."
rm -rf .github/backups/

# Clean up any empty directories that might be left
echo "Cleaning up empty directories..."
find .github -type d -empty -delete

echo "CodeQL cleanup complete!"
echo "Please note: This script only removes files locally."
echo "To complete removal, commit and push these changes to your repository."