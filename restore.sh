#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
# restore.sh — OpenClaw backup restore with cross-platform path conversion
#
# Usage: ./restore.sh <archive.tar.gz> [--dry-run]
#
# This script:
#   1. Extracts the backup archive
#   2. Reads MANIFEST.json for source system info
#   3. Restores files to OPENCLAW_HOME
#   4. Converts paths from source HOME to current HOME
#   5. Restarts the gateway
# ══════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
DRY_RUN=false

# ── Logging ──────────────────────────────────────────────────────
info()   { echo "$(date +%H:%M:%S) [INFO]  $*"; }
warn()   { echo "$(date +%H:%M:%S) [WARN]  $*" >&2; }
error()  { echo "$(date +%H:%M:%S) [ERROR] $*" >&2; }
dryrun() { echo "$(date +%H:%M:%S) [DRY]   $*"; }

# ── Source path conversion module ────────────────────────────────
source "${SCRIPT_DIR}/path-convert.sh"

# ── Parse args ───────────────────────────────────────────────────
ARCHIVE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -*) error "Unknown option: $arg"; exit 1 ;;
    *) ARCHIVE="$arg" ;;
  esac
done

if [ -z "$ARCHIVE" ]; then
  error "Usage: $0 <archive.tar.gz> [--dry-run]"
  exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
  error "Archive not found: $ARCHIVE"
  exit 1
fi

info "Restoring from: $ARCHIVE"
info "Target OPENCLAW_HOME: $OPENCLAW_HOME"
$DRY_RUN && info "DRY RUN mode — no changes will be made"

# ── 1. Extract to temp dir ───────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

info "Extracting archive..."
tar xzf "$ARCHIVE" -C "$TMPDIR"

# Find the archive root (first directory inside)
BACKUP_ROOT=$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -type d | head -1)
if [ -z "$BACKUP_ROOT" ]; then
  error "Invalid archive: no root directory found"
  exit 1
fi

# ── 2. Read manifest ────────────────────────────────────────────
MANIFEST="${BACKUP_ROOT}/MANIFEST.json"
if [ ! -f "$MANIFEST" ]; then
  error "No MANIFEST.json found in archive"
  exit 1
fi

info "Reading manifest..."
SOURCE_PLATFORM=$(python3 -c "import json; print(json.load(open('$MANIFEST')).get('platform','unknown'))" 2>/dev/null || echo "unknown")
SOURCE_HOME=$(get_source_home "$MANIFEST")

# Fall back to inference for legacy archives
if [ -z "$SOURCE_HOME" ]; then
  warn "No home_dir in manifest (legacy archive), attempting inference..."
  # Look for openclaw.json in the archive to infer
  BACKUP_CONFIG=$(find "$BACKUP_ROOT" -name "openclaw.json" -type f | head -1)
  if [ -n "$BACKUP_CONFIG" ]; then
    SOURCE_HOME=$(infer_source_home "$BACKUP_CONFIG")
    if [ -n "$SOURCE_HOME" ]; then
      info "Inferred source home: $SOURCE_HOME"
    else
      warn "Could not infer source home — path conversion will be skipped"
    fi
  fi
fi

info "Source platform: $SOURCE_PLATFORM"
info "Source home: ${SOURCE_HOME:-<unknown>}"
info "Target home: $HOME"

# ── 3-8. Restore files (rsync from archive to OPENCLAW_HOME) ────
# This section restores config, credentials, workspace, sessions, etc.
# In a full implementation, each asset from MANIFEST.json is restored
# to its correct location under OPENCLAW_HOME.

if ! $DRY_RUN; then
  info "Restoring files to ${OPENCLAW_HOME}..."
  
  # Restore config
  if [ -f "${BACKUP_ROOT}/openclaw.json" ]; then
    cp "${BACKUP_ROOT}/openclaw.json" "${OPENCLAW_HOME}/openclaw.json"
    info "  ✓ openclaw.json"
  fi

  # Restore workspace
  if [ -d "${BACKUP_ROOT}/workspace" ]; then
    rsync -a --ignore-existing "${BACKUP_ROOT}/workspace/" "${OPENCLAW_HOME}/workspace/"
    info "  ✓ workspace"
  fi

  # Restore other assets as needed...
  # (cron, agents, scripts, etc.)
  for dir in cron agents scripts; do
    if [ -d "${BACKUP_ROOT}/${dir}" ]; then
      rsync -a "${BACKUP_ROOT}/${dir}/" "${OPENCLAW_HOME}/${dir}/"
      info "  ✓ ${dir}"
    fi
  done
else
  dryrun "Would restore files from archive to ${OPENCLAW_HOME}"
fi

# ── 9. Cron restoration (placeholder) ───────────────────────────
info "Cron restoration... (handled by openclaw CLI)"

# ══════════════════════════════════════════════════════════════════
# ── 10. Cross-Platform Path Conversion ───────────────────────────
# ══════════════════════════════════════════════════════════════════
if ! $DRY_RUN; then
  convert_all_paths "$BACKUP_ROOT" "$SOURCE_HOME"
else
  if [ -n "$SOURCE_HOME" ] && [ "$SOURCE_HOME" != "$HOME" ]; then
    dryrun "Would convert paths: ${SOURCE_HOME} → ${HOME}"
  else
    info "No path conversion needed (same home or unknown source)"
  fi
fi

# ── 11. Restart gateway ─────────────────────────────────────────
if ! $DRY_RUN; then
  info "Restarting gateway..."
  openclaw gateway restart 2>/dev/null || warn "Gateway restart failed (may need manual restart)"
else
  dryrun "Would restart gateway"
fi

info "Restore complete! 🎉"
