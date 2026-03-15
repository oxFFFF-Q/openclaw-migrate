#!/usr/bin/env bash
# openclaw-migrate.sh — OpenClaw Cross-Platform Migration Tool (macOS/Linux)
# Usage:
#   ./openclaw-migrate.sh export --mode=replicate|full|skills [--output=path]
#   ./openclaw-migrate.sh import <archive.tar.gz>

set -euo pipefail

VERSION="1.0.0"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
WORKSPACE_DIR="$OPENCLAW_DIR/workspace"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEFAULT_OUTPUT="$HOME/openclaw-export-$TIMESTAMP.tar.gz"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info()  { echo -e "${BLUE}ℹ${NC}  $*"; }
ok()    { echo -e "${GREEN}✔${NC}  $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
err()   { echo -e "${RED}✖${NC}  $*" >&2; }
die()   { err "$@"; exit 1; }

# ── System Detection ──────────────────────────────────────────────
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if [ -f /etc/debian_version ]; then echo "debian"
      elif [ -f /etc/redhat-release ]; then echo "redhat"
      else echo "linux"
      fi ;;
    *) echo "unknown" ;;
  esac
}

check_node() {
  if command -v node &>/dev/null; then
    ok "Node.js $(node -v) detected"
    return 0
  fi
  warn "Node.js not found"
  return 1
}

check_openclaw() {
  if command -v openclaw &>/dev/null; then
    ok "OpenClaw detected: $(openclaw --version 2>/dev/null || echo 'installed')"
    return 0
  fi
  return 1
}

install_openclaw() {
  info "Installing OpenClaw..."
  if ! check_node; then
    local os=$(detect_os)
    info "Installing Node.js first..."
    case "$os" in
      macos)   brew install node || die "Failed to install Node.js. Install manually." ;;
      debian)  sudo apt-get update && sudo apt-get install -y nodejs npm || die "Failed" ;;
      redhat)  sudo yum install -y nodejs npm || die "Failed" ;;
      *)       die "Cannot auto-install Node.js on this system. Install manually." ;;
    esac
  fi
  npm install -g openclaw || die "Failed to install OpenClaw"
  ok "OpenClaw installed"
}

# ── Export ────────────────────────────────────────────────────────
do_export() {
  local mode="replicate"
  local output="$DEFAULT_OUTPUT"

  for arg in "$@"; do
    case "$arg" in
      --mode=*)   mode="${arg#--mode=}" ;;
      --output=*) output="${arg#--output=}" ;;
    esac
  done

  [[ "$mode" =~ ^(replicate|full|skills)$ ]] || die "Invalid mode: $mode (use replicate|full|skills)"
  [ -d "$OPENCLAW_DIR" ] || die "OpenClaw directory not found: $OPENCLAW_DIR"

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" EXIT

  local exportdir="$tmpdir/openclaw-export"
  mkdir -p "$exportdir"

  info "Exporting in '$mode' mode..."

  case "$mode" in
    skills)
      if [ -d "$WORKSPACE_DIR/skills" ]; then
        mkdir -p "$exportdir/workspace"
        cp -R "$WORKSPACE_DIR/skills" "$exportdir/workspace/skills"
        ok "Skills copied"
      else
        warn "No skills directory found"
      fi
      ;;
    replicate)
      # Config
      [ -f "$OPENCLAW_DIR/openclaw.json" ] && cp "$OPENCLAW_DIR/openclaw.json" "$exportdir/" && ok "openclaw.json"
      # Workspace skills
      if [ -d "$WORKSPACE_DIR/skills" ]; then
        mkdir -p "$exportdir/workspace"
        cp -R "$WORKSPACE_DIR/skills" "$exportdir/workspace/skills"
        ok "Skills"
      fi
      # AGENTS.md, TOOLS.md, SOUL.md, USER.md, IDENTITY.md
      for f in AGENTS.md TOOLS.md SOUL.md USER.md IDENTITY.md; do
        [ -f "$WORKSPACE_DIR/$f" ] && {
          mkdir -p "$exportdir/workspace"
          cp "$WORKSPACE_DIR/$f" "$exportdir/workspace/$f"
          ok "$f"
        }
      done
      # Scripts
      if [ -d "$WORKSPACE_DIR/scripts" ]; then
        mkdir -p "$exportdir/workspace"
        cp -R "$WORKSPACE_DIR/scripts" "$exportdir/workspace/scripts"
        ok "Scripts"
      fi
      ;;
    full)
      cp -R "$OPENCLAW_DIR/." "$exportdir/"
      # Remove sessions (too large, ephemeral)
      rm -rf "$exportdir/sessions" 2>/dev/null
      ok "Full export (excluding sessions)"
      ;;
  esac

  # Generate manifest
  cat > "$exportdir/manifest.json" <<EOF
{
  "version": "$VERSION",
  "mode": "$mode",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source_os": "$(detect_os)",
  "source_hostname": "$(hostname)",
  "openclaw_version": "$(openclaw --version 2>/dev/null || echo 'unknown')",
  "node_version": "$(node -v 2>/dev/null || echo 'unknown')"
}
EOF

  # Create archive
  tar -czf "$output" -C "$tmpdir" "openclaw-export"
  local size
  size=$(du -h "$output" | cut -f1)
  ok "Export complete: $output ($size)"
}

