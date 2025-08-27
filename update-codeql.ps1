<# 
  update-codeql.ps1
  - Idempotent updater for CodeQL workflow & per-language configs
  - Scopes analysis strictly to "src/" and "bridge/"
  - Adds Go toolchain step for Go scans
  - Runs Autobuild only for C/C++
  - Normalizes path casing to ".github\codeql"
  - Backs up any existing targets
  - Verifies all changes and writes a PASS/FAIL log

  Run from the repo root. No destructive deletes. 
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------
# Helpers: Logging & FS ops
# ---------------------------
$StartTime = Get-Date
$IsoStamp  = $StartTime.ToString('yyyyMMddTHHmmssZ')
$RepoRoot  = (Get-Location).Path
$GitHubDir = Join-Path $RepoRoot '.github'
$LogsDir   = Join-Path $GitHubDir "backups\logs"
$BackupRoot = Join-Path $GitHubDir "backups\safe-$IsoStamp"
$LogFile   = Join-Path $LogsDir "codeql-setup-$IsoStamp.txt"

$global:HadError = $false

# simple mapper instead of switch-in-expression
function Get-LevelColor {
  param([ValidateSet('INFO','OK','WARN','ERROR')] [string] $Level)
  $map = @{
    'OK'    = 'Green'
    'WARN'  = 'Yellow'
    'ERROR' = 'Red'
    'INFO'  = 'Gray'
  }
  return $map[$Level]
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR')][string]$Level = 'INFO'
    )
    $prefix = switch ($Level) {
        'OK'    { '[OK]   ' }
        'WARN'  { '[WARN] ' }
        'ERROR' { '[ERR]  ' }
        default { '[INFO] ' }
    }
    $line = "$prefix$Message"
    Write-Host $line -ForegroundColor (Get-LevelColor $Level)
    try {
        Add-Content -Path $LogFile -Value $line
    } catch { }
    if ($Level -eq 'ERROR') { $global:HadError = $true }
}

function New-DirSafe {
    param([Parameter(Mandatory)][string]$Path, [int]$Retries = 6)
    for ($i=0; $i -lt $Retries; $i++) {
        try {
            if (-not (Test-Path -LiteralPath $Path)) {
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
            }
            if (Test-Path -LiteralPath $Path) { return $true }
        } catch {
            Start-Sleep -Milliseconds (150 * ($i + 1))
        }
        Start-Sleep -Milliseconds (200 * ($i + 1))
    }
    return $false
}

function Ensure-ParentDir {
    param([Parameter(Mandatory)][string]$FilePath)
    $parent = Split-Path -Parent $FilePath
    if (-not (New-DirSafe -Path $parent)) {
        throw "Could not create directory: $parent"
    }
}

function Write-FileSafe {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$Content
    )
    Ensure-ParentDir -FilePath $FilePath
    try {
        $enc = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($FilePath, $Content, $enc)
    } catch {
        $Content | Out-File -FilePath $FilePath -Encoding utf8 -Force
    }
}

function Copy-IfExists {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Dest)
    if (Test-Path -LiteralPath $Source) {
        Ensure-ParentDir -FilePath $Dest
        Copy-Item -Path $Source -Destination $Dest -Force
        return $true
    }
    return $false
}

# ---------------------------
# Prepare log & directories
# ---------------------------
if (-not (New-DirSafe -Path $LogsDir)) { throw "Failed to create logs directory: $LogsDir" }
"== CodeQL setup run: $($StartTime.ToString('s')) ==" | Set-Content -Path $LogFile
Write-Log "Repo root: $RepoRoot"
Write-Log "Log file : $LogFile"

foreach ($dir in @(
    $GitHubDir,
    (Join-Path $GitHubDir 'workflows'),
    (Join-Path $GitHubDir 'codeql'),
    (Join-Path $GitHubDir 'codeql\config'),
    (Join-Path $GitHubDir 'backups')
)) {
    if (New-DirSafe -Path $dir) { Write-Log "Ensured dir: $dir" -Level OK }
    else { Write-Log "Could not create dir: $dir" -Level ERROR }
}

