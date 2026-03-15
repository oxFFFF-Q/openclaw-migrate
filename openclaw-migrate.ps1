#Requires -Version 5.1
# openclaw-migrate.ps1 — OpenClaw Cross-Platform Migration Tool (PowerShell)
#
# Repository: https://github.com/oxFFFF-Q/openclaw-migrate
# License: MIT
#
# Usage:
#   .\openclaw-migrate.ps1 export [-Mode replicate|full|skills] [-Output path] [-DryRun] [-Verbose]
#   .\openclaw-migrate.ps1 import [-Archive <archive.tar.gz>] [-Force] [-NoBackup]
#   .\openclaw-migrate.ps1 doctor
#   .\openclaw-migrate.ps1 version
#   .\openclaw-migrate.ps1 update
#   .\openclaw-migrate.ps1 help

param(
    [Parameter(Position = 0)]
    [ValidateSet("export", "import", "doctor", "version", "update", "help")]
    [string]$Action = "help",

    [ValidateSet("replicate", "full", "skills")]
    [string]$Mode = "replicate",

    [string]$Output,
    [string]$Archive,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoBackup
)

$ErrorActionPreference = "Stop"

# ── Configuration ──────────────────────────────────────────────────────────

$script:VERSION = "1.1.0"
$script:SCRIPT_NAME = "openclaw-migrate"
$script:REPO_URL = "https://github.com/oxFFFF-Q/openclaw-migrate"
$script:REPO_RAW_URL = "https://raw.githubusercontent.com/oxFFFF-Q/openclaw-migrate/main"

$script:OpenClawDir = if ($env:OPENCLAW_DIR) { $env:OPENCLAW_DIR } else { Join-Path $env:USERPROFILE ".openclaw" }
$script:WorkspaceDir = Join-Path $script:OpenClawDir "workspace"
$script:Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
if (-not $Output) { $Output = Join-Path $env:USERPROFILE "openclaw-export-$($script:Timestamp).tar.gz" }
$script:LogFile = Join-Path ([System.IO.Path]::GetTempPath()) "openclaw-migrate-$($script:Timestamp).log"

# ── Colors & Output ────────────────────────────────────────────────────────

function Write-Log { param($m) Add-Content -Path $script:LogFile -Value "[$(Get-Date -Format 'HH:mm:ss')] $m" -ErrorAction SilentlyContinue }
function Write-Info  { param($m) Write-Host "ℹ  $m" -ForegroundColor Cyan;    Write-Log "[INFO] $m" }
function Write-Ok    { param($m) Write-Host "✔  $m" -ForegroundColor Green;   Write-Log "[OK] $m" }
function Write-Warn  { param($m) Write-Host "⚠  $m" -ForegroundColor Yellow;  Write-Log "[WARN] $m" }
function Write-Err   { param($m) Write-Host "✖  $m" -ForegroundColor Red;     Write-Log "[ERROR] $m" }
function Exit-Fatal  { param($m) Write-Err $m; exit 1 }

function Show-Banner {
    Write-Host ""
    Write-Host "  ____                          _____ _       _ _     _ _ " -ForegroundColor Magenta
    Write-Host " / __ \                        / ____| |     | | |   (_) |" -ForegroundColor Magenta
    Write-Host "| |  | |_   _____ _ __  ___   | |    | |_   _| | |___ _| |" -ForegroundColor Magenta
    Write-Host "| |  | |\ \ / / _ \ '_ \/ __|  | |    | | | | | | / __| | |" -ForegroundColor Magenta
    Write-Host "| |__| |\ V /  __/ | | \__ \  | |____| | |_| | | \__ \ | |" -ForegroundColor Magenta
    Write-Host " \____/  \_/ \___|_| |_|___/   \_____|_|\__,_|_|_|___/_|_|" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Cross-Platform Migration Tool v$($script:VERSION)" -NoNewline
    Write-Host ""
    Write-Host "  $($script:REPO_URL)"
    Write-Host ""
}

# ── System Detection ───────────────────────────────────────────────────────

function Get-OSInfo {
    if ($IsLinux) { return "linux" }
    if ($IsMacOS) { return "macos" }
    # Windows (PowerShell 5.1 or pwsh on Windows)
    return "windows"
}