# ── Import ────────────────────────────────────────────────────────
do_import() {
  local archive="${1:-}"
  [ -z "$archive" ] && die "Usage: $0 import <archive.tar.gz>"
  [ -f "$archive" ] && true || die "File not found: $archive"

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" EXIT

  info "Extracting archive..."
  tar -xzf "$archive" -C "$tmpdir" || die "Failed to extract archive"

  local exportdir="$tmpdir/openclaw-export"
  [ -d "$exportdir" ] || die "Invalid archive: missing openclaw-export directory"
  [ -f "$exportdir/manifest.json" ] || die "Invalid archive: missing manifest.json"

  # Show manifest
  info "Archive info:"
  cat "$exportdir/manifest.json" | python3 -m json.tool 2>/dev/null || cat "$exportdir/manifest.json"
  echo

  # Ensure openclaw is installed
  if ! check_openclaw; then
    warn "OpenClaw not installed on this system"
    read -rp "Install OpenClaw now? [Y/n] " ans
    [[ "$ans" =~ ^[Nn] ]] && die "Cannot import without OpenClaw" || install_openclaw
  fi

  # Backup existing config
  if [ -d "$OPENCLAW_DIR" ]; then
    local backup="$HOME/openclaw-backup-$TIMESTAMP.tar.gz"
    info "Backing up existing config to $backup"
    tar -czf "$backup" -C "$HOME" ".openclaw" 2>/dev/null && ok "Backup created" || warn "Backup failed, continuing anyway"
  fi

  # Import files
  mkdir -p "$OPENCLAW_DIR"
  info "Importing files..."

  # Copy everything from export, preserving structure
  if [ -f "$exportdir/openclaw.json" ]; then
    cp "$exportdir/openclaw.json" "$OPENCLAW_DIR/openclaw.json"
    ok "openclaw.json"
  fi
  if [ -d "$exportdir/workspace" ]; then
    mkdir -p "$WORKSPACE_DIR"
    cp -R "$exportdir/workspace/." "$WORKSPACE_DIR/"
    ok "Workspace files"
  fi
  # Full mode extras
  for d in extensions identity memory credentials; do
    if [ -d "$exportdir/$d" ]; then
      cp -R "$exportdir/$d" "$OPENCLAW_DIR/$d"
      ok "$d/"
    fi
  done

  # Run doctor
  info "Running openclaw doctor..."
  openclaw doctor 2>&1 || warn "openclaw doctor had issues (check above)"

  ok "Import complete! 🎉"
}

# ── Main ──────────────────────────────────────────────────────────
usage() {
  cat <<EOF
OpenClaw Migration Tool v$VERSION

Usage:
  $0 export --mode=replicate   Copy architecture (config + skills + docs)
  $0 export --mode=full        Full migration (everything)
  $0 export --mode=skills      Skills only
  $0 export --output=<path>    Custom output path
  $0 import <archive.tar.gz>   Import from archive

EOF
}

case "${1:-}" in
  export) shift; do_export "$@" ;;
  import) shift; do_import "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
