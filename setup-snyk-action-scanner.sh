#!/bin/bash
#
# Snyk GitHub Actions Scanner Setup Script
# Created: 2025-08-27 02:32:55 UTC
# Author: foolshopedemocrazyimplement
#
# This script sets up Snyk GitHub Actions Scanner for workflow security scanning

echo "==================================================="
echo "   Snyk GitHub Actions Scanner Setup               "
echo "   Date: 2025-08-27 02:32:55 UTC                  "
echo "   Author: foolshopedemocrazyimplement            "
echo "==================================================="

# Create directory structure
echo "Creating directory structure..."
mkdir -p .github/workflows
mkdir -p .snyk

# Create GitHub Actions workflow for Snyk Actions Scanner
echo "Creating Snyk Actions Scanner workflow..."
cat > .github/workflows/snyk-actions-scan.yml << 'EOF'
name: Snyk GitHub Actions Scanner

on:
  # Scan all workflows when changes are pushed to main or master
  push:
    branches: [ main, master ]
    paths:
      - '.github/workflows/**'
  
  # Scan when workflow files are modified in PRs
  pull_request:
    branches: [ main, master ]
    paths:
      - '.github/workflows/**'
  
  # Regular scheduled scans
  schedule:
    - cron: '0 0 * * 1' # Weekly scan on Mondays at midnight
  
  # Manual trigger
  workflow_dispatch:

