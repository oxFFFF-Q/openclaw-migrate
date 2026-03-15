#!/usr/bin/env bash
#
# OpenClaw Migration Tool
# Cross-platform configuration migration for OpenClaw AI Assistant
#
# Repository: https://github.com/oxFFFF-Q/openclaw-migrate
# License: MIT
#
# Usage:
#   ./openclaw-migrate.sh export --mode=replicate|full|skills [--output=path]
#   ./openclaw-migrate.sh import <archive.tar.gz>
#   ./openclaw-migrate.sh doctor
#   ./openclaw-migrate.sh version
#

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────

readonly VERSION="1.1.0"
readonly SCRIPT_NAME="openclaw-migrate"
readonly REPO_URL="https://github.com/oxFFFF-Q/openclaw-migrate"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/oxFFFF-Q/openclaw-migrate/main"

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
WORKSPACE_DIR="$OPENCLAW_DIR/workspace"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEFAULT_OUTPUT="$HOME/openclaw-export-$TIMESTAMP.tar.gz"
LOG_FILE="/tmp/openclaw-migrate-$TIMESTAMP.log"

# ── Colors & Output ────────────────────────────────────────────────────────

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Logging
log()  { echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"; }
info() { echo -e "${BLUE}ℹ${NC}  $*"; log "[INFO] $*"; }
ok()   { echo -e "${GREEN}✔${NC}  $*"; log "[OK] $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; log "[WARN] $*"; }
err()  { echo -e "${RED}✖${NC}  $*" >&2; log "[ERROR] $*"; }
die()  { err "$@"; exit 1; }

# Progress indicator
show_spinner() {
  local pid=$1
  local msg=$2
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 $pid 2>/dev/null; do
    i=$(( (i+1) % ${#spin} ))
    printf "\r${CYAN}${spin:$i:1}${NC}  %s" "$msg"
    sleep 0.1
  done
  printf "\r"
}

# Banner
show_banner() {
  echo -e "${MAGENTA}"
  echo "  ____                          _____ _       _ _     _ _ "
  echo " / __ \                        / ____| |     | | |   (_) |"
  echo "| |  | |_   _____ _ __  ___   | |    | |_   _| | |___ _| |"
  echo "| |  | \ \ / / _ \ '_ \/ __|  | |    | | | | | | / __| | |"
  echo "| |__| |\ V /  __/ | | \__ \  | |____| | |_| | | \__ \ | |"
  echo " \____/  \_/ \___|_| |_|___/   \_____|_|\__,_|_|_|___/_|_|"
  echo -e "${NC}"
  echo -e "  ${BOLD}Cross-Platform Migration Tool${NC} v$VERSION"
  echo "  $REPO_URL"
  echo
}

# ── System Detection ───────────────────────────────────────────────────────

detect_os() {
  case "$(uname -s)" in
    Darwin)
      if [[ "$(uname -m)" == "arm64" ]]; then
        echo "macos-arm64"
      else
        echo "macos-x64"
      fi
      ;;
    Linux)
      if [ -f /etc/debian_version ]; then
        echo "debian"
      elif [ -f /etc/redhat-release ]; then
        echo "redhat"
      elif [ -f /etc/arch-release ]; then
        echo "arch"
      elif [ -f /etc/alpine-release ]; then
        echo "alpine"
      else
        echo "linux"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "windows"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

detect_package_manager() {
  case "$(detect_os)" in
    macos-*)    echo "brew" ;;
    debian)     echo "apt" ;;
    redhat)     echo "yum" ;;
    arch)       echo "pacman" ;;
    alpine)     echo "apk" ;;
    windows)    echo "winget" ;;
    *)          echo "unknown" ;;
  esac
}

# ── Dependency Management ──────────────────────────────────────────────────

