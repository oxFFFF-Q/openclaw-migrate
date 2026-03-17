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

readonly VERSION="1.3.0"
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

# Calculate size of items to be exported
calculate_export_size() {
  local total_size=0
  
  for item in "$@"; do
    if [ -e "$item" ]; then
      local size=$(du -sb "$item" 2>/dev/null | cut -f1)
      total_size=$((total_size + size))
    fi
  done
  
  # Convert to human readable
  if [ $total_size -gt 1073741824 ]; then
    echo "$(echo "scale=1; $total_size / 1073741824" | bc)GB"
  elif [ $total_size -gt 1048576 ]; then
    echo "$(echo "scale=1; $total_size / 1048576" | bc)MB"
  elif [ $total_size -gt 1024 ]; then
    echo "$(echo "scale=1; $total_size / 1024" | bc)KB"
  else
    echo "${total_size}B"
  fi
}

# Interactive export mode
do_export_interactive() {
  local output="$DEFAULT_OUTPUT"
  local verbose=false
  
  # Parse common args
  for arg in "$@"; do
    case "$arg" in
      --output=*) output="${arg#--output=}" ;;
      --verbose|-v) verbose=true ;;
    esac
  done
  
  echo
  echo -e "${MAGENTA}📦 ${BOLD}OpenClaw 配置导出向导${NC}"
  echo
  
  # Preset options with descriptions
  local options=(
    "🚀 快速 - 核心配置 + 自建技能 (约 2MB)"
    "📋 标准 - 快速 + 扩展插件 + 多 Agent (约 5MB)"
    "🔐 完整 - 全部内容含记忆凭证 (约 50MB)"
    "⚙️  自定义 - 手动选择每一项"
  )
  
  echo -e "${CYAN}?${NC} ${BOLD}选择导出预设:${NC}"
  echo
  
  # Use select for interactive menu
  PS3="${CYAN}❯ ${NC}"
  select choice in "${options[@]}"; do
    case "$REPLY" in
      1) # Quick
        do_export --mode=replicate --output="$output" ${verbose:+"--verbose"}
        return $?
        ;;
      2) # Standard
        do_export --mode=standard --output="$output" ${verbose:+"--verbose"}
        return $?
        ;;
      3) # Full
        do_export --mode=full --output="$output" ${verbose:+"--verbose"}
        return $?
        ;;
      4) # Custom
        do_export_custom "$output" "$verbose"
        return $?
        ;;
      *) 
        echo -e "${RED}无效选择，请输入 1-4${NC}"
        ;;
    esac
  done
}

