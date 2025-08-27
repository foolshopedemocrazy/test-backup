#!/bin/bash

# CodeQL Security System Setup Script
# This script creates the CodeQL security system structure in your repository

# Display timestamp
echo "Setting up CodeQL Security System"
echo "Current time: 2025-08-27 06:27:27 UTC"
echo "User: foolshopedemocrazy"
echo "----------------------------------------"

# Setup base directory
BASE_DIR=".github/CodeQL"
echo "Creating directory structure in $BASE_DIR..."

mkdir -p "$BASE_DIR/workflows"
mkdir -p "$BASE_DIR/tools"
mkdir -p "$BASE_DIR/config"
mkdir -p "$BASE_DIR/queries"
mkdir -p "$BASE_DIR/compliance"
mkdir -p "$BASE_DIR/templates"

echo "Directory structure created."
echo "----------------------------------------"

# Create workflow files
echo "Creating workflow files..."

cat > "$BASE_DIR/workflows/codeql-analysis.yml" << 'EOF'
name: "CodeQL Security Analysis"

on:
  push:
    branches: [ "main" ]
    paths:
      - '**.py'
      - '**.js'
      - '**.ts'
      - '**.java'
      - '**.go'
  pull_request:
    branches: [ "main" ]
    paths-ignore:
      - 'docs/**'
      - '**/*.md'
  schedule:
    - cron: '0 5 * * 1'  # Every Monday at 5:00 UTC
  workflow_dispatch:

jobs:
  analyze:
    name: Analyze
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      security-events: write

    strategy:
      fail-fast: false
      matrix:
        language: [ 'javascript', 'python', 'java' ]

    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v2
        with:
          languages: ${{ matrix.language }}
          queries: security-and-quality,
                   security-extended

      - name: Autobuild
        uses: github/codeql-action/autobuild@v2

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v2
        with:
          category: "/language:${{ matrix.language }}"
          output: sarif-results
          upload-artifact: true
          ram: 4096
          threads: 2
          timeout-minutes: 10
EOF

cat > "$BASE_DIR/workflows/ai-remediation.yml" << 'EOF'
name: "AI Security Remediation"

on:
  workflow_run:
    workflows: ["CodeQL Security Analysis"]
    types: [completed]

jobs:
  remediate:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      security-events: read
      actions: read
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Download SARIF results
        uses: actions/github-script@v6
        with:
          script: |
            const artifacts = await github.rest.actions.listWorkflowRunArtifacts({
              owner: context.repo.owner,
              repo: context.repo.repo,
              run_id: ${{ github.event.workflow_run.id }}
            });
            const sarif = artifacts.data.artifacts.find(a => a.name === "sarif-results");
            if (sarif) {
              const download = await github.rest.actions.downloadArtifact({
                owner: context.repo.owner,
                repo: context.repo.repo,
                artifact_id: sarif.id,
                archive_format: 'zip'
              });
              require('fs').writeFileSync('sarif.zip', Buffer.from(download.data));
              require('child_process').execSync('unzip sarif.zip');
            }

      - name: Process with AI
        id: ai-processing
        uses: openai/openai-github-actions@v1
        with:
          model: "gpt-4"
          api-key: ${{ secrets.AI_API_KEY }}
          input-file: "results.sarif"
          output-file: "remediation.json"
          prompt: |
            You are an expert security code remediation specialist.
            Analyze the attached SARIF security findings and generate fixes.
            
            For each vulnerability:
            1. Identify the root cause and vulnerable pattern
            2. Generate optimal fix code that preserves functionality
            3. Explain why your fix resolves the issue
            4. Note any potential side effects
            
            Format your response as JSON with this structure:
            [
              {
                "file_path": "path/to/file.py",
                "fix_type": "replacement",
                "start_line": 42,
                "end_line": 45,
                "replacement_code": "# Fixed code here",
                "explanation": "This fixes the XSS by...",
                "confidence": 0.9
              }
            ]

      - name: Apply Fixes
        run: python ${{ github.workspace }}/.github/CodeQL/tools/apply_ai_fixes.py remediation.json

      - name: Create Fix PR
        uses: peter-evans/create-pull-request@v5
        with:
          title: "AI-generated security fixes"
          body: |
            # Automated Security Fixes
            
            This PR contains AI-generated fixes for security issues identified by CodeQL.
            
            ## Fixes Summary
            
            - Total issues fixed: $(cat fix_summary.txt | grep "Total" | cut -d':' -f2)
            - Fix confidence: $(cat fix_summary.txt | grep "Average confidence" | cut -d':' -f2)
            
            Please review these changes carefully before merging.
          branch: "security-fixes/ai-remediation"
          commit-message: "fix: Apply AI-recommended security patches"