check_node() {
  if command -v node &>/dev/null; then
    local version=$(node -v 2>/dev/null)
    # Check minimum version (Node 18+)
    local major=$(echo "$version" | sed 's/v//;s/\..*//')
    if [ "$major" -ge 18 ]; then
      ok "Node.js $version detected"
      return 0
    else
      warn "Node.js $version detected, but version 18+ is recommended"
      return 1
    fi
  fi
  warn "Node.js not found"
  return 1
}

check_npm() {
  if command -v npm &>/dev/null; then
    ok "npm $(npm --version) detected"
    return 0
  fi
  warn "npm not found"
  return 1
}

check_openclaw() {
  if command -v openclaw &>/dev/null; then
    local version=$(openclaw --version 2>/dev/null || echo 'installed')
    ok "OpenClaw detected: $version"
    return 0
  fi
  
  # Check if installed but not in PATH
  if [ -f "$OPENCLAW_DIR/bin/openclaw" ]; then
    warn "OpenClaw found at $OPENCLAW_DIR/bin/openclaw but not in PATH"
    return 0
  fi
  
  warn "OpenClaw not found"
  return 1
}

check_tar() {
  if command -v tar &>/dev/null; then
    return 0
  fi
  die "tar is required but not installed"
}

check_jq() {
  if command -v jq &>/dev/null; then
    return 0
  fi
  # python3 can also parse JSON
  if command -v python3 &>/dev/null; then
    return 0
  fi
  warn "Neither jq nor python3 found, JSON output will be raw"
  return 1
}

# Install Node.js based on OS
install_node() {
  local os=$(detect_os)
  info "Installing Node.js..."
  
  case "$os" in
    macos-*)
      if command -v brew &>/dev/null; then
        brew install node || die "Failed to install Node.js via Homebrew"
      else
        die "Homebrew not found. Install from https://brew.sh or install Node.js manually"
      fi
      ;;
    debian)
      sudo apt-get update && sudo apt-get install -y nodejs npm \
        || die "Failed to install Node.js. Try: curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
      ;;
    redhat)
      sudo yum install -y nodejs npm \
        || die "Failed to install Node.js. Try: curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -"
      ;;
    arch)
      sudo pacman -S nodejs npm || die "Failed to install Node.js"
      ;;
    alpine)
      sudo apk add nodejs npm || die "Failed to install Node.js"
      ;;
    *)
      die "Cannot auto-install Node.js on this system ($os). Install manually from https://nodejs.org"
      ;;
  esac
  
  ok "Node.js installed: $(node -v)"
}

# Install OpenClaw
install_openclaw() {
  info "Installing OpenClaw..."
  
  # Ensure npm is available
  if ! command -v npm &>/dev/null; then
    die "npm is required to install OpenClaw"
  fi
  
  # Install globally
  npm install -g openclaw || {
    # Try with sudo if permission denied
    warn "Permission denied, trying with sudo..."
    sudo npm install -g openclaw || die "Failed to install OpenClaw"
  }
  
  ok "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'installed')"
}

# ── Export Functions ───────────────────────────────────────────────────────

do_export() {
  local mode="replicate"
  local output="$DEFAULT_OUTPUT"
  local dry_run=false
  local verbose=false
  
  for arg in "$@"; do
    case "$arg" in
      --mode=*)     mode="${arg#--mode=}" ;;
      --output=*)   output="${arg#--output=}" ;;
      --dry-run)    dry_run=true ;;
      --verbose|-v) verbose=true ;;
      --help)       
        cat <<EOF
Export OpenClaw configuration

Usage: $SCRIPT_NAME export [options]

Options:
  --mode=MODE     Export mode: replicate, full, skills (default: replicate)
  --output=PATH   Output file path (default: ~/openclaw-export-TIMESTAMP.tar.gz)
  --dry-run       Show what would be exported without creating archive
  --verbose, -v   Show detailed output
  --help          Show this help

Modes:
  replicate    Config + skills + docs (no memory/credentials) [recommended]
  full         Everything including memory and credentials
  skills       Skills directory only