# Custom export with checkboxes
do_export_custom() {
  local output="$1"
  local verbose="$2"
  
  echo
  echo -e "${MAGENTA}⚙️  ${BOLD}自定义导出选项${NC}"
  echo
  echo -e "${CYAN}?${NC} ${BOLD}选择要导出的项目 (输入 y/n，多选用空格分隔):${NC}"
  echo
  
  # Define export items with default states
  local items=(
    "core:核心配置 (openclaw.json):y"
    "skills:自建技能 (workspace/skills):y"
    "clawhub:ClawHub 技能 (~/.openclaw/skills):n"
    "extensions:扩展插件 (~/.openclaw/extensions):n"
    "agents:多 Agent 配置 (~/.openclaw/agents + workspace-*):n"
    "memory:记忆文件 (memory/):n"
    "credentials:凭证和密钥 (credentials):n"
  )
  
  local item_names=()
  local item_paths=()
  
  # Show current selection state and get user input
  for item in "${items[@]}"; do
    local id="${item%%:*}"
    local desc="${item#*:}"
    local name="${desc%%:*}"
    local default="${desc##*:}"
    
    item_names+=("$name")
    
    # Determine path based on id
    case "$id" in
      core)
        item_paths+=("$OPENCLAW_DIR/openclaw.json")
        ;;
      skills)
        item_paths+=("$WORKSPACE_DIR/skills")
        ;;
      clawhub)
        item_paths+=("$OPENCLAW_DIR/skills")
        ;;
      extensions)
        item_paths+=("$OPENCLAW_DIR/extensions")
        ;;
      agents)
        item_paths+=("$OPENCLAW_DIR/agents")
        ;;
      memory)
        item_paths+=("$WORKSPACE_DIR/memory")
        ;;
      credentials)
        item_paths+=("$OPENCLAW_DIR/credentials")
        ;;
    esac
    
    local current_state="$default"
    local checkbox="[ ]"
    if [ "$default" = "y" ]; then
      checkbox="[x]"
    fi
    
    echo -e "  $checkbox $name"
  done
  
  echo
  echo -e "${CYAN}提示:${NC} 默认选中的项目已标记 [x]"
  echo -e "${CYAN}输入格式:${NC} 例如: y n y y n"
  echo
  
  # Get user input
  printf "${CYAN}❯ ${NC}"
  read -ra answers
  
  # Process answers
  local selected=()
  local index=0
  for item in "${items[@]}"; do
    local id="${item%%:*}"
    local desc="${item#*:}"
    local name="${desc%%:*}"
    
    local answer="n"
    if [ -n "${answers[$index]:-}" ]; then
      answer="${answers[$index]}"
    fi
    
    if [[ "$answer" =~ ^[Yy] ]]; then
      selected+=("$id")
    fi
    
    index=$((index + 1))
  done
  
  # Validate selection
  if [ ${#selected[@]} -eq 0 ]; then
    warn "未选择任何项目，取消导出"
    return 1
  fi
  
  # Show preview
  echo
  echo -e "${CYAN}────────────────────────────────────────${NC}"
  echo -e "${BOLD}将导出以下内容:${NC}"
  echo
  
  local preview_items=()
  for id in "${selected[@]}"; do
    case "$id" in
      core) echo "  ✓ 核心配置 (openclaw.json)"; preview_items+=("$OPENCLAW_DIR/openclaw.json") ;;
      skills) echo "  ✓ 自建技能 (workspace/skills)"; preview_items+=("$WORKSPACE_DIR/skills") ;;
      clawhub) echo "  ✓ ClawHub 技能"; preview_items+=("$OPENCLAW_DIR/skills") ;;
      extensions) echo "  ✓ 扩展插件"; preview_items+=("$OPENCLAW_DIR/extensions") ;;
      agents) echo "  ✓ 多 Agent 配置"; preview_items+=("$OPENCLAW_DIR/agents") ;;
      memory) echo "  ✓ 记忆文件"; preview_items+=("$WORKSPACE_DIR/memory") ;;
      credentials) echo "  ✓ 凭证和密钥"; preview_items+=("$OPENCLAW_DIR/credentials") ;;
    esac
  done
  
  # Calculate size
  local size_estimate=$(calculate_export_size "${preview_items[@]}")
  echo
  echo -e "${CYAN}预估大小:${NC} $size_estimate"
  echo -e "${CYAN}────────────────────────────────────────${NC}"
  echo
  
  # Confirm
  read -rp "确认导出? [Y/n]: " confirm
  if [[ "$confirm" =~ ^[Nn] ]]; then
    warn "取消导出"
    return 1
  fi
  
  # Perform custom export
  do_export_custom_files "$output" "${selected[@]}"
}

