#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
# backup.sh — Enhanced OpenClaw backup with home_dir in manifest
#
# Wraps `openclaw backup create` and patches MANIFEST.json to add
# home_dir and openclaw_home fields for cross-platform restore.
#
# Usage: ./backup.sh [--dry-run] [--output <path>] [--verify]
# ══════════════════════════════════════════════════════════════════

set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

info()  { echo "$(date +%H:%M:%S) [INFO]  $*"; }
warn()  { echo "$(date +%H:%M:%S) [WARN]  $*" >&2; }

# ── Pass through to openclaw backup create ───────────────────────
ARGS=("$@")
DRY_RUN=false
OUTPUT=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --output)  ;; # handled by openclaw
  esac
done

# Run the built-in backup
info "Running openclaw backup create..."
RESULT=$(openclaw backup create --json "${ARGS[@]}" 2>&1) || {
  echo "$RESULT" >&2
  exit 1
}

echo "$RESULT"

# Extract archive path from JSON output
ARCHIVE=$(echo "$RESULT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('archivePath', ''))
except:
    pass
" 2>/dev/null)

if [ -z "$ARCHIVE" ] || $DRY_RUN; then
  info "Dry run or no archive path — skipping manifest patch"
  exit 0
fi

if [ ! -f "$ARCHIVE" ]; then
  warn "Archive not found at $ARCHIVE — skipping manifest patch"
  exit 0
fi

# ── Patch MANIFEST.json inside the archive ───────────────────────
info "Patching MANIFEST.json with home_dir..."

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Extract
tar xzf "$ARCHIVE" -C "$TMPDIR"

# Find and patch manifest
MANIFEST=$(find "$TMPDIR" -name "MANIFEST.json" -type f | head -1)
if [ -n "$MANIFEST" ]; then
  python3 -c "
import json, os, sys

manifest_path = sys.argv[1]
with open(manifest_path) as f:
    data = json.load(f)

data['home_dir'] = os.path.expanduser('~')
data['openclaw_home'] = os.environ.get('OPENCLAW_HOME', os.path.expanduser('~/.openclaw'))

with open(manifest_path, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f'Patched: home_dir={data[\"home_dir\"]}, openclaw_home={data[\"openclaw_home\"]}')
" "$MANIFEST"

  # Re-create archive
  ARCHIVE_DIR=$(dirname "$ARCHIVE")
  ARCHIVE_NAME=$(basename "$ARCHIVE")
  (cd "$TMPDIR" && tar czf "${ARCHIVE_DIR}/${ARCHIVE_NAME}" *)
  info "Archive patched successfully: $ARCHIVE"
else
  warn "No MANIFEST.json found in archive"
fi
