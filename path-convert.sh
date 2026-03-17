#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
# path-convert.sh — Cross-platform path conversion for OpenClaw backups
#
# Source this file to get the following functions:
#   get_source_home       — Read source home from MANIFEST.json
#   infer_source_home     — Infer source home from config (legacy archives)
#   convert_paths_in_file — Replace paths in a single text file
#   convert_paths_in_json — Replace paths in a JSON file (structure-aware)
#   convert_all_paths     — Batch convert all relevant files
# ══════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Logging helpers (no-op if already defined by caller) ─────────
type info  &>/dev/null || info()  { echo "[INFO]  $*"; }
type warn  &>/dev/null || warn()  { echo "[WARN]  $*"; }
type dryrun &>/dev/null || dryrun() { echo "[DRY]   $*"; }

# ── get_source_home ──────────────────────────────────────────────
# Read source home directory from MANIFEST.json (new-style archives).
# Args: $1 = path to MANIFEST.json
# Prints: source home path (e.g. /Users/eva) or empty string
get_source_home() {
  local manifest="${1:?usage: get_source_home <manifest.json>}"
  python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('home_dir', ''))
except Exception:
    print('')
" "$manifest" 2>/dev/null
}

# ── infer_source_home ────────────────────────────────────────────
# For legacy archives without home_dir in manifest, infer source
# home from path patterns inside openclaw.json.
# Args: $1 = path to openclaw.json (from backup)
# Prints: inferred home path or empty string
infer_source_home() {
  local config="${1:?usage: infer_source_home <openclaw.json>}"
  python3 -c "
import json, re, collections, sys

try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)

homes = []
def scan(obj):
    if isinstance(obj, str):
        m = re.match(r'(/(?:Users|home)/[^/]+)', obj)
        if m:
            homes.append(m.group(1))
    elif isinstance(obj, dict):
        for v in obj.values():
            scan(v)
    elif isinstance(obj, list):
        for v in obj:
            scan(v)

scan(d)
if homes:
    top, count = collections.Counter(homes).most_common(1)[0]
    # Only trust if we see it at least 3 times
    if count >= 3:
        print(top)
" "$config" 2>/dev/null
}

# ── convert_paths_in_file ────────────────────────────────────────
# Replace source_home → $HOME in a single text file.
# Args: $1 = file path, $2 = source home
# Returns: 0 if replaced, 1 if skipped
convert_paths_in_file() {
  local file="${1:?}" source_home="${2:?}"
  local target_home="$HOME"

  [ "$source_home" = "$target_home" ] && return 1
  [ ! -f "$file" ] && return 1

  # Skip binary files
  local mime
  mime=$(file -b --mime-type "$file" 2>/dev/null || echo "unknown")
  case "$mime" in
    text/*|application/json|application/javascript|application/x-shellscript) ;;
    *) return 1 ;;
  esac

  if grep -qF "$source_home" "$file" 2>/dev/null; then
    sed -i.pathbak "s|${source_home}|${target_home}|g" "$file"
    rm -f "${file}.pathbak"
    return 0
  fi
  return 1
}

# ── convert_paths_in_json ────────────────────────────────────────
# Structure-aware JSON path replacement (preserves formatting).
# Args: $1 = JSON file path, $2 = source home
convert_paths_in_json() {
  local file="${1:?}" source_home="${2:?}"
  local target_home="$HOME"

  [ "$source_home" = "$target_home" ] && return 0
  [ ! -f "$file" ] && return 1

  python3 -c "
import json, sys

def convert(obj, src, dst):
    if isinstance(obj, str):
        return obj.replace(src, dst)
    elif isinstance(obj, dict):
        return {k: convert(v, src, dst) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert(i, src, dst) for i in obj]
    return obj

src, dst, fpath = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(fpath) as f:
        data = json.load(f)
    data = convert(data, src, dst)
    with open(fpath, 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')
except Exception as e:
    print(f'Warning: JSON conversion failed for {fpath}: {e}', file=sys.stderr)
" "$source_home" "$target_home" "$file" 2>/dev/null
}

# ── convert_all_paths ────────────────────────────────────────────
# Batch convert all relevant files under OPENCLAW_HOME.
# Args: $1 = backup dir (unused, kept for API compat), $2 = source home
convert_all_paths() {
  local backup_dir="${1:-}"
  local source_home="${2:-}"
  local openclaw_home="${OPENCLAW_HOME:-$HOME/.openclaw}"
  local count=0

  if [ -z "$source_home" ]; then
    warn "No source home detected, skipping path conversion"
    return
  fi
  if [ "$source_home" = "$HOME" ]; then
    info "Same home directory ($HOME), no path conversion needed"
    return
  fi

  info "Converting paths: ${source_home} → ${HOME}"

  # 1. openclaw.json — JSON-aware replacement
  local config="${openclaw_home}/openclaw.json"
  if [ -f "$config" ]; then
    convert_paths_in_json "$config" "$source_home"
    info "  ✓ openclaw.json"
    ((count++)) || true
  fi

  # 2. Workspace text files (md, sh, json, yaml, js, ts, toml)
  if [ -d "${openclaw_home}/workspace" ]; then
    while IFS= read -r -d '' file; do
      if convert_paths_in_file "$file" "$source_home"; then
        ((count++)) || true
      fi
    done < <(find "${openclaw_home}/workspace" -type f \( \
      -name "*.md" -o -name "*.sh" -o -name "*.json" -o \
      -name "*.yaml" -o -name "*.yml" -o -name "*.toml" -o \
      -name "*.js" -o -name "*.ts" \) -print0 2>/dev/null)
  fi

  # 3. Cron job configs
  if [ -d "${openclaw_home}/cron" ]; then
    while IFS= read -r -d '' file; do
      if convert_paths_in_file "$file" "$source_home"; then
        ((count++)) || true
      fi
    done < <(find "${openclaw_home}/cron" -type f -name "*.json" -print0 2>/dev/null)
  fi

  # 4. Root-level scripts
  for f in "${openclaw_home}"/*.sh; do
    [ -f "$f" ] && convert_paths_in_file "$f" "$source_home" && { ((count++)) || true; }
  done

  # 5. Agent configs
  if [ -d "${openclaw_home}/agents" ]; then
    while IFS= read -r -d '' file; do
      if convert_paths_in_file "$file" "$source_home"; then
        ((count++)) || true
      fi
    done < <(find "${openclaw_home}/agents" -type f -name "*.json" -print0 2>/dev/null)
  fi

  info "Path conversion complete (${count} files updated)"
}