# Execute custom export with selected items
do_export_custom_files() {
  local output="$1"
  shift
  local selected=("$@")
  
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" EXIT
  
  local exportdir="$tmpdir/openclaw-export"
  mkdir -p "$exportdir"
  
  local file_count=0
  
  # Helper
  copy_item_custom() {
    local src="$1"
    local dest="$2"
    
    if [ -e "$src" ]; then
      mkdir -p "$(dirname "$dest")"
      if [ -d "$src" ]; then
        cp -R "$src" "$dest" 2>/dev/null || true
      else
        cp "$src" "$dest" 2>/dev/null || true
      fi
      return 0
    fi
    return 1
  }
  
  for id in "${selected[@]}"; do
    case "$id" in
      core)
        copy_item_custom "$OPENCLAW_DIR/openclaw.json" "$exportdir/openclaw.json"
        file_count=$((file_count + 1))
        ;;
      skills)
        if [ -d "$WORKSPACE_DIR/skills" ]; then
          copy_item_custom "$WORKSPACE_DIR/skills" "$exportdir/workspace/skills"
          file_count=$(find "$WORKSPACE_DIR/skills" -type f 2>/dev/null | wc -l | tr -d ' ')
        fi
        ;;
      clawhub)
        if [ -d "$OPENCLAW_DIR/skills" ]; then
          copy_item_custom "$OPENCLAW_DIR/skills" "$exportdir/skills"
        fi
        ;;
      extensions)
        if [ -d "$OPENCLAW_DIR/extensions" ]; then
          copy_item_custom "$OPENCLAW_DIR/extensions" "$exportdir/extensions"
        fi
        ;;
      agents)
        if [ -d "$OPENCLAW_DIR/agents" ]; then
          copy_item_custom "$OPENCLAW_DIR/agents" "$exportdir/agents"
        fi
        # Also export workspace-* directories
        if ls "$WORKSPACE_DIR"/workspace-* &>/dev/null; then
          for workspace_dir in "$WORKSPACE_DIR"/workspace-*; do
            if [ -d "$workspace_dir" ]; then
              local dir_name=$(basename "$workspace_dir")
              copy_item_custom "$workspace_dir" "$exportdir/workspace/$dir_name"
            fi
          done
        fi
        ;;
      memory)
        if [ -d "$WORKSPACE_DIR/memory" ]; then
          copy_item_custom "$WORKSPACE_DIR/memory" "$exportdir/workspace/memory"
        fi
        ;;
      credentials)
        if [ -d "$OPENCLAW_DIR/credentials" ]; then
          copy_item_custom "$OPENCLAW_DIR/credentials" "$exportdir/credentials"
        fi
        ;;
    esac
  done
  
  # Also include basic workspace files for core/skills
  if [[ " ${selected[*]} " =~ " core " ]] || [[ " ${selected[*]} " =~ " skills " ]]; then
    mkdir -p "$exportdir/workspace"
    for f in AGENTS.md TOOLS.md SOUL.md USER.md IDENTITY.md HEARTBEAT.md; do
      if [ -f "$WORKSPACE_DIR/$f" ]; then
        copy_item_custom "$WORKSPACE_DIR/$f" "$exportdir/workspace/$f"
      fi
    done
  fi
  
  # Generate manifest
  cat > "$exportdir/manifest.json" <<EOF
{
  "version": "$VERSION",
  "mode": "custom",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "custom_items": $(printf '%s\n' "${selected[@]}" | jq -R . | jq -s . 2>/dev/null || echo '["custom"]'),
  "source": {
    "os": "$(detect_os)",
    "hostname": "$(hostname)",
    "user": "${USER:-unknown}"
  }
}
EOF
  
  # Create archive
  tar -czf "$output" -C "$tmpdir" "openclaw-export"
  
  local final_size=$(du -h "$output" | cut -f1)
  
  echo
  ok "导出完成!"
  echo
  echo -e "  ${BOLD}输出:${NC}     $output"
  echo -e "  ${BOLD}大小:${NC}       $final_size"
  echo -e "  ${BOLD}项目:${NC}      ${selected[*]}"
  echo
}

# ── Export Functions ───────────────────────────────────────────────────────

do_export() {
  local mode=""
  local output="$DEFAULT_OUTPUT"
  local dry_run=false
  local verbose=false
  local interactive=false
  
  for arg in "$@"; do
    case "$arg" in
      --mode=*)     mode="${arg#--mode=}" ;;
      --output=*)   output="${arg#--output=}" ;;
      --dry-run)    dry_run=true ;;
      --verbose|-v) verbose=true ;;
      --interactive|-i) interactive=true ;;
      --help)       
        cat <<EOF
Export OpenClaw configuration

Usage: $SCRIPT_NAME export [options]

Options:
  --mode=MODE      Export mode: replicate, standard, full, skills (default: interactive)
  --output=PATH    Output file path (default: ~/openclaw-export-TIMESTAMP.tar.gz)
  --dry-run        Show what would be exported without creating archive
  --verbose, -v    Show detailed output
  --interactive, -i  Force interactive mode
  --help           Show this help

Modes:
  replicate    Config + skills + docs (no memory/credentials) [recommended]
  standard     replicate + extensions + agents (recommended for full setup)
  full         Everything including memory and credentials
  skills       Skills directory only