function Get-PackageManager {
    $os = Get-OSInfo
    switch ($os) {
        "windows" {
            if (Get-Command winget -ErrorAction SilentlyContinue) { return "winget" }
            if (Get-Command choco -ErrorAction SilentlyContinue) { return "choco" }
            if (Get-Command scoop -ErrorAction SilentlyContinue) { return "scoop" }
            return "none"
        }
        "macos" { return "brew" }
        "linux" { return "apt" }
    }
}

# ── Dependency Management ──────────────────────────────────────────────────

function Test-Node {
    try {
        $v = & node -v 2>$null
        if ($v) {
            $major = [int]($v -replace '^v' -replace '\..*')
            if ($major -ge 18) {
                Write-Ok "Node.js $v detected"
                return $true
            } else {
                Write-Warn "Node.js $v detected, but version 18+ is recommended"
                return $false
            }
        }
    } catch {}
    Write-Warn "Node.js not found"
    return $false
}

function Test-Npm {
    try {
        $v = & npm --version 2>$null
        if ($v) { Write-Ok "npm $v detected"; return $true }
    } catch {}
    Write-Warn "npm not found"
    return $false
}

function Test-OpenClaw {
    try {
        $v = & openclaw --version 2>$null
        if ($LASTEXITCODE -eq 0 -or $v) {
            Write-Ok "OpenClaw detected: $v"
            return $true
        }
    } catch {}

    # Check common install paths
    $binPath = Join-Path $script:OpenClawDir "bin/openclaw"
    if (Test-Path $binPath) {
        Write-Warn "OpenClaw found at $binPath but not in PATH"
        return $true
    }

    Write-Warn "OpenClaw not found"
    return $false
}

function Test-Tar {
    if (Get-Command tar -ErrorAction SilentlyContinue) { return $true }
    Exit-Fatal "tar is required but not installed"
}

function Install-NodeJS {
    Write-Info "Installing Node.js..."
    $pm = Get-PackageManager

    switch ($pm) {
        "winget" {
            & winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) { Exit-Fatal "Failed to install Node.js via winget" }
        }
        "choco" {
            & choco install nodejs-lts -y
            if ($LASTEXITCODE -ne 0) { Exit-Fatal "Failed to install Node.js via Chocolatey" }
        }
        "scoop" {
            & scoop install nodejs-lts
            if ($LASTEXITCODE -ne 0) { Exit-Fatal "Failed to install Node.js via Scoop" }
        }
        "brew" {
            & brew install node
            if ($LASTEXITCODE -ne 0) { Exit-Fatal "Failed to install Node.js via Homebrew" }
        }
        default {
            Exit-Fatal "No supported package manager found. Install Node.js manually from https://nodejs.org"
        }
    }

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
    Write-Ok "Node.js installed: $(node -v 2>$null)"
}

function Install-OpenClaw {
    Write-Info "Installing OpenClaw..."

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Exit-Fatal "npm is required to install OpenClaw"
    }

    & npm install -g openclaw
    if ($LASTEXITCODE -ne 0) {
        Exit-Fatal "Failed to install OpenClaw"
    }

    Write-Ok "OpenClaw installed: $(openclaw --version 2>$null)"
}

# ── Export Functions ───────────────────────────────────────────────────────