EOF

cat > "$BASE_DIR/workflows/enhanced-reporting.yml" << 'EOF'
name: "Enhanced Security Reporting"

on:
  workflow_run:
    workflows: ["CodeQL Security Analysis"]
    types: [completed]

jobs:
  generate-report:
    runs-on: ubuntu-latest
    permissions:
      actions: read
      contents: read
      security-events: read
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3

      - name: Download SARIF results
        uses: actions/github-script@v6
        with:
          script: |
            const artifacts = await github.rest.actions.listWorkflowRunArtifacts({
              owner: context.repo.owner,
              repo: context.repo.repo,
              run_id: ${{ github.event.workflow_run.id }}
            });
            const sarif = artifacts.data.artifacts.find(a => a.name === "sarif-results");
            if (sarif) {
              const download = await github.rest.actions.downloadArtifact({
                owner: context.repo.owner,
                repo: context.repo.repo,
                artifact_id: sarif.id,
                archive_format: 'zip'
              });
              require('fs').writeFileSync('sarif.zip', Buffer.from(download.data));
              require('child_process').execSync('unzip sarif.zip');
            }

      - name: Generate Enhanced Report
        id: report-generation
        uses: openai/openai-github-actions@v1
        with:
          model: "gpt-4"
          api-key: ${{ secrets.AI_API_KEY }}
          input-file: "results.sarif"
          output-file: "enhanced_security_report.md"
          prompt: |
            Generate an enhanced security report from the SARIF results.
            For each vulnerability, include:
            
            1. DETAILED TECHNICAL EXPLANATION:
               - Provide in-depth technical details about the vulnerability
               - Include relevant code patterns and security principles violated
               - Explain the technical impact on system security
            
            2. NON-TECHNICAL SUMMARY:
               - Create a plain language summary for non-technical stakeholders
               - Use business impact terminology
               - Avoid jargon and explain concepts simply
               
            3. ROOT CAUSE ANALYSIS:
               - Precisely identify underlying code patterns causing the issue
               - Show data flow visualization if applicable
               - Identify architectural or design weaknesses
               
            4. PRIMARY RECOMMENDED FIX:
               - Provide complete implementation of the recommended fix
               - Include all code changes needed, formatted as git diff
               - Explain security principles applied in the fix
               
            5. BEFORE/AFTER CONFIRMATION:
               - Show the code before the fix
               - Show the code after the fix
               - Confirm how the vulnerability has been addressed
            
            Format the report in Markdown with clear sections and code blocks.

      - name: Convert to HTML
        run: python ${{ github.workspace }}/.github/CodeQL/tools/process_vulnerability_report.py enhanced_security_report.md security_report.html

      - name: Upload HTML Report
        uses: actions/upload-artifact@v3
        with:
          name: security-report-html
          path: security_report.html

      - name: Upload Markdown Report
        uses: actions/upload-artifact@v3
        with:
          name: security-report-md
          path: enhanced_security_report.md
EOF

echo "Workflow files created."
echo "----------------------------------------"

# Create tool scripts
echo "Creating tool scripts..."

cat > "$BASE_DIR/tools/apply_ai_fixes.py" << 'EOF'
#!/usr/bin/env python3

import json
import os
import sys
from statistics import mean

def apply_fixes(remediation_file):
    """Apply AI-generated fixes to codebase"""
    with open(remediation_file, 'r') as f:
        fixes = json.load(f)
        
    fix_count = 0
    confidence_scores = []
    
    for fix in fixes:
        file_path = fix.get('file_path')
        if not file_path or not os.path.exists(file_path):
            print(f"Warning: File not found - {file_path}")
            continue
            
        # Read original file
        with open(file_path, 'r') as f:
            original_content = f.read()
            
        # Apply fix based on type
        if fix.get('fix_type') == 'replacement':
            start_line = fix.get('start_line', 0) - 1
            end_line = fix.get('end_line', 0)
            replacement = fix.get('replacement_code', '')
            
            lines = original_content.split('\n')
            new_content = '\n'.join(lines[:start_line] + 
                                  [replacement] + 
                                  lines[end_line:])
            
        elif fix.get('fix_type') == 'insertion':
            line = fix.get('line', 0) - 1
            code = fix.get('code', '')
            
            lines = original_content.split('\n')
            lines.insert(line, code)
            new_content = '\n'.join(lines)
            
        else:
            # For complex fixes, use the complete replacement
            new_content = fix.get('full_file_content', original_content)
            
        # Write fixed file
        with open(file_path, 'w') as f:
            f.write(new_content)
            
        fix_count += 1
        confidence_scores.append(fix.get('confidence', 0.5))
        print(f"Applied fix to {file_path}")
        
    # Generate summary
    with open("fix_summary.txt", "w") as f:
        f.write(f"Total fixes applied: {fix_count}\n")
        if confidence_scores:
            f.write(f"Average confidence: {mean(confidence_scores):.2f}\n")
    
    print(f"Successfully applied {fix_count} fixes")
    