Examples:
  $SCRIPT_NAME export
  $SCRIPT_NAME export -i
  $SCRIPT_NAME export --mode=full --output=/tmp/my-export.tar.gz
  $SCRIPT_NAME export --dry-run
EOF
        return 0
        ;;
    esac
  done
  
  # Enter interactive mode if:
  # 1. -i/--interactive flag is set
  # 2. No --mode parameter is provided AND stdin is a terminal
  if $interactive; then
    do_export_interactive "$@"
    return $?
  fi
  
  # If no mode specified and not interactive, default to replicate
  if [ -z "$mode" ]; then
    if [ -t 0 ]; then
      # Terminal available, enter interactive mode
      do_export_interactive "$@"
      return $?
    else
      # Non-interactive, default to replicate
      mode="replicate"
    fi
  fi
  
  # Validate mode
  case "$mode" in
    replicate|standard|full|skills) ;;
    *) die "Invalid mode: $mode (use: replicate, standard, full, or skills)" ;;
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
      
    standard)
      info "Exporting configuration (standard mode)..."
      
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
      
      # Extensions
      if [ -d "$OPENCLAW_DIR/extensions" ]; then
        copy_item "$OPENCLAW_DIR/extensions" "$exportdir/extensions" "Extensions"
      fi
      
      # Agents
      if [ -d "$OPENCLAW_DIR/agents" ]; then
        copy_item "$OPENCLAW_DIR/agents" "$exportdir/agents" "Agents"
      fi
      
      # Workspace-* directories
      if ls "$WORKSPACE_DIR"/workspace-* &>/dev/null; then
        for workspace_dir in "$WORKSPACE_DIR"/workspace-*; do
          if [ -d "$workspace_dir" ]; then
            local dir_name=$(basename "$workspace_dir")
            copy_item "$workspace_dir" "$exportdir/workspace/$dir_name" "Workspace-$dir_name"
          fi
        done
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