function Invoke-Export {
    # Validate source
    if (-not (Test-Path $script:OpenClawDir)) {
        Exit-Fatal "OpenClaw directory not found: $($script:OpenClawDir)"
    }

    if ($DryRun) {
        Write-Info "DRY RUN - No files will be created"
        Write-Host ""
    }

    Write-Info "Exporting in '$Mode' mode..."

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "openclaw-export-$($script:Timestamp)"
    $exportDir = Join-Path $tmpDir "openclaw-export"
    New-Item -ItemType Directory -Path $exportDir -Force | Out-Null

    $script:fileCount = 0

    # Helper to copy with feedback
    function Copy-ExportItem {
        param([string]$Src, [string]$Dst, [string]$Name)
        if (Test-Path $Src) {
            $parentDir = Split-Path $Dst -Parent
            if ($parentDir -and -not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            if ((Get-Item $Src).PSIsContainer) {
                Copy-Item $Src $Dst -Recurse -Force
            } else {
                Copy-Item $Src $Dst -Force
            }
            $script:fileCount++
            if ($VerbosePreference -eq 'Continue') { Write-Ok "$Name" }
            return $true
        }
        if ($VerbosePreference -eq 'Continue') { Write-Warn "$Name not found, skipping" }
        return $false
    }

    switch ($Mode) {
        "skills" {
            Write-Info "Exporting skills only..."
            $src = Join-Path $script:WorkspaceDir "skills"
            Copy-ExportItem -Src $src -Dst (Join-Path $exportDir "workspace/skills") -Name "Skills"
        }
        "replicate" {
            Write-Info "Exporting configuration (replicate mode)..."

            # Core config
            Copy-ExportItem -Src (Join-Path $script:OpenClawDir "openclaw.json") -Dst (Join-Path $exportDir "openclaw.json") -Name "openclaw.json"

            # Workspace directories
            Copy-ExportItem -Src (Join-Path $script:WorkspaceDir "skills") -Dst (Join-Path $exportDir "workspace/skills") -Name "Skills"
            Copy-ExportItem -Src (Join-Path $script:WorkspaceDir "scripts") -Dst (Join-Path $exportDir "workspace/scripts") -Name "Scripts"

            # Documentation files
            foreach ($f in @("AGENTS.md", "TOOLS.md", "SOUL.md", "USER.md", "IDENTITY.md", "HEARTBEAT.md", "MEMORY.md")) {
                $src = Join-Path $script:WorkspaceDir $f
                $dst = Join-Path $exportDir "workspace/$f"
                Copy-ExportItem -Src $src -Dst $dst -Name $f
            }

            # PLANS directory
            $plansDir = Join-Path $script:WorkspaceDir "PLANS"
            if (Test-Path $plansDir) {
                Copy-ExportItem -Src $plansDir -Dst (Join-Path $exportDir "workspace/PLANS") -Name "PLANS"
            }
        }
        "full" {
            Write-Info "Exporting full configuration..."
            Write-Warn "This includes memory and credentials!"

            Copy-Item "$($script:OpenClawDir)/*" $exportDir -Recurse -Force

            # Remove large/ephemeral directories
            foreach ($d in @("sessions", "logs", "tmp")) {
                $removeDir = Join-Path $exportDir $d
                if (Test-Path $removeDir) { Remove-Item $removeDir -Recurse -Force }
            }

            Write-Ok "Full export (excluding sessions/logs/tmp)"
            $script:fileCount = (Get-ChildItem $exportDir -Recurse -File).Count
        }
    }

    # Generate manifest
    Write-Info "Generating manifest..."
    $ocVersion = try { & openclaw --version 2>$null } catch { "not installed" }
    $nodeVersion = try { & node -v 2>$null } catch { "not installed" }
    $npmVersion = try { & npm --version 2>$null } catch { "not installed" }

    $manifest = [ordered]@{
        version    = $script:VERSION
        mode       = $Mode
        timestamp  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        source     = [ordered]@{
            os       = Get-OSInfo
            hostname = $env:COMPUTERNAME ?? (hostname)
            user     = $env:USERNAME ?? $env:USER ?? "unknown"
        }
        versions   = [ordered]@{
            openclaw = "$ocVersion"
            node     = "$nodeVersion"
            npm      = "$npmVersion"
        }
        export     = [ordered]@{
            file_count  = $script:fileCount
            compression = "gzip"
        }
    } | ConvertTo-Json -Depth 4

    $manifest | Out-File (Join-Path $exportDir "manifest.json") -Encoding utf8

    if ($DryRun) {
        Write-Host ""
        Write-Info "Files that would be exported:"
        Get-ChildItem $exportDir -Recurse -File | Select-Object -First 50 | ForEach-Object { Write-Host "  $($_.FullName.Replace($exportDir, ''))" }
        $totalFiles = (Get-ChildItem $exportDir -Recurse -File).Count
        Write-Host ""
        Write-Info "Total: $totalFiles files"
        Write-Host ""
        Write-Info "Manifest preview:"
        Write-Host $manifest
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        return
    }

    # Create archive
    Write-Info "Creating archive..."
    & tar -czf $Output -C $tmpDir "openclaw-export"
    if ($LASTEXITCODE -ne 0) { Exit-Fatal "Failed to create archive" }

    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    $finalSize = [math]::Round((Get-Item $Output).Length / 1KB)

    Write-Host ""
    Write-Ok "Export complete!"
    Write-Host ""
    Write-Host "  Output:     $Output" -ForegroundColor White
    Write-Host "  Size:       ${finalSize} KB" -ForegroundColor White
    Write-Host "  Files:      $($script:fileCount)" -ForegroundColor White
    Write-Host "  Mode:       $Mode" -ForegroundColor White
    Write-Host ""
    Write-Host "  To import on another device:" -ForegroundColor Cyan
    Write-Host "  .\openclaw-migrate.ps1 import -Archive $Output"
    Write-Host ""
}

# ── Import Functions ───────────────────────────────────────────────────────

function Invoke-Import {
    if (-not $Archive) { Exit-Fatal "Usage: .\openclaw-migrate.ps1 import -Archive <file.tar.gz>" }
    if (-not (Test-Path $Archive)) { Exit-Fatal "File not found: $Archive" }

    # Validate archive
    try {
        & tar -tzf $Archive 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw }
    } catch {
        Exit-Fatal "Invalid archive: not a valid gzip tar file"
    }

    Write-Info "Extracting archive..."

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "openclaw-import-$($script:Timestamp)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    & tar -xzf $Archive -C $tmpDir
    if ($LASTEXITCODE -ne 0) { Exit-Fatal "Failed to extract archive" }

    $exportDir = Join-Path $tmpDir "openclaw-export"
    if (-not (Test-Path $exportDir)) { Exit-Fatal "Invalid archive: missing openclaw-export directory" }

    $manifestPath = Join-Path $exportDir "manifest.json"
    if (-not (Test-Path $manifestPath)) { Exit-Fatal "Invalid archive: missing manifest.json" }

    # Display manifest
    Write-Host ""
    Write-Info "Archive information:"
    Write-Host ("─" * 40) -ForegroundColor Cyan
    Get-Content $manifestPath | Write-Host
    Write-Host ("─" * 40) -ForegroundColor Cyan
    Write-Host ""

    # Check dependencies
    Write-Info "Checking dependencies..."

    if (-not (Test-Node)) {
        if ($Force) {
            Install-NodeJS
        } else {
            $ans = Read-Host "Install Node.js now? [Y/n]"
            if ($ans -match "^[Nn]") { Exit-Fatal "Cannot import without Node.js" }
            Install-NodeJS
        }
    }

    if (-not (Test-OpenClaw)) {
        if ($Force) {
            Install-OpenClaw
        } else {
            $ans = Read-Host "Install OpenClaw now? [Y/n]"
            if ($ans -match "^[Nn]") { Exit-Fatal "Cannot import without OpenClaw" }
            Install-OpenClaw
        }
    }

    # Backup existing config
    if ((Test-Path $script:OpenClawDir) -and -not $NoBackup) {
        $backup = Join-Path $env:USERPROFILE "openclaw-backup-$($script:Timestamp).tar.gz"
        Write-Info "Backing up existing configuration..."
        try {
            & tar -czf $backup -C $env:USERPROFILE ".openclaw"
            Write-Ok "Backup: $backup"
        } catch {
            Write-Warn "Backup failed, continuing anyway"
        }
    }

    # Confirm import
    if (-not $Force) {
        Write-Host ""
        $ans = Read-Host "Proceed with import? [y/N]"
        if ($ans -notmatch "^[Yy]") { Exit-Fatal "Import cancelled" }
    }

    # Import files
    New-Item -ItemType Directory -Path $script:OpenClawDir -Force | Out-Null
    Write-Info "Importing files..."

    # Config
    $cfg = Join-Path $exportDir "openclaw.json"
    if (Test-Path $cfg) {
        Copy-Item $cfg $script:OpenClawDir -Force
        Write-Ok "openclaw.json"
    }

    # Workspace
    $ws = Join-Path $exportDir "workspace"
    if (Test-Path $ws) {
        New-Item -ItemType Directory -Path $script:WorkspaceDir -Force | Out-Null
        Copy-Item "$ws/*" $script:WorkspaceDir -Recurse -Force
        Write-Ok "Workspace files"
    }

    # Additional directories (from full export)
    foreach ($d in @("extensions", "identity", "memory", "credentials")) {
        $src = Join-Path $exportDir $d
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $script:OpenClawDir $d) -Recurse -Force
            Write-Ok "$d/"
        }
    }

    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Ok "Import complete! 🎉"
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Run: openclaw doctor"
    Write-Host "  2. Restart any running OpenClaw services"
    Write-Host "  3. Verify configuration: Get-Content ~/.openclaw/openclaw.json"
    Write-Host ""
}