if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: apply_ai_fixes.py <remediation_file>")
        sys.exit(1)
    apply_fixes(sys.argv[1])
EOF

cat > "$BASE_DIR/tools/process_vulnerability_report.py" << 'EOF'
#!/usr/bin/env python3

import sys
import markdown
import os

def generate_html_report(markdown_file, output_html):
    """Convert markdown report to styled HTML"""
    if not os.path.exists(markdown_file):
        print(f"Error: Markdown file '{markdown_file}' not found!")
        return False
    
    try:
        with open(markdown_file, 'r') as f:
            md_content = f.read()
        
        html = markdown.markdown(md_content, extensions=['fenced_code', 'tables'])
        
        # Add styling
        styled_html = f"""<!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Enhanced Security Report</title>
            <style>
                body {{ font-family: Arial, sans-serif; line-height: 1.6; max-width: 1200px; margin: 0 auto; padding: 20px; }}
                h1 {{ color: #d9534f; }}
                h2 {{ color: #337ab7; border-bottom: 1px solid #eee; padding-bottom: 10px; }}
                h3 {{ margin-top: 30px; }}
                h4 {{ color: #5cb85c; }}
                table {{ border-collapse: collapse; width: 100%; margin-bottom: 30px; }}
                th, td {{ border: 1px solid #ddd; padding: 12px; }}
                th {{ background-color: #f2f2f2; }}
                code {{ background-color: #f8f8f8; padding: 2px 5px; border-radius: 3px; }}
                pre {{ background-color: #f8f8f8; padding: 15px; border-radius: 5px; overflow-x: auto; }}
                .diff-add {{ background-color: #e6ffed; }}
                .diff-remove {{ background-color: #ffeef0; }}
                .severity-critical {{ color: #d9534f; font-weight: bold; }}
                .severity-high {{ color: #f0ad4e; font-weight: bold; }}
                .severity-medium {{ color: #5bc0de; }}
                .severity-low {{ color: #5cb85c; }}
            </style>
        </head>
        <body>
            {html}
        </body>
        </html>"""
        
        with open(output_html, 'w') as f:
            f.write(styled_html)
        
        return True
    except Exception as e:
        print(f"Error generating HTML report: {str(e)}")
        return False

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: process_vulnerability_report.py <markdown_report> <output_html>")
        sys.exit(1)
    
    success = generate_html_report(sys.argv[1], sys.argv[2])
    if success:
        print(f"Successfully generated HTML report: {sys.argv[2]}")
    else:
        sys.exit(1)
EOF

# Make Python scripts executable
chmod +x "$BASE_DIR/tools/apply_ai_fixes.py"
chmod +x "$BASE_DIR/tools/process_vulnerability_report.py"

echo "Tool scripts created and made executable."
echo "----------------------------------------"

# Create configuration files
echo "Creating configuration files..."

cat > "$BASE_DIR/config/codeql-config.yml" << 'EOF'
name: "CodeQL Configuration"

queries:
  - name: Security and Quality
    uses: security-and-quality
  - name: Security Extended
    uses: security-extended
  - name: Custom Security Rules
    uses: ./.github/CodeQL/queries/custom-rules.ql

query-filters:
  - exclude:
      id: js/unused-local-variable

paths:
  - src
  - lib
  - bridge
paths-ignore:
  - node_modules
  - '**/*.test.js'
  - '**/*.spec.js'
  - '**/test/**'
  - '**/tests/**'
  - '**/vendor/**'

trap-caching:
  enabled: true
EOF