Examples:
  $SCRIPT_NAME export
  $SCRIPT_NAME export --mode=full --output=/tmp/my-export.tar.gz
  $SCRIPT_NAME export --dry-run
EOF
        return 0
        ;;
    esac
  done
  
  # Validate mode
  case "$mode" in
    replicate|full|skills) ;;
    *) die "Invalid mode: $mode (use: replicate, full, or skills)" ;;
  esac
  
  # Check source exists
  [ -d "$OPENCLAW_DIR" ] || die "OpenClaw directory not found: $OPENCLAW_DIR"
  
  if $dry_run; then
    info "DRY RUN - No files will be created"
    echo
  fi
  
  info "Exporting in '$mode' mode..."
  
  local tmpdir
  tmpdir=$(mktemp -d)
  if ! $dry_run; then
    trap "rm -rf '$tmpdir'" EXIT
  fi
  
  local exportdir="$tmpdir/openclaw-export"
  mkdir -p "$exportdir"
  
  local file_count=0
  local total_size=0
  
  # Helper to copy with feedback
  copy_item() {
    local src="$1"
    local dest="$2"
    local name="$3"
    
    if [ -e "$src" ]; then
      mkdir -p "$(dirname "$dest")"
      if [ -d "$src" ]; then
        cp -R "$src" "$dest"
        local size=$(du -sh "$src" 2>/dev/null | cut -f1)
        $verbose && ok "$name/ ($size)"
      else
        cp "$src" "$dest"
        local size=$(du -sh "$src" 2>/dev/null | cut -f1)
        $verbose && ok "$name ($size)"
      fi
      file_count=$((file_count + 1))
      return 0
    fi
    $verbose && warn "$name not found, skipping"
    return 1
  }
  
  # Export based on mode
  case "$mode" in
    skills)
      info "Exporting skills only..."
      copy_item "$WORKSPACE_DIR/skills" "$exportdir/workspace/skills" "Skills"
      ;;
      
    replicate)
      info "Exporting configuration (replicate mode)..."
      
      # Core config
      copy_item "$OPENCLAW_DIR/openclaw.json" "$exportdir/openclaw.json" "openclaw.json"
      
      # Workspace files
      copy_item "$WORKSPACE_DIR/skills" "$exportdir/workspace/skills" "Skills"
      copy_item "$WORKSPACE_DIR/scripts" "$exportdir/workspace/scripts" "Scripts"
      
      # Documentation files
      for f in AGENTS.md TOOLS.md SOUL.md USER.md IDENTITY.md HEARTBEAT.md MEMORY.md; do
        copy_item "$WORKSPACE_DIR/$f" "$exportdir/workspace/$f" "$f"
      done
      
      # PLANS directory (project management)
      if [ -d "$WORKSPACE_DIR/PLANS" ]; then
        copy_item "$WORKSPACE_DIR/PLANS" "$exportdir/workspace/PLANS" "PLANS"
      fi
      ;;
      
    full)
      info "Exporting full configuration..."
      warn "This includes memory and credentials!"
      
      # Copy everything
      cp -R "$OPENCLAW_DIR/." "$exportdir/"
      
      # Remove large/ephemeral directories
      rm -rf "$exportdir/sessions" 2>/dev/null || true
      rm -rf "$exportdir/logs" 2>/dev/null || true
      rm -rf "$exportdir/tmp" 2>/dev/null || true
      
      ok "Full export (excluding sessions/logs/tmp)"
      file_count=$(find "$exportdir" -type f | wc -l | tr -d ' ')
      ;;
  esac
  
  # Generate manifest
  info "Generating manifest..."
  cat > "$exportdir/manifest.json" <<EOF
{
  "version": "$VERSION",
  "mode": "$mode",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source": {
    "os": "$(detect_os)",
    "hostname": "$(hostname)",
    "user": "${USER:-unknown}"
  },
  "versions": {
    "openclaw": "$(openclaw --version 2>/dev/null || echo 'not installed')",
    "node": "$(node -v 2>/dev/null || echo 'not installed')",
    "npm": "$(npm --version 2>/dev/null || echo 'not installed')"
  },
  "export": {
    "file_count": $file_count,
    "compression": "gzip"
  }
}
EOF
  
  if $dry_run; then
    echo
    info "Files that would be exported:"
    find "$exportdir" -type f 2>/dev/null | head -50
    local count=$(find "$exportdir" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo
    info "Total: $count files"
    echo
    info "Manifest preview:"
    cat "$exportdir/manifest.json"
    rm -rf "$tmpdir"
    return 0
  fi
  
  # Create archive
  info "Creating archive..."
  tar -czf "$output" -C "$tmpdir" "openclaw-export"
  
  local final_size=$(du -h "$output" | cut -f1)
  
  echo
  ok "Export complete!"
  echo
  echo -e "  ${BOLD}Output:${NC}     $output"
  echo -e "  ${BOLD}Size:${NC}       $final_size"
  echo -e "  ${BOLD}Files:${NC}      $file_count"
  echo -e "  ${BOLD}Mode:${NC}       $mode"
  echo
  echo -e "  ${CYAN}To import on another device:${NC}"
  echo -e "  ./openclaw-migrate.sh import $output"
  echo
}