# ── Doctor Function ─────────────────────────────────────────────────────────

function Invoke-Doctor {
    Show-Banner

    Write-Info "Running diagnostics..."
    Write-Host ""

    $issues = 0

    # System info
    Write-Host "System Information" -ForegroundColor White
    Write-Host "  OS:         $(Get-OSInfo)"
    Write-Host "  Hostname:   $($env:COMPUTERNAME ?? (hostname))"
    Write-Host "  User:       $($env:USERNAME ?? $env:USER ?? 'unknown')"
    Write-Host "  PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host ""

    # Node.js
    Write-Host "Node.js" -ForegroundColor White
    if (Test-Node) {
        Write-Host "  Version:    $(node -v 2>$null)"
        Write-Host "  Path:       $((Get-Command node -ErrorAction SilentlyContinue).Source)"
    } else {
        Write-Host "  ✖ Not installed" -ForegroundColor Red
        $issues++
    }
    Write-Host ""

    # npm
    Write-Host "npm" -ForegroundColor White
    if (Test-Npm) {
        Write-Host "  Version:    $(npm --version 2>$null)"
        Write-Host "  Path:       $((Get-Command npm -ErrorAction SilentlyContinue).Source)"
    } else {
        Write-Host "  ✖ Not installed" -ForegroundColor Red
        $issues++
    }
    Write-Host ""

    # OpenClaw
    Write-Host "OpenClaw" -ForegroundColor White
    if (Test-OpenClaw) {
        Write-Host "  Version:    $(openclaw --version 2>$null)"
        Write-Host "  Path:       $((Get-Command openclaw -ErrorAction SilentlyContinue).Source)"
    } else {
        Write-Host "  ✖ Not installed" -ForegroundColor Red
        $issues++
    }
    Write-Host ""

    # Configuration
    Write-Host "Configuration" -ForegroundColor White
    if (Test-Path $script:OpenClawDir) {
        Write-Host "  Directory:  $($script:OpenClawDir) " -NoNewline; Write-Host "✓" -ForegroundColor Green

        $cfgPath = Join-Path $script:OpenClawDir "openclaw.json"
        if (Test-Path $cfgPath) {
            Write-Host "  Config:     openclaw.json " -NoNewline; Write-Host "✓" -ForegroundColor Green
        } else {
            Write-Host "  Config:     " -NoNewline; Write-Host "✖ Missing openclaw.json" -ForegroundColor Red
            $issues++
        }

        if (Test-Path $script:WorkspaceDir) {
            Write-Host "  Workspace:  " -NoNewline; Write-Host "✓" -ForegroundColor Green

            $skillsDir = Join-Path $script:WorkspaceDir "skills"
            if (Test-Path $skillsDir) {
                $skillCount = (Get-ChildItem $skillsDir -Directory -ErrorAction SilentlyContinue).Count
                Write-Host "  Skills:     $skillCount installed"
            }
        } else {
            Write-Host "  Workspace:  " -NoNewline; Write-Host "⚠ Not found" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Directory:  " -NoNewline; Write-Host "✖ $($script:OpenClawDir) not found" -ForegroundColor Red
        $issues++
    }
    Write-Host ""

    # Summary
    Write-Host "Summary" -ForegroundColor White
    if ($issues -eq 0) {
        Write-Host "  All checks passed! ✓" -ForegroundColor Green
    } else {
        Write-Host "  Found $issues issue(s)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Suggested fixes:" -ForegroundColor Cyan
        if (-not (Test-Path $script:OpenClawDir)) { Write-Host "  • Install OpenClaw: npm install -g openclaw" }
        if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Write-Host "  • Install Node.js: https://nodejs.org" }
    }
    Write-Host ""
}