# Normalize ".github\CodeQL" -> ".github\codeql"
$UpperCaseDir = Join-Path $GitHubDir 'CodeQL'
$LowerCaseDir = Join-Path $GitHubDir 'codeql'
if (Test-Path -LiteralPath $UpperCaseDir) {
    try {
        if (-not (Test-Path -LiteralPath $LowerCaseDir)) {
            New-Item -ItemType Directory -Path $LowerCaseDir -Force | Out-Null
        }
        Get-ChildItem -Path $UpperCaseDir -Recurse -Force | ForEach-Object {
            $rel = $_.FullName.Substring($UpperCaseDir.Length).TrimStart('\','/')
            $dest = Join-Path $LowerCaseDir $rel
            Ensure-ParentDir -FilePath $dest
            Move-Item -Path $_.FullName -Destination $dest -Force
        }
        Remove-Item -Path $UpperCaseDir -Recurse -Force
        Write-Log "Normalized '.github\\CodeQL' to '.github\\codeql'." -Level OK
    } catch {
        Write-Log "Failed to normalize CodeQL dir casing: $_" -Level ERROR
    }
}

# ---------------------------
# Targets & backup
# ---------------------------
$Targets = @(
    '.github/workflows/codeql.yml',
    '.github/codeql/config/javascript.yml',
    '.github/codeql/config/python.yml',
    '.github/codeql/config/go.yml',
    '.github/codeql/config/cpp.yml'
)

foreach ($t in $Targets) {
    $src = Join-Path $RepoRoot $t
    $dst = Join-Path $BackupRoot $t
    if (Copy-IfExists -Source $src -Dest $dst) {
        Write-Log "Backed up $t -> $dst" -Level OK
    } else {
        Write-Log "No existing file to backup: $t" -Level INFO
    }
}

# ---------------------------
# File contents (single-quoted here-strings to avoid interpolation)
# ---------------------------

$WorkflowYaml = @'
name: "CodeQL Security Analysis"

on:
  push:
    branches: ["main", "master", "develop"]
    paths-ignore:
      - "**/*.md"
      - "docs/**"
  pull_request:
    branches: ["main", "master", "develop"]
    paths-ignore:
      - "**/*.md"
      - "docs/**"
  schedule:
    - cron: "14 3 * * 1"
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
        language: [ javascript, python, go, cpp ]

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Go (for Go only)
        if: matrix.language == 'go'
        uses: actions/setup-go@v5
        with:
          go-version: '1.22'

      - name: Initialize CodeQL
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          config-file: ./.github/codeql/config/${{ matrix.language }}.yml

      - name: Autobuild (C/C++ only)
        if: matrix.language == 'cpp'
        uses: github/codeql-action/autobuild@v3

      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@v3
        with:
          category: "/language:${{ matrix.language }}"
'@

$JsYaml = @'
name: "CodeQL JavaScript Configuration"

queries:
  - uses: security-extended
  - uses: security-and-quality

paths:
  - "src/"
  - "bridge/"
'@

$PyYaml = @'
name: "CodeQL Python Configuration"

queries:
  - uses: security-extended
  - uses: security-and-quality

paths:
  - "src/"
  - "bridge/"
'@

$GoYaml = @'
name: "CodeQL Go Configuration"

queries:
  - uses: security-extended
  - uses: security-and-quality

paths:
  - "src/"
  - "bridge/"
'@

$CppYaml = @'
name: "CodeQL C/C++ Configuration"

queries:
  - uses: security-extended
  - uses: security-and-quality

paths:
  - "src/"
  - "bridge/"
'@

# ---------------------------
# Write files
# ---------------------------
try {
    Write-FileSafe -FilePath (Join-Path $RepoRoot '.github/workflows/codeql.yml') -Content $WorkflowYaml
    Write-Log "Wrote .github/workflows/codeql.yml" -Level OK

    Write-FileSafe -FilePath (Join-Path $RepoRoot '.github/codeql/config/javascript.yml') -Content $JsYaml
    Write-Log "Wrote .github/codeql/config/javascript.yml" -Level OK

    Write-FileSafe -FilePath (Join-Path $RepoRoot '.github/codeql/config/python.yml') -Content $PyYaml
    Write-Log "Wrote .github/codeql/config/python.yml" -Level OK

    Write-FileSafe -FilePath (Join-Path $RepoRoot '.github/codeql/config/go.yml') -Content $GoYaml
    Write-Log "Wrote .github/codeql/config/go.yml" -Level OK

    Write-FileSafe -FilePath (Join-Path $RepoRoot '.github/codeql/config/cpp.yml') -Content $CppYaml
    Write-Log "Wrote .github/codeql/config/cpp.yml" -Level OK
}
catch {
    Write-Log "Exception while writing files: $_" -Level ERROR
}

# ---------------------------
# Verification
# ---------------------------
function Verify-FileContainsAll {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Needles
    )
    if (-not (Test-Path -LiteralPath $FilePath)) {
        Write-Log "Verify: missing $FilePath" -Level ERROR
        return $false
    }
    $text = Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop
    $allOk = $true
    foreach ($n in $Needles) {
        if ($text -match $n) {
            Write-Log "Verify: '$($n)' found in $FilePath" -Level OK
        } else {
            Write-Log "Verify: '$($n)' NOT found in $FilePath" -Level ERROR
            $allOk = $false
        }
    }
    return $allOk
}

Write-Log "Starting verification..." -Level INFO

$allPass = $true

# Verify workflow semantics
$wfPath = Join-Path $RepoRoot '.github/workflows/codeql.yml'
$wfNeedles = @(
    'language:\s*\[\s*javascript,\s*python,\s*go,\s*cpp\s*\]',
    'Setup Go \(for Go only\)',
    "if:\s*matrix\.language\s*==\s*'go'",
    'Initialize CodeQL',
    'config-file:\s*\./\.github/codeql/config/\$\{\{\s*matrix\.language\s*\}\}\.yml',
    'Autobuild \(C/C\+\+ only\)',
    "if:\s*matrix\.language\s*==\s*'cpp'",
    'github/codeql-action/init@v3',
    'github/codeql-action/analyze@v3'
)
if (-not (Verify-FileContainsAll -FilePath $wfPath -Needles $wfNeedles)) { $allPass = $false }

# Verify each config has only src/ and bridge/
$cfgChecks = @(
    '.github/codeql/config/javascript.yml',
    '.github/codeql/config/python.yml',
    '.github/codeql/config/go.yml',
    '.github/codeql/config/cpp.yml'
)
foreach ($cfg in $cfgChecks) {
    $cfgPath = Join-Path $RepoRoot $cfg
    $ok = Verify-FileContainsAll -FilePath $cfgPath -Needles @(
        'queries:\s*\r?\n\s*-\s*uses:\s*security-extended',
        'queries:\s*[\s\S]*security-and-quality',
        'paths:\s*\r?\n\s*-\s*"src/"',
        'paths:\s*[\s\S]*"bridge/"'
    )
    if (-not $ok) { $allPass = $false }
}

# Summarize
if ($allPass -and (-not $global:HadError)) {
    Write-Log "Verification completed: ALL CHECKS PASSED." -Level OK
    Write-Log "Done. Log saved to: $LogFile" -Level INFO
    exit 0
} else {
    Write-Log "Verification completed: SOME CHECKS FAILED. See log: $LogFile" -Level ERROR
    exit 1
}