# ── Import Functions ───────────────────────────────────────────────────────

do_import() {
  local archive="${1:-}"
  local force=false
  local no_backup=false
  
  for arg in "$@"; do
    case "$arg" in
      --force|-f)     force=true ;;
      --no-backup)    no_backup=true ;;
      --help)
        cat <<EOF
Import OpenClaw configuration from archive

Usage: $SCRIPT_NAME import <archive.tar.gz> [options]

Options:
  --force, -f      Skip confirmation prompts
  --no-backup      Don't backup existing configuration
  --help           Show this help

Examples:
  $SCRIPT_NAME import openclaw-export-20260315.tar.gz
  $SCRIPT_NAME import export.tar.gz --force
EOF
        return 0
        ;;
    esac
  done
  
  [ -z "$archive" ] && die "Usage: $SCRIPT_NAME import <archive.tar.gz>"
  [ -f "$archive" ] || die "File not found: $archive"
  
  # Validate archive
  if ! tar -tzf "$archive" &>/dev/null; then
    die "Invalid archive: not a valid gzip tar file"
  fi
  
  info "Extracting archive..."
  
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" EXIT
  
  tar -xzf "$archive" -C "$tmpdir" || die "Failed to extract archive"
  
  local exportdir="$tmpdir/openclaw-export"
  [ -d "$exportdir" ] || die "Invalid archive: missing openclaw-export directory"
  [ -f "$exportdir/manifest.json" ] || die "Invalid archive: missing manifest.json"
  
  # Read and display manifest
  echo
  info "Archive information:"
  echo -e "${CYAN}────────────────────────────────────────${NC}"
  
  if command -v python3 &>/dev/null; then
    python3 -m json.tool "$exportdir/manifest.json" 2>/dev/null || cat "$exportdir/manifest.json"
  elif command -v jq &>/dev/null; then
    jq . "$exportdir/manifest.json" 2>/dev/null || cat "$exportdir/manifest.json"
  else
    cat "$exportdir/manifest.json"
  fi
  
  echo -e "${CYAN}────────────────────────────────────────${NC}"
  echo
  
  # Check dependencies
  info "Checking dependencies..."
  
  if ! check_node; then
    if $force; then
      install_node
    else
      read -rp "Install Node.js now? [Y/n] " ans
      [[ "$ans" =~ ^[Nn] ]] && die "Cannot import without Node.js" || install_node
    fi
  fi
  
  if ! check_openclaw; then
    if $force; then
      install_openclaw
    else
      read -rp "Install OpenClaw now? [Y/n] " ans
      [[ "$ans" =~ ^[Nn] ]] && die "Cannot import without OpenClaw" || install_openclaw
    fi
  fi
  
  # Backup existing config
  if [ -d "$OPENCLAW_DIR" ] && ! $no_backup; then
    local backup="$HOME/openclaw-backup-$TIMESTAMP.tar.gz"
    info "Backing up existing configuration..."
    tar -czf "$backup" -C "$HOME" ".openclaw" 2>/dev/null && ok "Backup: $backup" || warn "Backup failed, continuing anyway"
  fi
  
  # Confirm import
  if ! $force; then
    echo
    read -rp "Proceed with import? [y/N] " ans
    [[ "$ans" =~ ^[Yy] ]] || die "Import cancelled"
  fi
  
  # Import files
  mkdir -p "$OPENCLAW_DIR"
  info "Importing files..."
  
  # Config
  if [ -f "$exportdir/openclaw.json" ]; then
    cp "$exportdir/openclaw.json" "$OPENCLAW_DIR/openclaw.json"
    ok "openclaw.json"
  fi
  
  # Workspace
  if [ -d "$exportdir/workspace" ]; then
    mkdir -p "$WORKSPACE_DIR"
    cp -R "$exportdir/workspace/." "$WORKSPACE_DIR/"
    ok "Workspace files"
  fi
  
  # Additional directories (from full export)
  for d in extensions identity memory credentials; do
    if [ -d "$exportdir/$d" ]; then
      cp -R "$exportdir/$d" "$OPENCLAW_DIR/$d"
      ok "$d/"
    fi
  done
  
  echo
  ok "Import complete! 🎉"
  echo
  echo -e "  ${CYAN}Next steps:${NC}"
  echo "  1. Run: openclaw doctor"
  echo "  2. Restart any running OpenClaw services"
  echo "  3. Verify configuration: cat ~/.openclaw/openclaw.json"
  echo
}

