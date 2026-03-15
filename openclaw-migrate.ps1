# openclaw-migrate.ps1 — OpenClaw Cross-Platform Migration Tool (Windows)
# Usage:
#   .\openclaw-migrate.ps1 export -Mode replicate|full|skills [-Output path]
#   .\openclaw-migrate.ps1 import -Archive <archive.tar.gz>

param(
    [Parameter(Position=0)]
    [ValidateSet("export", "import", "help")]
    [string]$Action = "help",

    [ValidateSet("replicate", "full", "skills")]
    [string]$Mode = "replicate",

    [string]$Output,
    [string]$Archive
)

$ErrorActionPreference = "Stop"
$Version = "1.0.0"
$OpenClawDir = if ($env:OPENCLAW_DIR) { $env:OPENCLAW_DIR } else { Join-Path $env:USERPROFILE ".openclaw" }
$WorkspaceDir = Join-Path $OpenClawDir "workspace"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
if (-not $Output) { $Output = Join-Path $env:USERPROFILE "openclaw-export-$Timestamp.tar.gz" }

function Write-Info  { param($m) Write-Host "i  $m" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "✔  $m" -ForegroundColor Green }
function Write-Warn  { param($m) Write-Host "⚠  $m" -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host "✖  $m" -ForegroundColor Red }
function Exit-Fatal  { param($m) Write-Err $m; exit 1 }

# ── System Detection ──────────────────────────────────────────────
function Test-Node {
    try { $v = & node -v 2>$null; Write-Ok "Node.js $v detected"; return $true }
    catch { Write-Warn "Node.js not found"; return $false }
}

function Test-OpenClaw {
    try { $null = & openclaw --version 2>$null; Write-Ok "OpenClaw detected"; return $true }
    catch { return $false }
}

function Install-OpenClaw {
    Write-Info "Installing OpenClaw..."
    if (-not (Test-Node)) {
        Write-Info "Installing Node.js via winget..."
        try { winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements }
        catch { Exit-Fatal "Failed to install Node.js. Install manually from https://nodejs.org" }
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
    }
    & npm install -g openclaw
    if ($LASTEXITCODE -ne 0) { Exit-Fatal "Failed to install OpenClaw" }
    Write-Ok "OpenClaw installed"
}

# ── Export ────────────────────────────────────────────────────────
function Invoke-Export {
    if (-not (Test-Path $OpenClawDir)) { Exit-Fatal "OpenClaw directory not found: $OpenClawDir" }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "openclaw-export-$Timestamp"
    $exportDir = Join-Path $tmpDir "openclaw-export"
    New-Item -ItemType Directory -Path $exportDir -Force | Out-Null

    Write-Info "Exporting in '$Mode' mode..."

    switch ($Mode) {
        "skills" {
            $src = Join-Path $WorkspaceDir "skills"
            if (Test-Path $src) {
                $dst = Join-Path $exportDir "workspace\skills"
                Copy-Item $src $dst -Recurse -Force
                Write-Ok "Skills copied"
            } else { Write-Warn "No skills directory found" }
        }
        "replicate" {
            # Config
            $cfg = Join-Path $OpenClawDir "openclaw.json"
            if (Test-Path $cfg) { Copy-Item $cfg $exportDir; Write-Ok "openclaw.json" }

            # Skills
            $src = Join-Path $WorkspaceDir "skills"
            if (Test-Path $src) {
                $dst = Join-Path $exportDir "workspace\skills"
                New-Item -ItemType Directory -Path (Join-Path $exportDir "workspace") -Force | Out-Null
                Copy-Item $src $dst -Recurse -Force
                Write-Ok "Skills"
            }

            # Markdown docs
            foreach ($f in @("AGENTS.md","TOOLS.md","SOUL.md","USER.md","IDENTITY.md")) {
                $p = Join-Path $WorkspaceDir $f
                if (Test-Path $p) {
                    $wsDst = Join-Path $exportDir "workspace"
                    New-Item -ItemType Directory -Path $wsDst -Force | Out-Null
                    Copy-Item $p $wsDst
                    Write-Ok $f
                }
            }

            # Scripts
            $src = Join-Path $WorkspaceDir "scripts"
            if (Test-Path $src) {
                $dst = Join-Path $exportDir "workspace\scripts"
                New-Item -ItemType Directory -Path (Join-Path $exportDir "workspace") -Force | Out-Null
                Copy-Item $src $dst -Recurse -Force
                Write-Ok "Scripts"
            }
        }
        "full" {
            Copy-Item "$OpenClawDir\*" $exportDir -Recurse -Force
            $sessDir = Join-Path $exportDir "sessions"
            if (Test-Path $sessDir) { Remove-Item $sessDir -Recurse -Force }
            Write-Ok "Full export (excluding sessions)"
        }
    }

    # Manifest
    $manifest = @{
        version          = $Version
        mode             = $Mode
        timestamp        = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        source_os        = "windows"
        source_hostname  = $env:COMPUTERNAME
        openclaw_version = try { & openclaw --version 2>$null } catch { "unknown" }
        node_version     = try { & node -v 2>$null } catch { "unknown" }
    } | ConvertTo-Json -Depth 3
    $manifest | Out-File (Join-Path $exportDir "manifest.json") -Encoding utf8

    # Create tar.gz
    Write-Info "Creating archive..."
    tar -czf $Output -C $tmpDir "openclaw-export"
    if ($LASTEXITCODE -ne 0) { Exit-Fatal "Failed to create archive" }

    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    $size = (Get-Item $Output).Length / 1KB
    Write-Ok ("Export complete: $Output ({0:N0} KB)" -f $size)
}