# ── Version & Self-Update ──────────────────────────────────────────────────

function Show-Version {
    Write-Host "$($script:SCRIPT_NAME) v$($script:VERSION)"
    Write-Host "Repository: $($script:REPO_URL)"
}

function Invoke-SelfUpdate {
    Write-Info "Checking for updates..."

    try {
        $latestVersion = (Invoke-WebRequest -Uri "$($script:REPO_RAW_URL)/VERSION" -UseBasicParsing -TimeoutSec 10).Content.Trim()
    } catch {
        Write-Warn "Could not check for updates"
        return
    }

    if ($script:VERSION -eq $latestVersion) {
        Write-Ok "Already up to date (v$($script:VERSION))"
        return
    }

    Write-Info "New version available: v$latestVersion (current: v$($script:VERSION))"

    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }

    $ans = Read-Host "Update now? [Y/n]"
    if ($ans -match "^[Nn]") { return }

    try {
        $tmpFile = [System.IO.Path]::GetTempFileName()
        Invoke-WebRequest -Uri "$($script:REPO_RAW_URL)/openclaw-migrate.ps1" -OutFile $tmpFile -UseBasicParsing -TimeoutSec 30
        Copy-Item $tmpFile $scriptPath -Force
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
        Write-Ok "Updated to v$latestVersion"
    } catch {
        Exit-Fatal "Failed to download update: $_"
    }
}