# ── Doctor Function ─────────────────────────────────────────────────────────

do_doctor() {
  show_banner
  
  info "Running diagnostics..."
  echo
  
  local issues=0
  
  # System info
  echo -e "${BOLD}System Information${NC}"
  echo -e "  OS:         $(detect_os)"
  echo -e "  Hostname:   $(hostname)"
  echo -e "  User:       ${USER:-unknown}"
  echo
  
  # Node.js
  echo -e "${BOLD}Node.js${NC}"
  if check_node; then
    echo -e "  Version:    $(node -v)"
    echo -e "  Path:       $(which node)"
  else
    echo -e "  ${RED}✖ Not installed${NC}"
    issues=$((issues + 1))
  fi
  echo
  
  # npm
  echo -e "${BOLD}npm${NC}"
  if check_npm; then
    echo -e "  Version:    $(npm --version)"
    echo -e "  Path:       $(which npm)"
  else
    echo -e "  ${RED}✖ Not installed${NC}"
    issues=$((issues + 1))
  fi
  echo
  
  # OpenClaw
  echo -e "${BOLD}OpenClaw${NC}"
  if check_openclaw; then
    echo -e "  Version:    $(openclaw --version 2>/dev/null || echo 'unknown')"
    echo -e "  Path:       $(which openclaw 2>/dev/null || echo 'not in PATH')"
  else
    echo -e "  ${RED}✖ Not installed${NC}"
    issues=$((issues + 1))
  fi
  echo
  
  # OpenClaw directory
  echo -e "${BOLD}Configuration${NC}"
  if [ -d "$OPENCLAW_DIR" ]; then
    echo -e "  Directory:  $OPENCLAW_DIR ${GREEN}✓${NC}"
    
    if [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
      echo -e "  Config:     openclaw.json ${GREEN}✓${NC}"
    else
      echo -e "  Config:     ${RED}✖ Missing openclaw.json${NC}"
      issues=$((issues + 1))
    fi
    
    if [ -d "$WORKSPACE_DIR" ]; then
      echo -e "  Workspace:  ${GREEN}✓${NC}"
      
      # Count skills
      if [ -d "$WORKSPACE_DIR/skills" ]; then
        local skill_count=$(find "$WORKSPACE_DIR/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        echo -e "  Skills:     $skill_count installed"
      fi
    else
      echo -e "  Workspace:  ${YELLOW}⚠ Not found${NC}"
    fi
  else
    echo -e "  Directory:  ${RED}✖ $OPENCLAW_DIR not found${NC}"
    issues=$((issues + 1))
  fi
  echo
  
  # Summary
  echo -e "${BOLD}Summary${NC}"
  if [ $issues -eq 0 ]; then
    echo -e "  ${GREEN}All checks passed! ✓${NC}"
  else
    echo -e "  ${RED}Found $issues issue(s)${NC}"
    echo
    echo -e "  ${CYAN}Suggested fixes:${NC}"
    [ ! -d "$OPENCLAW_DIR" ] && echo "  • Install OpenClaw: npm install -g openclaw"
    ! check_node && echo "  • Install Node.js: https://nodejs.org"
  fi
  echo
}

# ── Version & Self-Update ──────────────────────────────────────────────────

do_version() {
  echo "$SCRIPT_NAME v$VERSION"
  echo "Repository: $REPO_URL"
}

do_self_update() {
  info "Checking for updates..."
  
  local latest_version=$(curl -fsSL "$REPO_RAW_URL/VERSION" 2>/dev/null || echo "")
  
  if [ -z "$latest_version" ]; then
    warn "Could not check for updates"
    return 1
  fi
  
  if [ "$VERSION" = "$latest_version" ]; then
    ok "Already up to date (v$VERSION)"
    return 0
  fi
  
  info "New version available: v$latest_version (current: v$VERSION)"
  
  local script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  
  read -rp "Update now? [Y/n] " ans
  [[ "$ans" =~ ^[Nn] ]] && return 0
  
  # Download new version
  local tmp_script=$(mktemp)
  curl -fsSL "$REPO_RAW_URL/openclaw-migrate.sh" -o "$tmp_script" || die "Failed to download update"
  
  # Replace
  mv "$tmp_script" "$script_path"
  chmod +x "$script_path"
  
  ok "Updated to v$latest_version"
}

# ── Main Entry Point ───────────────────────────────────────────────────────

usage() {
  show_banner
  cat <<EOF
${BOLD}Usage:${NC}
  $SCRIPT_NAME <command> [options]

${BOLD}Commands:${NC}
  export        Export OpenClaw configuration
  import        Import configuration from archive
  doctor        Run system diagnostics
  version       Show version information
  update        Update to latest version
  help          Show this help message

${BOLD}Export Options:${NC}
  --mode=MODE       Mode: replicate (default), full, skills
  --output=PATH     Custom output path
  --dry-run         Preview without creating files
  --verbose, -v     Show detailed output

${BOLD}Import Options:${NC}
  --force, -f       Skip confirmation prompts
  --no-backup       Don't backup existing config

${BOLD}Examples:${NC}
  # Export configuration
  $SCRIPT_NAME export
  $SCRIPT_NAME export --mode=full --output=/tmp/backup.tar.gz

  # Import on new machine
  $SCRIPT_NAME import openclaw-export-*.tar.gz

  # Check system health
  $SCRIPT_NAME doctor

${BOLD}Repository:${NC} $REPO_URL
${BOLD}License:${NC} MIT

EOF
}

# Parse command
case "${1:-}" in
  export)
    shift
    do_export "$@"
    ;;
  import)
    shift
    do_import "$@"
    ;;
  doctor|--doctor|-d)
    do_doctor
    ;;
  version|--version|-v)
    do_version
    ;;
  update|--update|-u)
    do_self_update
    ;;
  help|--help|-h)
    usage
    ;;
  "")
    usage
    exit 1
    ;;
  *)
    err "Unknown command: $1"
    echo
    usage
    exit 1
    ;;
esac