# Parse manifest and display interactive summary
display_import_summary() {
  local manifest="$1"
  local export_dir="$2"
  
  # Extract values with fallback
  local source_os source_hostname source_time version
  source_os=$(python3 -c "import json; print(json.load(open('$manifest')).get('source', {}).get('os', 'Unknown'))" 2>/dev/null || echo "Unknown")
  source_hostname=$(python3 -c "import json; print(json.load(open('$manifest')).get('source', {}).get('hostname', 'Unknown'))" 2>/dev/null || echo "Unknown")
  source_time=$(python3 -c "import json; print(json.load(open('$manifest')).get('timestamp', '').replace('T', ' ').replace('Z', ''))" 2>/dev/null || echo "Unknown")
  version=$(python3 -c "import json; print(json.load(open('$manifest')).get('version', '1.0.0'))" 2>/dev/null || echo "1.0.0")
  
  # Check what's included
  local has_config=false
  local has_skills=false
  local has_extensions=false
  local has_agents=false
  local has_memory=false
  local has_credentials=false
  
  if [ -f "$export_dir/openclaw.json" ]; then
    has_config=true
  fi
  
  if [ -d "$export_dir/workspace/skills" ]; then
    has_skills=true
  fi
  
  if [ -d "$export_dir/extensions" ]; then
    has_extensions=true
  fi
  
  if [ -d "$export_dir/workspace/AGENTS.md" ] || [ -d "$export_dir/workspace/agents" ]; then
    has_agents=true
  fi
  
  if [ -d "$export_dir/memory" ]; then
    has_memory=true
  fi
  
  if [ -d "$export_dir/credentials" ] || [ -d "$export_dir/identity" ]; then
    has_credentials=true
  fi
  
  # Count skills
  local skill_count=0
  if [ -d "$export_dir/workspace/skills" ]; then
    skill_count=$(find "$export_dir/workspace/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  fi
  
  # Count extensions
  local extension_count=0
  if [ -d "$export_dir/extensions" ]; then
    extension_count=$(find "$export_dir/extensions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  fi
  
  # Get archive size
  local archive_size=$(du -h "$archive" | cut -f1)
  
  # Display summary
  echo
  echo -e "${BOLD}📦 归档内容摘要${NC}"
  echo
  printf "  ${BOLD}来源:${NC}     %s (%s)\n" "$source_hostname" "$source_os"
  printf "  ${BOLD}时间:${NC}     %s\n" "$source_time"
  printf "  ${BOLD}版本:${NC}     %s\n" "$version"
  echo
  echo -e "  ${BOLD}包含:${NC}"
  
  if $has_config; then
    echo -e "    ${GREEN}✓${NC} 核心配置"
  else
    echo -e "    ${RED}✗${NC} 核心配置"
  fi
  
  if $has_skills; then
    echo -e "    ${GREEN}✓${NC} 自建技能 (${skill_count}个)"
  else
    echo -e "    ${RED}✗${NC} 自建技能"
  fi
  
  if $has_extensions; then
    echo -e "    ${GREEN}✓${NC} 扩展插件 (${extension_count}个)"
  else
    echo -e "    ${RED}✗${NC} 扩展插件"
  fi
  
  if $has_agents; then
    echo -e "    ${GREEN}✓${NC} 多 Agent"
  else
    echo -e "    ${RED}✗${NC} 多 Agent"
  fi
  
  if $has_memory; then
    echo -e "    ${GREEN}✓${NC} 记忆"
  else
    echo -e "    ${RED}✗${NC} 记忆"
  fi
  
  if $has_credentials; then
    echo -e "    ${GREEN}✓${NC} 凭证"
  else
    echo -e "    ${RED}✗${NC} 凭证"
  fi
  
  echo
  printf "  ${BOLD}大小:${NC} %s\n" "$archive_size"
  echo
}

# Check if plugin exists
check_plugin_exists() {
  local plugin_name="$1"
  
  # Check if plugin is installed
  if openclaw plugins list 2>/dev/null | grep -q "$plugin_name"; then
    return 0
  fi
  return 1
}

# Install missing plugin
install_plugin() {
  local plugin_name="$1"
  
  info "Installing plugin: $plugin_name..."
  
  if openclaw plugins install "$plugin_name" 2>&1; then
    ok "Plugin installed: $plugin_name"
    return 0
  else
    warn "Failed to install plugin: $plugin_name"
    return 1
  fi
}

# Detect and install missing plugins from config
detect_missing_plugins() {
  local config_file="$1"
  local missing_plugins=()
  
  if [ ! -f "$config_file" ]; then
    return 0
  fi
  
  # Extract plugin names from config using grep
  local plugins=$(grep -oE '"openclaw-[a-z0-9-]+"' "$config_file" 2>/dev/null | sort -u | tr -d '"')
  
  if [ -z "$plugins" ]; then
    return 0
  fi
  
  for plugin in $plugins; do
    if ! check_plugin_exists "$plugin"; then
      missing_plugins+=("$plugin")
    fi
  done
  
  # Print missing plugins
  if [ ${#missing_plugins[@]} -gt 0 ]; then
    echo
    warn "检测到以下插件未安装:"
    for plugin in "${missing_plugins[@]}"; do
      # Get plugin description from name
      local desc=""
      case "$plugin" in
        openclaw-lark) desc="飞书" ;;
        *) desc="" ;;
      esac
      if [ -n "$desc" ]; then
        echo -e "  - $plugin ($desc)"
      else
        echo -e "  - $plugin"
      fi
    done
    return 0
  fi
  
  return 1
}

do_import() {
  local archive="${1:-}"
  local force=false
  local no_backup=false
  local install_deps=false
  local interactive=true
  
  for arg in "$@"; do
    case "$arg" in
      --force|-f)     force=true
                      interactive=false ;;
      --no-backup)    no_backup=true ;;
      --install-deps) install_deps=true ;;
      --help)
        cat <<EOF
Import OpenClaw configuration from archive

Usage: $SCRIPT_NAME import <archive.tar.gz> [options]

Options:
  --force, -f      Skip confirmation prompts
  --no-backup      Don't backup existing configuration
  --install-deps   Automatically install missing plugins
  --help           Show this help

