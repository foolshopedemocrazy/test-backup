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