# ── Main Entry Point ───────────────────────────────────────────────────────

function Show-Usage {
    Show-Banner
    Write-Host "Usage:" -ForegroundColor White
    Write-Host "  .\openclaw-migrate.ps1 <command> [options]"
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor White
    Write-Host "  export        Export OpenClaw configuration"
    Write-Host "  import        Import configuration from archive"
    Write-Host "  doctor        Run system diagnostics"
    Write-Host "  version       Show version information"
    Write-Host "  update        Update to latest version"
    Write-Host "  help          Show this help message"
    Write-Host ""
    Write-Host "Export Options:" -ForegroundColor White
    Write-Host "  -Mode MODE        Mode: replicate (default), full, skills"
    Write-Host "  -Output PATH      Custom output path"
    Write-Host "  -DryRun           Preview without creating files"
    Write-Host "  -Verbose          Show detailed output"
    Write-Host ""
    Write-Host "Import Options:" -ForegroundColor White
    Write-Host "  -Archive PATH     Archive file to import"
    Write-Host "  -Force            Skip confirmation prompts"
    Write-Host "  -NoBackup         Don't backup existing config"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor White
    Write-Host "  # Export configuration"
    Write-Host "  .\openclaw-migrate.ps1 export"
    Write-Host "  .\openclaw-migrate.ps1 export -Mode full -Output C:\tmp\backup.tar.gz"
    Write-Host "  .\openclaw-migrate.ps1 export -DryRun"
    Write-Host ""
    Write-Host "  # Import on new machine"
    Write-Host "  .\openclaw-migrate.ps1 import -Archive openclaw-export-*.tar.gz"
    Write-Host ""
    Write-Host "  # Check system health"
    Write-Host "  .\openclaw-migrate.ps1 doctor"
    Write-Host ""
    Write-Host "Repository: $($script:REPO_URL)" -ForegroundColor White
    Write-Host "License: MIT" -ForegroundColor White
    Write-Host ""
}

switch ($Action) {
    "export"  { Invoke-Export }
    "import"  { Invoke-Import }
    "doctor"  { Invoke-Doctor }
    "version" { Show-Version }
    "update"  { Invoke-SelfUpdate }
    default   { Show-Usage }
}