jobs:
  snyk-actions-scan:
    name: Scan GitHub Actions Workflows
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
      actions: read
      id-token: write # Required for Snyk integration
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full git history for scanning
      
      # Setup Node.js environment for running the scanner
      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '18'
      
      # Install the scanner globally
      - name: Install Snyk GitHub Actions Scanner
        run: |
          npm install -g @snyk/github-actions-scanner
          echo "Installed version: $(github-actions-scanner --version)"
      
      # Authenticate with Snyk (if token available)
      - name: Authenticate with Snyk
        if: env.SNYK_TOKEN != ''
        run: snyk auth ${{ secrets.SNYK_TOKEN }}
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
      
      # Scan all workflow files
      - name: Scan workflows
        id: scan
        run: |
          # Create output directory
          mkdir -p snyk-actions-scan-results
          
          # Run the scanner
          github-actions-scanner scan \
            --repo-path=. \
            --output-file=snyk-actions-scan-results/scan-results.json \
            --output-format=json \
            --config-file=.snyk/actions-scanner-config.json
          
          # Generate summary for GitHub Actions
          echo "### Snyk GitHub Actions Scanner Results" >> $GITHUB_STEP_SUMMARY
          github-actions-scanner report \
            --input-file=snyk-actions-scan-results/scan-results.json \
            --format=markdown >> $GITHUB_STEP_SUMMARY
        continue-on-error: true
      
      # Generate SARIF report for GitHub Security tab
      - name: Generate SARIF report
        if: success() || steps.scan.outcome == 'failure'
        run: |
          github-actions-scanner report \
            --input-file=snyk-actions-scan-results/scan-results.json \
            --format=sarif \
            --output-file=snyk-actions-scan-results/results.sarif
      
      # Upload SARIF file to GitHub Security
      - name: Upload SARIF file
        if: success() || steps.scan.outcome == 'failure'
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: snyk-actions-scan-results/results.sarif
          category: snyk-actions-scanner
      
      # Upload full results as artifacts
      - name: Upload scan results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: snyk-actions-scan-results
          path: snyk-actions-scan-results
          retention-days: 7
      
      # Comment on PR with findings if running on a PR
      - name: Comment on PR
        if: github.event_name == 'pull_request' && (success() || steps.scan.outcome == 'failure')
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            
            try {
              // Read scan results
              const scanResults = JSON.parse(fs.readFileSync('snyk-actions-scan-results/scan-results.json', 'utf8'));
              
              // Generate markdown report
              let markdownReport = `## 🔍 Snyk GitHub Actions Workflow Security Scan\n\n`;
              
              // Check if we have any findings
              if (scanResults.findings && scanResults.findings.length > 0) {
                markdownReport += `### 🚨 Found ${scanResults.findings.length} potential security issues in workflow files\n\n`;
                
                // Group by severity
                const severityGroups = {
                  critical: [],
                  high: [],
                  medium: [],
                  low: []
                };
                
                // Group findings by severity
                scanResults.findings.forEach(finding => {
                  const severity = finding.severity ? finding.severity.toLowerCase() : 'low';
                  if (severityGroups[severity]) {
                    severityGroups[severity].push(finding);
                  } else {
                    severityGroups.low.push(finding);
                  }
                });
                
                // Display findings by severity (highest first)
                if (severityGroups.critical.length > 0) {
                  markdownReport += `### Critical Severity Issues (${severityGroups.critical.length})\n\n`;
                  severityGroups.critical.forEach(finding => {
                    markdownReport += `- **${finding.title || 'Security Issue'}**: ${finding.description || 'No description'}\n`;
                    if (finding.file) markdownReport += `  - File: \`${finding.file}\`\n`;
                    if (finding.remediation) markdownReport += `  - Recommendation: ${finding.remediation}\n`;
                    markdownReport += '\n';
                  });
                }
                
                if (severityGroups.high.length > 0) {
                  markdownReport += `### High Severity Issues (${severityGroups.high.length})\n\n`;
                  severityGroups.high.forEach(finding => {
                    markdownReport += `- **${finding.title || 'Security Issue'}**: ${finding.description || 'No description'}\n`;
                    if (finding.file) markdownReport += `  - File: \`${finding.file}\`\n`;
                    if (finding.remediation) markdownReport += `  - Recommendation: ${finding.remediation}\n`;
                    markdownReport += '\n';
                  });
                }
                
                if (severityGroups.medium.length > 0) {
                  markdownReport += `### Medium Severity Issues (${severityGroups.medium.length})\n\n`;
                  markdownReport += `<details><summary>Click to expand</summary>\n\n`;
                  severityGroups.medium.forEach(finding => {
                    markdownReport += `- **${finding.title || 'Security Issue'}**: ${finding.description || 'No description'}\n`;
                    if (finding.file) markdownReport += `  - File: \`${finding.file}\`\n`;
                    if (finding.remediation) markdownReport += `  - Recommendation: ${finding.remediation}\n`;
                    markdownReport += '\n';
                  });
                  markdownReport += `</details>\n\n`;
                }
                
                if (severityGroups.low.length > 0) {
                  markdownReport += `### Low Severity Issues (${severityGroups.low.length})\n\n`;
                  markdownReport += `<details><summary>Click to expand</summary>\n\n`;
                  severityGroups.low.forEach(finding => {
                    markdownReport += `- **${finding.title || 'Security Issue'}**: ${finding.description || 'No description'}\n`;
                    if (finding.file) markdownReport += `  - File: \`${finding.file}\`\n`;
                    if (finding.remediation) markdownReport += `  - Recommendation: ${finding.remediation}\n`;
                    markdownReport += '\n';
                  });
                  markdownReport += `</details>\n\n`;
                }
                
                // Add a note about the full report
                markdownReport += `For complete details, check the [Actions tab](${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}).\n\n`;
                
                // Add best practices
                markdownReport += `## 📚 GitHub Actions Security Best Practices\n\n`;
                markdownReport += `- Use specific commit hashes instead of tags for third-party actions\n`;
                markdownReport += `- Minimize the permissions granted to the GitHub token\n`;
                markdownReport += `- Avoid using input data directly in commands (to prevent injection)\n`;
                markdownReport += `- Set the \`permissions\` field explicitly in your workflows\n`;
                markdownReport += `- Use secrets for sensitive data\n`;
              } else {
                markdownReport += `### ✅ No security issues found in workflow files\n\n`;
                markdownReport += `Great job! Your GitHub Actions workflows follow good security practices. Keep it up!\n\n`;
              }
              
              // Post the comment
              const { data: comment } = await github.rest.issues.createComment({
                issue_number: context.issue.number,
                owner: context.repo.owner,
                repo: context.repo.repo,
                body: markdownReport
              });
              
              console.log(`Created comment with ID ${comment.id}`);
            } catch (error) {
              console.log(`Error creating PR comment: ${error.message}`);
            }
EOF

# Create configuration file
echo "Creating Snyk Actions Scanner configuration file..."
cat > .snyk/actions-scanner-config.json << 'EOF'
{
  "scanSettings": {
    "baseBranch": "main",
    "enableLicenseViolations": true,
    "enableDependencyVulnerabilities": true,
    "enableWorkflowVulnerabilities": true,
    "minSeverity": "low"
  },
  "checks": {
    "third-party-action-pinning": {
      "enabled": true,
      "pinningStrategy": "sha"
    },
    "github-token-permissions": {
      "enabled": true,
      "maxPermissions": "write-all"
    },
    "script-injection": {
      "enabled": true
    },
    "insecure-downloads": {
      "enabled": true
    },
    "credentials-exposure": {
      "enabled": true
    },
    "self-hosted-runner-security": {
      "enabled": true
    },
    "protected-branch-workflow": {
      "enabled": true
    }
  },
  "ignores": {
    // Example of ignoring specific findings
    // "workflow-files": [
    //   ".github/workflows/release.yml"
    // ],
    // "rule-ids": [
    //   "snyk-actions-001"
    // ]
  }
}
EOF