Examples:
  $SCRIPT_NAME import openclaw-export-20260315.tar.gz
  $SCRIPT_NAME import export.tar.gz --force --install-deps
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
  
  # Display interactive summary
  display_import_summary "$exportdir/manifest.json" "$exportdir"
  
  # Interactive import choice
  if $interactive; then
    echo -e "${BOLD}? 是否导入?${NC}"
    echo "  ❯ 是，导入并安装缺失插件"
    echo "    是，仅导入配置"
    echo "    否，取消"
    echo
    
    local choice=""
    while [ -z "$choice" ]; do
      read -rp "> " choice
      case "$choice" in
        1|"是，导入并安装缺失插件"|"是")
          install_deps=true
          ;;
        2|"是，仅导入配置")
          install_deps=false
          ;;
        3|"否"|"否，取消"|"n"|"N")
          die "导入已取消"
          ;;
        *)
          echo "请输入 1, 2 或 3"
          choice=""
          ;;
      esac
    done
  fi
  
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
  
  # Import files
  mkdir -p "$OPENCLAW_DIR"
  info "Importing files..."
  
  # Config
  if [ -f "$exportdir/openclaw.json" ]; then
    cp "$exportdir/openclaw.json" "$OPENCLAW_DIR/openclaw.json"
    ok "openclaw.json"
    
    # Check and prompt for missing plugins
    if $install_deps; then
      if detect_missing_plugins "$OPENCLAW_DIR/openclaw.json"; then
        if $interactive; then
          echo
          read -rp "是否自动安装? [Y/n] " ans
          if [[ "$ans" =~ ^[Nn] ]]; then
            warn "跳过插件安装"
          else
            info "安装缺失插件..."
            # Install each missing plugin
            local plugins=$(grep -oE '"openclaw-[a-z0-9-]+"' "$OPENCLAW_DIR/openclaw.json" 2>/dev/null | sort -u | tr -d '"')
            for plugin in $plugins; do
              if ! check_plugin_exists "$plugin"; then
                install_plugin "$plugin" || true
              fi
            done
            ok "插件安装完成"
          fi
        else
          # Auto install in non-interactive mode
          info "安装缺失插件..."
          local plugins=$(grep -oE '"openclaw-[a-z0-9-]+"' "$OPENCLAW_DIR/openclaw.json" 2>/dev/null | sort -u | tr -d '"')
          for plugin in $plugins; do
            if ! check_plugin_exists "$plugin"; then
              install_plugin "$plugin" || true
            fi
          done
          ok "插件安装完成"
        fi
      else
        ok "所有插件已安装"
      fi
    fi
  fi
  
  # Workspace
  if [ -d "$exportdir/workspace" ]; then
    mkdir -p "$WORKSPACE_DIR"
    # Copy each item individually to handle existing directories
    for item in "$exportdir/workspace"/*; do
      if [ -e "$item" ]; then
        local item_name=$(basename "$item")
        rm -rf "$WORKSPACE_DIR/$item_name" 2>/dev/null || true
        cp -R "$item" "$WORKSPACE_DIR/$item_name/"
      fi
    done
    ok "Workspace files"
  fi
  
  # Additional directories (from full export)
  for d in extensions identity memory credentials; do
    if [ -d "$exportdir/$d" ]; then
      cp -R "$exportdir/$d" "$OPENCLAW_DIR/$d"
      ok "$d/"
    fi
  done
  
  # Update version to archive version
  local archive_version=$(python3 -c "import json; print(json.load(open('$exportdir/manifest.json')).get('version', '1.0.0'))" 2>/dev/null || echo "1.0.0")
  info "更新版本到 $archive_version"
  
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
  --mode=MODE          Mode: replicate, standard, full, skills (default: interactive)
  --output=PATH       Custom output path
  --dry-run           Preview without creating files
  --verbose, -v       Show detailed output
  --interactive, -i  Force interactive mode

${BOLD}Export Modes:${NC}
  replicate    Config + skills + docs (no memory/credentials) [recommended]
  standard     replicate + extensions + agents
  full         Everything including memory and credentials
  skills       Skills directory only

${BOLD}Import Options:${NC}
  --force, -f       Skip confirmation prompts
  --no-backup       Don't backup existing config
  --install-deps    Automatically install missing plugins

${BOLD}Examples:${NC}
  # Export configuration (interactive mode)
  $SCRIPT_NAME export
  $SCRIPT_NAME export -i
  
  # Export with specific mode
  $SCRIPT_NAME export --mode=full --output=/tmp/backup.tar.gz
  $SCRIPT_NAME export --dry-run

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