# ── Import ────────────────────────────────────────────────────────
function Invoke-Import {
    if (-not $Archive) { Exit-Fatal "Usage: .\openclaw-migrate.ps1 import -Archive <file.tar.gz>" }
    if (-not (Test-Path $Archive)) { Exit-Fatal "File not found: $Archive" }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "openclaw-import-$Timestamp"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    Write-Info "Extracting archive..."
    tar -xzf $Archive -C $tmpDir
    if ($LASTEXITCODE -ne 0) { Exit-Fatal "Failed to extract archive" }

    $exportDir = Join-Path $tmpDir "openclaw-export"
    if (-not (Test-Path $exportDir)) { Exit-Fatal "Invalid archive: missing openclaw-export directory" }

    $manifestPath = Join-Path $exportDir "manifest.json"
    if (Test-Path $manifestPath) {
        Write-Info "Archive info:"
        Get-Content $manifestPath | Write-Host
        Write-Host
    }

    # Ensure openclaw installed
    if (-not (Test-OpenClaw)) {
        Write-Warn "OpenClaw not installed"
        $ans = Read-Host "Install OpenClaw now? [Y/n]"
        if ($ans -match "^[Nn]") { Exit-Fatal "Cannot import without OpenClaw" }
        Install-OpenClaw
    }

    # Backup
    if (Test-Path $OpenClawDir) {
        $backup = Join-Path $env:USERPROFILE "openclaw-backup-$Timestamp.tar.gz"
        Write-Info "Backing up existing config to $backup"
        try { tar -czf $backup -C $env:USERPROFILE ".openclaw"; Write-Ok "Backup created" }
        catch { Write-Warn "Backup failed, continuing" }
    }

    # Import
    New-Item -ItemType Directory -Path $OpenClawDir -Force | Out-Null
    Write-Info "Importing files..."

    $cfg = Join-Path $exportDir "openclaw.json"
    if (Test-Path $cfg) { Copy-Item $cfg $OpenClawDir; Write-Ok "openclaw.json" }

    $ws = Join-Path $exportDir "workspace"
    if (Test-Path $ws) {
        New-Item -ItemType Directory -Path $WorkspaceDir -Force | Out-Null
        Copy-Item "$ws\*" $WorkspaceDir -Recurse -Force
        Write-Ok "Workspace files"
    }

    foreach ($d in @("extensions","identity","memory","credentials")) {
        $src = Join-Path $exportDir $d
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $OpenClawDir $d) -Recurse -Force
            Write-Ok "$d/"
        }
    }

    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Info "Running openclaw doctor..."
    try { & openclaw doctor } catch { Write-Warn "openclaw doctor had issues" }

    Write-Ok "Import complete! 🎉"
}

# ── Main ──────────────────────────────────────────────────────────
function Show-Usage {
    Write-Host @"
OpenClaw Migration Tool v$Version (PowerShell)

Usage:
  .\openclaw-migrate.ps1 export -Mode replicate   Copy architecture
  .\openclaw-migrate.ps1 export -Mode full         Full migration
  .\openclaw-migrate.ps1 export -Mode skills       Skills only
  .\openclaw-migrate.ps1 export -Output <path>     Custom output
  .\openclaw-migrate.ps1 import -Archive <file>    Import from archive
"@
}

switch ($Action) {
    "export" { Invoke-Export }
    "import" { Invoke-Import }
    default  { Show-Usage }
}
