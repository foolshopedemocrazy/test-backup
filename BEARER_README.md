# Bearer Data Security Scanning

This repository is configured with Bearer security scanning to detect data security issues, PII exposure, and sensitive data leakage.

## What is Bearer?

Bearer is a data security scanner that helps identify and fix sensitive data exposures in your code. It can detect:

- Personal Identifiable Information (PII)
- Financial data
- Health information
- API keys and credentials
- Hardcoded secrets
- Data flow vulnerabilities
- And more...

## How It Works

Bearer is integrated in this repository in three ways:

1. **GitHub Actions Workflow**: Automatically scans code on pushes, pull requests, and scheduled intervals
2. **Local Scanning Script**: Allows developers to run scans locally
3. **Git Pre-commit Hook**: Scans staged changes before committing

## Getting Started

### Prerequisites

- To run Bearer locally, install the Bearer CLI:
  ```bash
  curl -sfL https://raw.githubusercontent.com/bearer/bearer/main/contrib/install.sh | sh