cat > "$BASE_DIR/config/vscode-settings.json" << 'EOF'
{
  "codeQL.runQueries": "onSave",
  "codeQL.runQuerySuite": "security-and-quality",
  "codeQL.useServerMode": true,
  "codeQL.securityAlertHighlights": "error",
  "codeQL.enableInlineResults": true
}
EOF

echo "Configuration files created."
echo "----------------------------------------"

# Create query files
echo "Creating query files..."

cat > "$BASE_DIR/queries/custom-rules.ql" << 'EOF'
/**
 * @name Insecure Deserialization in Python
 * @description Detects potentially unsafe deserialization of user input
 * @kind path-problem
 * @problem.severity error
 * @precision high
 * @id py/insecure-deserialization
 * @tags security
 *       external/cwe/cwe-502
 */

import python
import DataFlow::PathGraph

class InsecureDeserializationConfig extends TaintTracking::Configuration {
  InsecureDeserializationConfig() { this = "InsecureDeserializationConfig" }
  
  override predicate isSource(DataFlow::Node source) {
    exists(CallNode call |
      call.getFunction().toString() in ["request.POST", "request.GET", "request.data"] and
      source.asExpr() = call
    )
  }
  
  override predicate isSink(DataFlow::Node sink) {
    exists(CallNode call |
      call.getFunction().toString() in ["pickle.loads", "yaml.load"] and
      sink.asExpr() = call.getArg(0)
    )
  }
}

from InsecureDeserializationConfig config, DataFlow::PathNode source, DataFlow::PathNode sink
where config.hasFlowPath(source, sink)
select sink, source, sink, "Insecure deserialization of user data"
EOF

echo "Query files created."
echo "----------------------------------------"

# Create compliance files
echo "Creating compliance mapping files..."

cat > "$BASE_DIR/compliance/mapping.yml" << 'EOF'
compliance:
  mappings:
    - standard: "OWASP Top 10"
      controls:
        "A1:2021-Broken Access Control": 
          - "java/spring-disabled-csrf-protection"
          - "py/url-redirection"
        "A2:2021-Cryptographic Failures": 
          - "java/weak-encryption"
          - "py/weak-cryptography"
        "A3:2021-Injection":
          - "java/sql-injection"
          - "py/sql-injection"
          - "js/xss"
        "A4:2021-Insecure Design":
          - "java/insecure-cookie"
          - "py/insecure-cookie"
        "A5:2021-Security Misconfiguration":
          - "java/xxe-vulnerability"
          - "py/unsafe-deserialization"
        "A6:2021-Vulnerable and Outdated Components":
          - "js/insecure-dependency"
          - "py/insecure-dependency"
        "A7:2021-Identification and Authentication Failures":
          - "java/hardcoded-credentials"
          - "py/hardcoded-credentials"
        "A8:2021-Software and Data Integrity Failures":
          - "js/unsafe-eval"
          - "py/code-injection"
        "A9:2021-Security Logging and Monitoring Failures":
          - "java/insufficient-logging"
          - "py/insufficient-logging"
        "A10:2021-Server-Side Request Forgery":
          - "java/ssrf"
          - "py/ssrf"
          
    - standard: "PCI DSS"
      controls:
        "6.5.1":
          - "java/sql-injection"
          - "py/sql-injection"
        "6.5.7":
          - "java/xss"
          - "js/xss"
        "6.5.8":
          - "java/improper-auth"
          - "py/improper-auth"
EOF

echo "Compliance mapping files created."
echo "----------------------------------------"

# Create template files
echo "Creating template files..."

cat > "$BASE_DIR/templates/vulnerability_report_template.md" << 'EOF'
# Enhanced Security Vulnerability Report

**Generated:** {{TIMESTAMP}}

## Executive Summary

{{SUMMARY_FOR_EXECUTIVES}}

## Findings Overview

| ID | Vulnerability | Severity | Status | Fix Complexity |
|----|--------------|----------|--------|----------------|
{{TABLE_OF_FINDINGS}}

## Detailed Findings

{{#EACH_FINDING}}
### {{FINDING_ID}}: {{TITLE}}

#### Technical Details
{{DETAILED_TECHNICAL_EXPLANATION}}

#### Non-Technical Summary
{{PLAIN_LANGUAGE_SUMMARY}}

#### Root Cause Analysis
{{ROOT_CAUSE_DETAILS}}

#### Recommended Fix
```diff
{{FIX_IMPLEMENTATION_DIFF}}