# Create a local scan script
echo "Creating local scan script..."
cat > scan-github-actions.sh << 'EOF'
#!/bin/bash
#
# Local Snyk GitHub Actions Scanner Script
# Run from repository root to scan your workflow files for security issues

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "Error: npm is required but not installed. Please install Node.js and npm first."
    exit 1
fi

# Check if scanner is installed, install if not
if ! command -v github-actions-scanner &> /dev/null; then
    echo "Snyk GitHub Actions Scanner not found. Installing globally..."
    npm install -g @snyk/github-actions-scanner
fi

# Create output directory
mkdir -p snyk-actions-scan-results

# Display menu
echo "==== Snyk GitHub Actions Scanner ===="
echo "1. Scan all workflow files"
echo "2. Scan specific workflow file"
echo "3. Generate security report"
echo "4. Exit"
echo ""
echo "Select an option (1-4): "
read -r option

timestamp=$(date +"%Y%m%d_%H%M%S")

case $option in
    1)
        echo "Scanning all workflow files..."
        github-actions-scanner scan \
            --repo-path=. \
            --output-file=snyk-actions-scan-results/full_scan_$timestamp.json \
            --output-format=json \
            --config-file=.snyk/actions-scanner-config.json
        
        echo "Generating HTML report..."
        github-actions-scanner report \
            --input-file=snyk-actions-scan-results/full_scan_$timestamp.json \
            --format=html \
            --output-file=snyk-actions-scan-results/full_scan_$timestamp.html
        
        echo "✓ Scan complete! Results saved to snyk-actions-scan-results/"
        
        # Show summary
        echo ""
        echo "Summary:"
        github-actions-scanner report \
            --input-file=snyk-actions-scan-results/full_scan_$timestamp.json \
            --format=summary
        ;;
    2)
        echo "Enter path to workflow file (e.g. .github/workflows/build.yml):"
        read -r workflow_file
        
        if [ -z "$workflow_file" ] || [ ! -f "$workflow_file" ]; then
            echo "Invalid file path or file doesn't exist. Exiting."
            exit 1
        fi
        
        echo "Scanning workflow file: $workflow_file"
        github-actions-scanner scan \
            --workflow-file="$workflow_file" \
            --output-file=snyk-actions-scan-results/single_scan_$timestamp.json \
            --output-format=json \
            --config-file=.snyk/actions-scanner-config.json
        
        echo "Generating HTML report..."
        github-actions-scanner report \
            --input-file=snyk-actions-scan-results/single_scan_$timestamp.json \
            --format=html \
            --output-file=snyk-actions-scan-results/single_scan_$timestamp.html
        
        echo "✓ Scan complete! Results saved to snyk-actions-scan-results/"
        
        # Show summary
        echo ""
        echo "Summary:"
        github-actions-scanner report \
            --input-file=snyk-actions-scan-results/single_scan_$timestamp.json \
            --format=summary
        ;;
    3)
        echo "Select report format:"
        echo "1. HTML"
        echo "2. Markdown"
        echo "3. JSON"
        echo "4. SARIF (for GitHub Security)"
        read -r format_option
        
        echo "Select input file:"
        select input_file in snyk-actions-scan-results/*.json; do
            if [ -n "$input_file" ]; then
                break
            fi
        done
        
        if [ ! -f "$input_file" ]; then
            echo "No scan results found. Run a scan first."
            exit 1
        fi
        
        case $format_option in
            1) format="html"; ext="html" ;;
            2) format="markdown"; ext="md" ;;
            3) format="json"; ext="json" ;;
            4) format="sarif"; ext="sarif" ;;
            *) 
                echo "Invalid option. Using HTML."
                format="html"
                ext="html"
                ;;
        esac
        
        output_file="snyk-actions-scan-results/report_${timestamp}.${ext}"
        
        echo "Generating ${format} report..."
        github-actions-scanner report \
            --input-file="$input_file" \
            --format="${format}" \
            --output-file="$output_file"
        
        echo "✓ Report generated: $output_file"
        ;;
    4)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
esac

# Try to open HTML report if it exists and we're on a desktop
if [[ "$option" == "1" || "$option" == "2" ]] && [[ "$DISPLAY" != "" ]]; then
    html_file=""
    if [[ "$option" == "1" ]]; then
        html_file="snyk-actions-scan-results/full_scan_$timestamp.html"
    else
        html_file="snyk-actions-scan-results/single_scan_$timestamp.html"
    fi
    
    if [ -f "$html_file" ]; then
        echo "Opening HTML report..."
        if command -v xdg-open &> /dev/null; then
            xdg-open "$html_file"
        elif command -v open &> /dev/null; then
            open "$html_file"
        else
            echo "Cannot open report automatically. Please open it manually: $html_file"
        fi
    fi
fi
EOF
chmod +x scan-github-actions.sh

# Create a pre-commit hook to scan workflow files
echo "Creating pre-commit hook for workflow file scanning..."
mkdir -p .git/hooks
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
#
# Pre-commit hook to scan GitHub Actions workflow files for security issues
# This hook runs when committing changes to workflow files

# Check if GitHub Actions Scanner is installed
if ! command -v github-actions-scanner &> /dev/null; then
    echo "⚠️ Snyk GitHub Actions Scanner not installed. Skipping workflow security check."
    echo "Install with: npm install -g @snyk/github-actions-scanner"
    exit 0
fi

# Get all staged workflow files
staged_workflow_files=$(git diff --cached --name-only | grep -E '\.github/workflows/.*\.ya?ml$')

# If no workflow files are staged, exit
if [ -z "$staged_workflow_files" ]; then
    exit 0
fi

echo "🔍 Checking GitHub Actions workflows for security issues..."

# Create temporary file listing all staged workflow files
temp_file=$(mktemp)
echo "$staged_workflow_files" > "$temp_file"

# Create output directory
mkdir -p .snyk-scan-results

# Scan the staged workflow files
github-actions-scanner scan \
    --files-from="$temp_file" \
    --output-file=.snyk-scan-results/pre-commit-scan.json \
    --output-format=json \
    --config-file=.snyk/actions-scanner-config.json

scan_exit_code=$?

# Clean up temp file
rm "$temp_file"

# Check if scan found issues
if [ $scan_exit_code -ne 0 ]; then
    echo "❌ Security issues found in GitHub Actions workflows!"
    echo ""
    
    # Display summary of issues
    github-actions-scanner report \
        --input-file=.snyk-scan-results/pre-commit-scan.json \
        --format=summary
    
    echo ""
    echo "Would you like to view detailed findings? (y/n)"
    read -r view_details
    
    if [[ "$view_details" == "y" || "$view_details" == "Y" ]]; then
        github-actions-scanner report \
            --input-file=.snyk-scan-results/pre-commit-scan.json \
            --format=text
    fi
    
    echo ""
    echo "Do you want to commit anyway? (y/n)"
    read -r commit_anyway
    
    if [[ "$commit_anyway" != "y" && "$commit_anyway" != "Y" ]]; then
        echo "Commit aborted. Please fix the security issues before committing."
        exit 1
    fi
    
    echo "Committing despite security issues..."
fi

exit 0
EOF
chmod +x .git/hooks/pre-commit

# Create documentation
echo "Creating documentation..."
cat > SNYK_ACTIONS_SCANNER_README.md << 'EOF'
# Snyk GitHub Actions Scanner

This repository is configured with Snyk GitHub Actions Scanner to detect security issues in GitHub Actions workflow files.

## What is Snyk GitHub Actions Scanner?

Snyk GitHub Actions Scanner is a specialized security tool that analyzes GitHub Actions workflow files for:

- Use of non-pinned actions (supply chain risks)
- Excessive GitHub token permissions
- Command injection vulnerabilities
- Insecure downloading of dependencies
- Credentials exposure
- Self-hosted runner security issues
- And more...

## How It's Configured

The scanner is integrated in three ways:

1. **GitHub Actions Workflow**: Automatically scans workflow files on pushes, PRs, and scheduled runs
2. **Local Scanning Script**: For manual scanning during development
3. **Git Pre-commit Hook**: To catch issues before they're committed

## Setup Requirements

### For GitHub Actions Workflow

1. **Snyk API Token** (Optional but recommended)
   - Sign up at [Snyk.io](https://snyk.io)
   - Get your API token from Account Settings
   - Add it as a GitHub Secret named `SNYK_TOKEN`

### For Local Scanning

1. **Node.js and npm**
2. **Snyk GitHub Actions Scanner**
   ```bash
   npm install -g @snyk/github-actions-scanner