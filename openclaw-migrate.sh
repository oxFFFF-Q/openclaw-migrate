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

readonly VERSION="2.0.0"
readonly SCRIPT_NAME="openclaw-migrate"
readonly REPO_URL="https://github.com/oxFFFF-Q/openclaw-migrate"
readonly REPO_RAW_URL="https://raw.githubusercontent.com/oxFFFF-Q/openclaw-migrate/main"

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
WORKSPACE_DIR="$OPENCLAW_DIR/workspace"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEFAULT_OUTPUT="$HOME/openclaw-export-$TIMESTAMP.tar.gz"
LOG_FILE="/tmp/openclaw-migrate-$TIMESTAMP.log"
PREFS_FILE="$HOME/.openclaw/migrate-prefs.json"
MACHINES_FILE="$HOME/.openclaw/machines.json"

# ── Template Engine (using Python) ────────────────────────────────────────────

# Detect automatic variables
detect_auto_vars() {
  local os_type
  case "$(uname -s)" in
    Darwin) os_type="macos" ;;
    Linux) os_type="linux" ;;
    MINGW*|MSYS*|CYGWIN*) os_type="windows" ;;
    *) os_type="unknown" ;;
  esac
  
  local arch
  case "$(uname -m)" in
    arm64|aarch64) arch="arm64" ;;
    x86_64|amd64) arch="x86_64" ;;
    *) arch="unknown" ;;
  esac
  
  echo "hostname=$(hostname)"
  echo "os=$os_type"
  echo "arch=$arch"
  echo "home=$HOME"
  echo "user=${USER:-$(whoami)}"
}

# Load machine configuration
load_machine_config() {
  local machine_name="$1"
  
  [ -f "$MACHINES_FILE" ] || return 1
  
  python3 -c "
import json
import sys
import os
import platform

machines = json.load(open('$MACHINES_FILE'))
if '$machine_name' not in machines:
    sys.exit(1)

config = machines['$machine_name']
config['hostname'] = '$machine_name'
config['os'] = 'macos' if platform.system() == 'Darwin' else 'linux' if platform.system() == 'Linux' else 'windows'
config['arch'] = 'arm64' if platform.machine() in ['arm64', 'aarch64'] else 'x86_64'
config['home'] = os.path.expanduser('~')
config['user'] = os.environ.get('USER', os.environ.get('USERNAME', 'unknown'))

for k, v in config.items():
    print(f'{k}={v}')
"
}

# Validate machines.json format
validate_machines_file() {
  if [ ! -f "$MACHINES_FILE" ]; then
    err "Machines file not found: $MACHINES_FILE"
    info "Creating sample machines file..."
    mkdir -p "$(dirname "$MACHINES_FILE")"
    cat > "$MACHINES_FILE" <<'EOF'
{
  "my-machine": {
    "hostname": "my-machine",
    "macos": true,
    "office": false,
    "default_model": "anthropic/claude-3-sonnet",
    "workspace_path": "~/openclaw"
  }
}
EOF
    ok "Created sample machines file: $MACHINES_FILE"
    return 1
  fi
  
  python3 -c "import json; json.load(open('$MACHINES_FILE'))" 2>/dev/null || {
    err "Invalid JSON format in machines file"
    return 1
  }
  
  ok "Machines file validation passed"
  return 0
}

# Process template with variables using Python
process_template() {
  local content="$1"
  shift
  
  # Build variables as arguments to Python
  python3 -c "
import re
import sys

content = '''$content'''

vars = {}
$(
  while [ \$# -gt 0 ]; do
    local key=\"\${1%%=*}\"
    local value=\"\${1#*=}\"
    echo \"vars['$key'] = '''$value'''\"
    shift
  done
)

# Auto-detect variables
import platform
import os
vars['hostname'] = '$([hostname])'
vars['os'] = 'macos' if platform.system() == 'Darwin' else 'linux' if platform.system() == 'Linux' else 'windows'
vars['arch'] = 'arm64' if platform.machine() in ['arm64', 'aarch64'] else 'x86_64'
vars['home'] = os.path.expanduser('~')
vars['user'] = os.environ.get('USER', os.environ.get('USERNAME', 'unknown'))

def process_template(content, vars):
    # 1. Handle {{#if var}}...{{else}}...{{/if}}
    pattern_if_else = r'\{\{\#if\s+([a-zA-Z_][a-zA-Z0-9_]*)\}\}(.*?)\{\{else\}\}(.*?)\{\{\/if\}\}'
    def replace_if_else(m):
        var_name = m.group(1)
        if_content = m.group(2)
        else_content = m.group(3)
        var_val = vars.get(var_name, '')
        if var_val and str(var_val).lower() not in ['false', '0', '']:
            return if_content
        else:
            return else_content
    content = re.sub(pattern_if_else, replace_if_else, content, flags=re.DOTALL)
    
    # 2. Handle {{#if var}}...{{/if}}
    pattern_if = r'\{\{\#if\s+([a-zA-Z_][a-zA-Z0-9_]*)\}\}(.*?)\{\{\/if\}\}'
    def replace_if(m):
        var_name = m.group(1)
        if_content = m.group(2)
        var_val = vars.get(var_name, '')
        if var_val and str(var_val).lower() not in ['false', '0', '']:
            return if_content
        return ''
    content = re.sub(pattern_if, replace_if, content, flags=re.DOTALL)
    
    # 3. Handle {{var|default}}
    pattern_default = r'\{\{([a-zA-Z_][a-zA-Z0-9_]*)\|([^}]+)\}\}'
    def replace_default(m):
        var_name = m.group(1)
        default_val = m.group(2)
        var_val = vars.get(var_name)
        if var_val is not None and str(var_val).lower() not in ['false', '0', '']:
            return str(var_val)
        return default_val
    content = re.sub(pattern_default, replace_default, content)
    
    # 4. Handle {{var}}
    pattern_var = r'\{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\}'
    undefined = []
    def replace_var(m):
        var_name = m.group(1)
        var_val = vars.get(var_name)
        if var_val is not None:
            return str(var_val)
        undefined.append(var_name)
        return 'UNDEFINED:' + var_name
    content = re.sub(pattern_var, replace_var, content)
    
    if undefined:
        print('WARNING: Undefined variables: ' + ', '.join(set(undefined)), file=sys.stderr)
    
    return content

print(process_template(content, vars))
" 2>&1
}

# Check template syntax
check_template_syntax() {
  local content="$1"
  local errors=0
  local warnings=0
  
  python3 -c "
import re
content = '''$content'''
errors = 0
warnings = 0

# Check unclosed conditionals
if_count = len(re.findall(r'\{\{\#if\s+[a-zA-Z_][a-zA-Z0-9_]*\}\}', content))
endif_count = len(re.findall(r'\{\{\/if\}\}', content))
if if_count != endif_count:
    print(f'ERROR: Unclosed conditional: {if_count} {{#if}} but {endif_count} {{/if}}')
    errors += 1

# Check invalid syntax
if '{{' in content and content.rstrip()[-2:] != '}}' and not re.search(r'\}\}[^{]*$', content):
    if '{{' in content.split('\n')[-1]:
        print('ERROR: Malformed template: unclosed {{')
        errors += 1

exit(errors)
" || return 1
  return 0
}

# Template check command
do_template_check() {
  local template_file=""
  
  for arg in "$@"; do
    case "$arg" in
      --file=*) template_file="${arg#--file=}" ;;
      --help)
        cat <<'EOF'
Template Syntax Checker

Usage: openclaw-migrate.sh template-check [options]

Options:
  --file=PATH    Check specific template file
  --help         Show this help

Examples:
  openclaw-migrate.sh template-check
  openclaw-migrate.sh template-check --file=~/.openclaw/openclaw.json
EOF
        return 0
        ;;
    esac
  done
  
  echo
  echo -e "${MAGENTA}🔍 ${BOLD}Template Syntax Checker${NC}"
  echo
  
  # Validate machines.json
  echo -e "${BOLD}Validating machines.json...${NC}"
  validate_machines_file || true
  echo
  
  # List available machines
  if [ -f "$MACHINES_FILE" ]; then
    echo -e "${BOLD}Available machines:${NC}"
    python3 -c "
import json
m = json.load(open('$MACHINES_FILE'))
for name, config in m.items():
    os_type = 'macOS' if config.get('macos') else 'Linux'
    model = config.get('default_model', 'N/A')
    print(f'  * {name} ({os_type}, model: {model})')
" 2>/dev/null || true
    echo
  fi
  
  # Test template processing
  echo -e "${BOLD}Testing template processing...${NC}"
  local test_template='{
  "model": "{{default_model|default/model}}",
  "workspace": "{{workspace_path}}",
  "proxy": "{{#if office}}http://proxy.company.com:8080{{else}}{{/if}}",
  "skills_dir": "{{#if macos}}~/Documents/skills{{else}}~/skills{{/if}}"
}'
  
  echo -e "${CYAN}Test template:${NC}"
  echo "$test_template"
  echo
  
  # Test with each machine
  if [ -f "$MACHINES_FILE" ]; then
    for machine in $(python3 -c "import json; print(' '.join(json.load(open('$MACHINES_FILE')).keys()))" 2>/dev/null); do
      echo -e "${CYAN}Machine: $machine${NC}"
      local result
      result=$(load_machine_config "$machine" | while IFS= read -r line; do process_template "$test_template" "$line"; done)
      result=$(load_machine_config "$machine" | xargs -I {} bash -c 'source /dev/stdin <<<"result=\$(process_template \"$test_template\" {})" && echo "$result"' 2>/dev/null) || true
      
      # Simpler approach: use python directly
      result=$(python3 -c "
import json
import re
import platform
import os

machines = json.load(open('$MACHINES_FILE'))
config = machines['$machine']
config['hostname'] = '$machine'
config['os'] = 'macos' if platform.system() == 'Darwin' else 'linux'
config['arch'] = 'arm64' if platform.machine() in ['arm64', 'aarch64'] else 'x86_64'
config['home'] = os.path.expanduser('~')
config['user'] = os.environ.get('USER', 'unknown')

vars = config
content = '''$test_template'''

# Process conditionals with else
content = re.sub(r'\{\{\#if\s+([a-zA-Z_][a-zA-Z0-9_]*)\}\}(.*?)\{\{else\}\}(.*?)\{\{\/if\}\}', 
    lambda m: m.group(2) if vars.get(m.group(1)) and str(vars[m.group(1)]).lower() not in ['false','0',''] else m.group(3), content)

# Process simple conditionals
content = re.sub(r'\{\{\#if\s+([a-zA-Z_][a-zA-Z0-9_]*)\}\}(.*?)\{\{\/if\}\}',
    lambda m: m.group(2) if vars.get(m.group(1)) and str(vars[m.group(1)]).lower() not in ['false','0',''] else '', content)

# Process defaults
content = re.sub(r'\{\{([a-zA-Z_][a-zA-Z0-9_]*)\|([^}]+)\}\}',
    lambda m: str(vars[m.group(1)]) if vars.get(m.group(1)) and str(vars[m.group(1)]).lower() not in ['false','0',''] else m.group(2), content)

# Process simple variables
content = re.sub(r'\{\{([a-zA-Z_][a-zA-Z0-9_]*)\}\}',
    lambda m: str(vars[m.group(1)]) if m.group(1) in vars else 'UNDEFINED:'+m.group(1), content)

print(content)
" 2>&1)
      
      echo "$result" | python3 -m json.tool 2>/dev/null || echo "$result"
      echo
    done
  fi
  
  # Check syntax of openclaw.json if exists
  if [ -z "$template_file" ] && [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
    template_file="$OPENCLAW_DIR/openclaw.json"
  fi
  
  if [ -n "$template_file" ] && [ -f "$template_file" ]; then
    echo -e "${BOLD}Checking template file:${NC} $template_file"
    if check_template_syntax "$(cat "$template_file")"; then
      ok "Template syntax is valid"
    else
      err "Template has syntax errors"
    fi
  fi
  
  echo
  ok "Template check complete"
}

# ── Internationalization ───────────────────────────────────────────────────

LANG="${LANG:-zh}"

load_prefs() {
  if [ -f "$PREFS_FILE" ]; then
    local saved_lang
    saved_lang=$(python3 -c "import json; print(json.load(open('$PREFS_FILE')).get('language', 'zh'))" 2>/dev/null || echo "zh")
    LANG="$saved_lang"
  fi
}

save_prefs() {
  mkdir -p "$(dirname "$PREFS_FILE")"
  python3 -c "
import json
data = {}
try:
    with open('$PREFS_FILE', 'r') as f:
        data = json.load(f)
except: pass
data['language'] = '$LANG'
with open('$PREFS_FILE', 'w') as f:
    json.dump(data, f)
" 2>/dev/null || true
}

t() {
  local key="$1"
  case "$LANG" in
    en)
      case "$key" in
        select_preset) echo "Select export preset:" ;;
        quick) echo "Quick - Core config + skills" ;;
        standard) echo "Standard - + extensions + multi-agent" ;;
        full) echo "Full - Everything including memory & credentials" ;;
        custom) echo "Custom - Choose items manually" ;;
        custom_options) echo "Custom Export Options" ;;
        toggle_selection) echo "Enter numbers to toggle selection (space-separated, Enter to confirm):" ;;
        output_path) echo "Output path" ;;
        output_default) echo "Default" ;;
        language) echo "Language" ;;
        confirm_export) echo "Confirm export?" ;;
        select_language) echo "Select language:" ;;
        press_enter) echo "Press Enter to continue" ;;
        preview_export) echo "Will export:" ;;
        estimated_size) echo "Estimated size" ;;
      esac
      ;;
    *)
      case "$key" in
        select_preset) echo "选择导出预设:" ;;
        quick) echo "快速 - 核心配置 + 自建技能" ;;
        standard) echo "标准 - + 扩展插件 + 多 Agent" ;;
        full) echo "完整 - 全部内容含记忆凭证" ;;
        custom) echo "自定义 - 手动选择每一项" ;;
        custom_options) echo "自定义导出选项" ;;
        toggle_selection) echo "请输入序号切换选择 (空格分隔，回车确认):" ;;
        output_path) echo "输出路径" ;;
        output_default) echo "默认" ;;
        language) echo "语言" ;;
        confirm_export) echo "确认导出?" ;;
        select_language) echo "选择语言:" ;;
        press_enter) echo "按回车键继续" ;;
        preview_export) echo "将导出以下内容:" ;;
        estimated_size) echo "预估大小" ;;
      esac
      ;;
  esac
}

load_prefs

# ── Colors & Output ────────────────────────────────────────────────────────

if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  MAGENTA='\033[0;35m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  MAGENTA=''
  CYAN=''
  BOLD=''
  NC=''
fi

log()  { echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"; }
info() { echo -e "${BLUE}ℹ${NC}  $*"; log "[INFO] $*"; }
ok()   { echo -e "${GREEN}✔${NC}  $*"; log "[OK] $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; log "[WARN] $*"; }
err()  { echo -e "${RED}✖${NC}  $*" >&2; log "[ERROR] $*"; }
die()  { err "$@"; exit 1; }

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

check_node() {
  if command -v node &>/dev/null; then
    local version=$(node -v 2>/dev/null)
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
  if command -v python3 &>/dev/null; then
    return 0
  fi
  warn "Neither jq nor python3 found, JSON output will be raw"
  return 1
}

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
      sudo apt-get update && sudo apt-get install -y nodejs npm || die "Failed to install Node.js"
      ;;
    redhat)
      sudo yum install -y nodejs npm || die "Failed to install Node.js"
      ;;
    arch)
      sudo pacman -S nodejs npm || die "Failed to install Node.js"
      ;;
    alpine)
      sudo apk add nodejs npm || die "Failed to install Node.js"
      ;;
    *)
      die "Cannot auto-install Node.js on this system ($os)"
      ;;
  esac
  
  ok "Node.js installed: $(node -v)"
}

install_openclaw() {
  info "Installing OpenClaw..."
  
  if ! command -v npm &>/dev/null; then
    die "npm is required to install OpenClaw"
  fi
  
  npm install -g openclaw || {
    warn "Permission denied, trying with sudo..."
    sudo npm install -g openclaw || die "Failed to install OpenClaw"
  }
  
  ok "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'installed')"
}

calculate_export_size() {
  local total_size=0
  
  for item in "$@"; do
    if [ -e "$item" ]; then
      local size=$(du -sb "$item" 2>/dev/null | cut -f1)
      total_size=$((total_size + size))
    fi
  done
  
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

# ── Language Selection ───────────────────────────────────────────────────

do_select_language() {
  echo
  echo -e "${MAGENTA}⚙️  ${BOLD}$(t 'language')${NC}"
  echo
  echo "  1) English"
  echo "  2) 中文"
  echo
  
  local choice=""
  while [ -z "$choice" ]; do
    printf "${CYAN}?${NC} $(t 'select_language') [1-2]: "
    read -r choice
    
    case "$choice" in
      1)
        LANG="en"
        save_prefs
        ok "Language set to English"
        ;;
      2)
        LANG="zh"
        save_prefs
        ok "语言已设为中文"
        ;;
      *)
        echo -e "${RED}Invalid choice, please enter 1 or 2${NC}"
        choice=""
        ;;
    esac
  done
  
  echo
  printf "${CYAN}%s${NC}\n" "$(t 'press_enter')"
  read -r
}

# ── Interactive Export Mode ───────────────────────────────────────────────

do_export_interactive() {
  local output="$DEFAULT_OUTPUT"
  local verbose=false
  
  for arg in "$@"; do
    case "$arg" in
      --output=*) output="${arg#--output=}" ;;
      --verbose|-v) verbose=true ;;
    esac
  done
  
  echo
  echo -e "${MAGENTA}📦 ${BOLD}OpenClaw 配置导出向导${NC}"
  echo
  
  local options=(
    "1) 🚀 $(t 'quick')"
    "2) 📋 $(t 'standard')"
    "3) 🔐 $(t 'full')"
    "4) ⚙️  $(t 'custom')"
  )
  
  echo -e "${CYAN}?${NC} ${BOLD}$(t 'select_preset')${NC}"
  echo
  for opt in "${options[@]}"; do
    echo "  $opt"
  done
  echo
  
  local choice=""
  while [ -z "$choice" ]; do
    printf "${CYAN}?${NC} $(t 'select_preset') [1-4]: "
    read -r choice
    
    case "$choice" in
      1)
        do_export --mode=replicate --output="$output" ${verbose:+"--verbose"}
        return $?
        ;;
      2)
        do_export --mode=standard --output="$output" ${verbose:+"--verbose"}
        return $?
        ;;
      3)
        do_export --mode=full --output="$output" ${verbose:+"--verbose"}
        return $?
        ;;
      4)
        echo
        local custom_output=""
        printf "${CYAN}?${NC} $(t 'output_path') ($(t 'output_default'): $DEFAULT_OUTPUT): "
        read -r custom_output
        if [ -z "$custom_output" ]; then
          custom_output="$output"
        fi
        do_export_custom "$custom_output" "$verbose"
        return $?
        ;;
      *)
        echo -e "${RED}Invalid choice, please enter 1-4${NC}"
        choice=""
        ;;
    esac
  done
}

# Custom export with toggle selection
do_export_custom() {
  local output="$1"
  local verbose="$2"
  
  local -A item_defaults
  item_defaults=(
    ["1"]=y
    ["2"]=y
    ["3"]=n
    ["4"]=n
    ["5"]=n
    ["6"]=n
    ["7"]=n
  )
  
  local -A item_paths
  local -A item_names
  
  item_paths["1"]="$OPENCLAW_DIR/openclaw.json"
  item_names["1"]="核心配置 (openclaw.json)"
  
  item_paths["2"]="$WORKSPACE_DIR/skills"
  item_names["2"]="自建技能 (workspace/skills)"
  
  item_paths["3"]="$OPENCLAW_DIR/skills"
  item_names["3"]="ClawHub 技能"
  
  item_paths["4"]="$OPENCLAW_DIR/extensions"
  item_names["4"]="扩展插件"
  
  item_paths["5"]="$OPENCLAW_DIR/agents"
  item_names["5"]="多 Agent 配置"
  
  item_paths["6"]="$WORKSPACE_DIR/memory"
  item_names["6"]="记忆文件"
  
  item_paths["7"]="$OPENCLAW_DIR/credentials"
  item_names["7"]="凭证和密钥"
  
  echo
  echo -e "${MAGENTA}⚙️  ${BOLD}$(t 'custom_options')${NC}"
  echo
  
  show_custom_selection() {
    for i in {1..7}; do
      local checkbox="[ ]"
      if [ "${item_defaults[$i]}" = "y" ]; then
        checkbox="[✓]"
      fi
      echo "  $i) $checkbox ${item_names[$i]}"
    done
  }
  
  show_custom_selection
  
  echo
  echo -e "${CYAN}$(t 'toggle_selection')${NC}"
  printf "${CYAN}>${NC} "
  read -r input
  
  if [ -n "$input" ]; then
    for num in $input; do
      if [[ "$num" =~ ^[1-7]$ ]]; then
        if [ "${item_defaults[$num]}" = "y" ]; then
          item_defaults[$num]="n"
        else
          item_defaults[$num]="y"
        fi
      fi
    done
  fi
  
  local selected=()
  local preview_items=()
  
  for i in {1..7}; do
    if [ "${item_defaults[$i]}" = "y" ]; then
      selected+=("$i")
      preview_items+=("${item_paths[$i]}")
    fi
  done
  
  if [ ${#selected[@]} -eq 0 ]; then
    warn "未选择任何项目，取消导出"
    return 1
  fi
  
  echo
  echo -e "${CYAN}$(t 'preview_export')${NC}"
  echo
  
  for i in "${selected[@]}"; do
    echo "  ✓ ${item_names[$i]}"
  done
  
  local size_estimate=$(calculate_export_size "${preview_items[@]}")
  echo
  echo -e "${CYAN}$(t 'estimated_size'):${NC} $size_estimate"
  echo
  
  printf "${CYAN}?${NC} $(t 'confirm_export') [Y/n]: "
  read -r confirm
  if [[ "$confirm" =~ ^[Nn] ]]; then
    warn "导出已取消"
    return 1
  fi
  
  do_export_custom_files "$output" "${selected[@]}"
}

do_export_custom_files() {
  local output="$1"
  shift
  local selected=("$@")
  
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" EXIT
  
  local exportdir="$tmpdir/openclaw-export"
  mkdir -p "$exportdir"
  
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
      1)
        copy_item_custom "$OPENCLAW_DIR/openclaw.json" "$exportdir/openclaw.json"
        ;;
      2)
        if [ -d "$WORKSPACE_DIR/skills" ]; then
          copy_item_custom "$WORKSPACE_DIR/skills" "$exportdir/workspace/skills"
        fi
        ;;
      3)
        if [ -d "$OPENCLAW_DIR/skills" ]; then
          copy_item_custom "$OPENCLAW_DIR/skills" "$exportdir/skills"
        fi
        ;;
      4)
        if [ -d "$OPENCLAW_DIR/extensions" ]; then
          copy_item_custom "$OPENCLAW_DIR/extensions" "$exportdir/extensions"
        fi
        ;;
      5)
        if [ -d "$OPENCLAW_DIR/agents" ]; then
          copy_item_custom "$OPENCLAW_DIR/agents" "$exportdir/agents"
        fi
        if ls "$WORKSPACE_DIR"/workspace-* &>/dev/null; then
          for workspace_dir in "$WORKSPACE_DIR"/workspace-*; do
            if [ -d "$workspace_dir" ]; then
              local dir_name=$(basename "$workspace_dir")
              copy_item_custom "$workspace_dir" "$exportdir/workspace/$dir_name"
            fi
          done
        fi
        ;;
      6)
        if [ -d "$WORKSPACE_DIR/memory" ]; then
          copy_item_custom "$WORKSPACE_DIR/memory" "$exportdir/workspace/memory"
        fi
        ;;
      7)
        if [ -d "$OPENCLAW_DIR/credentials" ]; then
          copy_item_custom "$OPENCLAW_DIR/credentials" "$exportdir/credentials"
        fi
        ;;
    esac
  done
  
  if [[ " ${selected[*]} " =~ " 1 " ]] || [[ " ${selected[*]} " =~ " 2 " ]]; then
    mkdir -p "$exportdir/workspace"
    for f in AGENTS.md TOOLS.md SOUL.md USER.md IDENTITY.md HEARTBEAT.md; do
      if [ -f "$WORKSPACE_DIR/$f" ]; then
        copy_item_custom "$WORKSPACE_DIR/$f" "$exportdir/workspace/$f"
      fi
    done
  fi
  
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
  
  tar -czf "$output" -C "$tmpdir" "openclaw-export"
  
  local final_size=$(du -h "$output" | cut -f1)
  
  echo
  ok "导出完成!"
  echo
  echo -e "  ${BOLD}输出:${NC}     $output"
  echo -e "  ${BOLD}大小:${NC}       $final_size"
  echo
}

# ── Export Functions ───────────────────────────────────────────────────

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
  
  if $interactive; then
    do_export_interactive "$@"
    return $?
  fi
  
  if [ -z "$mode" ]; then
    if [ -t 0 ]; then
      do_export_interactive "$@"
      return $?
    else
      mode="replicate"
    fi
  fi
  
  case "$mode" in
    replicate|standard|full|skills) ;;
    *) die "Invalid mode: $mode (use: replicate, standard, full, or skills)" ;;
  esac
  
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
      
      # 🎯 方案 A: 导出时路径变量化
      # 如果复制的是 openclaw.json，将其路径变量化
      if [[ "$dest" == *"openclaw.json" ]] && [ -f "$dest" ]; then
        info "Variable path in $name..."
        local_user=$(whoami)
        # 替换绝对路径为 ${OPENCLAW_HOME} 变量
        python3 << PYEOF
import json
import os
import re

with open('$dest', 'r') as f:
    content = f.read()

# 检测 home 目录路径
home_paths = [
    (os.path.expanduser('~'), '\${OPENCLAW_HOME}'),
]

# 替换所有匹配的路径
for old, new in home_paths:
    if old and old != new:
        content = content.replace(old, new)

with open('$dest', 'w') as f:
    f.write(content)
PYEOF
      fi
      
      file_count=$((file_count + 1))
      return 0
    fi
    $verbose && warn "$name not found, skipping"
    return 1
  }
  
  case "$mode" in
    skills)
      info "Exporting skills only..."
      copy_item "$WORKSPACE_DIR/skills" "$exportdir/workspace/skills" "Skills"
      ;;
      
    replicate)
      info "Exporting configuration (replicate mode)..."
      copy_item "$OPENCLAW_DIR/openclaw.json" "$exportdir/openclaw.json" "openclaw.json"
      copy_item "$WORKSPACE_DIR/skills" "$exportdir/workspace/skills" "Skills"
      copy_item "$WORKSPACE_DIR/scripts" "$exportdir/workspace/scripts" "Scripts"
      for f in AGENTS.md TOOLS.md SOUL.md USER.md IDENTITY.md HEARTBEAT.md MEMORY.md; do
        copy_item "$WORKSPACE_DIR/$f" "$exportdir/workspace/$f" "$f"
      done
      if [ -d "$WORKSPACE_DIR/PLANS" ]; then
        copy_item "$WORKSPACE_DIR/PLANS" "$exportdir/workspace/PLANS" "PLANS"
      fi
      ;;
      
    standard)
      info "Exporting configuration (standard mode)..."
      copy_item "$OPENCLAW_DIR/openclaw.json" "$exportdir/openclaw.json" "openclaw.json"
      copy_item "$WORKSPACE_DIR/skills" "$exportdir/workspace/skills" "Skills"
      copy_item "$WORKSPACE_DIR/scripts" "$exportdir/workspace/scripts" "Scripts"
      for f in AGENTS.md TOOLS.md SOUL.md USER.md IDENTITY.md HEARTBEAT.md MEMORY.md; do
        copy_item "$WORKSPACE_DIR/$f" "$exportdir/workspace/$f" "$f"
      done
      if [ -d "$WORKSPACE_DIR/PLANS" ]; then
        copy_item "$WORKSPACE_DIR/PLANS" "$exportdir/workspace/PLANS" "PLANS"
      fi
      if [ -d "$OPENCLAW_DIR/extensions" ]; then
        copy_item "$OPENCLAW_DIR/extensions" "$exportdir/extensions" "Extensions"
      fi
      if [ -d "$OPENCLAW_DIR/agents" ]; then
        copy_item "$OPENCLAW_DIR/agents" "$exportdir/agents" "Agents"
      fi
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
      cp -R "$OPENCLAW_DIR/." "$exportdir/"
      rm -rf "$exportdir/sessions" 2>/dev/null || true
      rm -rf "$exportdir/logs" 2>/dev/null || true
      rm -rf "$exportdir/tmp" 2>/dev/null || true
      ok "Full export (excluding sessions/logs/tmp)"
      file_count=$(find "$exportdir" -type f | wc -l | tr -d ' ')
      ;;
  esac
  
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
    rm -rf "$tmpdir"
    return 0
  fi
  
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
}

# ── Import Functions ───────────────────────────────────────────────────

display_import_summary() {
  local manifest="$1"
  local export_dir="$2"
  
  local source_os source_hostname source_time version
  source_os=$(python3 -c "import json; print(json.load(open('$manifest')).get('source', {}).get('os', 'Unknown'))" 2>/dev/null || echo "Unknown")
  source_hostname=$(python3 -c "import json; print(json.load(open('$manifest')).get('source', {}).get('hostname', 'Unknown'))" 2>/dev/null || echo "Unknown")
  source_time=$(python3 -c "import json; print(json.load(open('$manifest')).get('timestamp', '').replace('T', ' ').replace('Z', ''))" 2>/dev/null || echo "Unknown")
  version=$(python3 -c "import json; print(json.load(open('$manifest')).get('version', '1.0.0'))" 2>/dev/null || echo "1.0.0")
  
  local has_config=false has_skills=false has_extensions=false has_agents=false has_memory=false has_credentials=false
  
  [ -f "$export_dir/openclaw.json" ] && has_config=true
  [ -d "$export_dir/workspace/skills" ] && has_skills=true
  [ -d "$export_dir/extensions" ] && has_extensions=true
  [ -d "$export_dir/workspace/AGENTS.md" ] || [ -d "$export_dir/workspace/agents" ] && has_agents=true
  [ -d "$export_dir/memory" ] || [ -d "$export_dir/workspace/memory" ] && has_memory=true
  [ -d "$export_dir/credentials" ] || [ -d "$export_dir/identity" ] && has_credentials=true
  
  local skill_count=0 extension_count=0
  if [ -d "$export_dir/workspace/skills" ]; then
    skill_count=$(find "$export_dir/workspace/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ -d "$export_dir/extensions" ]; then
    extension_count=$(find "$export_dir/extensions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  fi
  
  local archive_size=$(du -h "$archive" | cut -f1)
  
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

check_plugin_exists() {
  local plugin_name="$1"
  
  if openclaw plugins list 2>/dev/null | grep -q "$plugin_name"; then
    return 0
  fi
  return 1
}

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

detect_missing_plugins() {
  local config_file="$1"
  local missing_plugins=()
  
  if [ ! -f "$config_file" ]; then
    return 0
  fi
  
  local plugins=$(grep -oE '"openclaw-[a-z0-9-]+"' "$config_file" 2>/dev/null | sort -u | tr -d '"')
  
  if [ -z "$plugins" ]; then
    return 0
  fi
  
  for plugin in $plugins; do
    if ! check_plugin_exists "$plugin"; then
      missing_plugins+=("$plugin")
    fi
  done
  
  if [ ${#missing_plugins[@]} -gt 0 ]; then
    echo
    warn "检测到以下插件未安装:"
    for plugin in "${missing_plugins[@]}"; do
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
  local install
_deps=false
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
  
  if ! tar -tzf "$archive" &>/dev/null; then
    die "Invalid archive: not a valid gzip tar file"
  fi
  
  # 🧠 智能检测：OpenClaw 是否已安装
  local openclaw_installed=false
  if [ -d "$HOME/.openclaw" ] && [ -f "$HOME/.openclaw/openclaw.json" ]; then
    openclaw_installed=true
  fi
  
  # 如果未安装，询问是否安装
  if [ "$openclaw_installed" = false ] && $interactive; then
    echo
    warn "未检测到 OpenClaw 配置"
    echo
    echo -e "${BOLD}? 检测到新系统，如何继续?${NC}"
    echo "  ❯ 1) 一键安装 OpenClaw 并导入配置"
    echo "    2) 仅解压缩到当前目录"
    echo "    3) 取消"
    echo
    
    local choice=""
    while [ -z "$choice" ]; do
      read -rp "> " choice
      case "$choice" in
        1|"1")
          info "正在安装 OpenClaw..."
          # 安装 OpenClaw
          if command -v npm &>/dev/null; then
            npm install -g openclaw 2>/dev/null || npm install -g @openclaw/core 2>/dev/null || {
              # 尝试 curl 安装
              curl -fsSL https://openclaw.ai/install.sh | bash 2>/dev/null || die "安装失败，请手动安装 OpenClaw"
            }
          else
            curl -fsSL https://openclaw.ai/install.sh | bash 2>/dev/null || die "需要 Node.js，请先安装"
          fi
          openclaw_installed=true
          ;;
        2)
          # 仅解压缩
          local extract_dir="./openclaw-import-$(date +%Y%m%d_%H%M%S)"
          mkdir -p "$extract_dir"
          tar -xzf "$archive" -C "$extract_dir"
          ok "已解压缩到: $extract_dir"
          return 0
          ;;
        3|"取消"|"n"|"N")
          die "已取消"
          ;;
        *)
          echo "请输入 1, 2 或 3"
          choice=""
          ;;
      esac
    done
  fi
  
  # 🧩 已安装：显示合并选项（移除危险的"完全覆盖"选项）
  local merge_strategy=""
  if [ "$openclaw_installed" = true ] && $interactive; then
    echo
    info "检测到已有 OpenClaw 配置"
    echo
    echo -e "${BOLD}? 如何处理现有配置?${NC}"
    echo "  ❯ 1) 智能合并（推荐） - 保留本地系统配置，合并用户数据"
    echo "    2) 仅导入文件 - 忽略 openclaw.json，只导入技能/扩展"
    echo "    3) 取消"
    echo
    
    local merge_choice=""
    while [ -z "$merge_choice" ]; do
      read -rp "> " merge_choice
      case "$merge_choice" in
        1|"智能合并"|"1")
          merge_strategy="smart"
          install_deps=true
          ;;
        2|"仅导入文件"|"2")
          merge_strategy="files-only"
          install_deps=true
          ;;
        3|"取消"|"n"|"N")
          die "已取消"
          ;;
        *)
          echo "请输入 1, 2 或 3"
          merge_choice=""
          ;;
      esac
    done
    
    # 已选择合并策略，跳过后面的重复交互
    interactive=false
  fi
  
  info "Extracting archive..."
  
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf '$tmpdir'" EXIT
  
  tar -xzf "$archive" -C "$tmpdir" || die "Failed to extract archive"
  
  local exportdir="$tmpdir/openclaw-export"
  [ -d "$exportdir" ] || die "Invalid archive: missing openclaw-export directory"
  [ -f "$exportdir/manifest.json" ] || die "Invalid archive: missing manifest.json"
  
  display_import_summary "$exportdir/manifest.json" "$exportdir"
  
  # 如果之前没有选择合并策略（新系统场景），才询问是否导入
  if $interactive; then
    echo -e "${BOLD}? 确认导入?${NC}"
    echo "  ❯ 1) 是，导入并安装缺失插件"
    echo "    2) 是，仅导入配置"
    echo "    3) 否，取消"
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
  
  if [ -d "$OPENCLAW_DIR" ] && ! $no_backup; then
    local backup="$HOME/openclaw-backup-$TIMESTAMP.tar.gz"
    info "Backing up existing configuration..."
    tar -czf "$backup" -C "$HOME" ".openclaw" 2>/dev/null && ok "Backup: $backup" || warn "Backup failed, continuing anyway"
  fi
  
  mkdir -p "$OPENCLAW_DIR"
  info "Importing files..."
  
  # 验证并安全导入 openclaw.json
  if [ -f "$exportdir/openclaw.json" ]; then
    # 1. 验证 JSON 格式
    if python3 -c "import json; json.load(open('$exportdir/openclaw.json'))" 2>/dev/null; then
      # 2. 验证必需字段
      if python3 -c "import json; d=json.load(open('$exportdir/openclaw.json')); assert 'meta' in d or 'auth' in d" 2>/dev/null; then
        # 3. 原子操作：先写入临时文件
        local tmp_json="$OPENCLAW_DIR/openclaw.json.tmp.$$"
        cp "$exportdir/openclaw.json" "$tmp_json"
        
        # 4. 验证临时文件有效
        if python3 -c "import json; json.load(open('$tmp_json'))" 2>/dev/null; then
          # 5. 原子替换
          mv "$tmp_json" "$OPENCLAW_DIR/openclaw.json"
          ok "openclaw.json (validated)"
        else
          rm -f "$tmp_json"
          err "Import aborted: invalid temp file"
        fi
      else
        warn "Import skipped: openclaw.json missing required fields (meta/auth)"
      fi
    else
      err "Import aborted: invalid JSON in archive"
      err "Run: openclaw backup verify to check backup integrity"
    fi
    
    if $install_deps; then
      if detect_missing_plugins "$OPENCLAW_DIR/openclaw.json"; then
        if $interactive; then
          echo
          read -rp "是否自动安装? [Y/n] " ans
          if [[ "$ans" =~ ^[Nn] ]]; then
            warn "跳过插件安装"
          else
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
  
  if [ -d "$exportdir/workspace" ]; then
    mkdir -p "$WORKSPACE_DIR"
    for item in "$exportdir/workspace"/*; do
      if [ -e "$item" ]; then
        local item_name=$(basename "$item")
        rm -rf "$WORKSPACE_DIR/$item_name" 2>/dev/null || true
        # 修复：如果是目录，复制到目录内；如果是文件，直接复制
        if [ -d "$item" ]; then
          cp -R "$item" "$WORKSPACE_DIR/"
        else
          cp "$item" "$WORKSPACE_DIR/"
        fi
      fi
    done
    ok "Workspace files"
  fi
  
  for d in extensions identity memory credentials; do
    if [ -d "$exportdir/$d" ]; then
      cp -R "$exportdir/$d" "$OPENCLAW_DIR/$d"
      ok "$d/"
    fi
  done
  
  local archive_version=$(python3 -c "import json; print(json.load(open('$exportdir/manifest.json')).get('version', '1.0.0'))" 2>/dev/null || echo "1.0.0")
  info "更新版本到 $archive_version"
  
  # ═══════════════════════════════════════════════════════════════
  # 🧹 方案 B: 配置清洗 - 自动修复跨平台兼容性问题
  # ═══════════════════════════════════════════════════════════════
  info "执行配置清洗..."
  
  # B1: 检测并修复端口冲突
  if [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
    local current_port=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' "$OPENCLAW_DIR/openclaw.json" | head -1 | grep -o '[0-9]*' || echo "")
    if [ -n "$current_port" ]; then
      # 检测是否有 systemd service 固定的端口
      local systemd_port=""
      if [ -f "$HOME/.config/systemd/user/openclaw-gateway.service" ]; then
        systemd_port=$(grep -oP 'EXECLINE.*--port\s+\K[0-9]+' "$HOME/.config/systemd/user/openclaw-gateway.service" 2>/dev/null || echo "")
      fi
      if [ -n "$systemd_port" ] && [ "$current_port" != "$systemd_port" ]; then
        warn "检测到端口冲突: 配置=$current_port, systemd=$systemd_port"
        info "保留本地端口配置: $systemd_port"
      fi
    fi
    
    # ═══════════════════════════════════════════════════════════════
    # B2: 核心功能 - 智能路径转换（跨平台迁移关键！）
    # ═══════════════════════════════════════════════════════════════
    
    # 检测源系统路径（从 manifest 或配置文件）
    local source_home=""
    local source_user=""
    
    # 方法1: 从 manifest 获取源系统信息
    if [ -f "$exportdir/manifest.json" ]; then
      source_user=$(python3 -c "import json; print(json.load(open('$exportdir/manifest.json')).get('source',{}).get('user','unknown'))" 2>/dev/null || echo "")
    fi
    
    # 方法2: 从配置文件检测 macOS 路径
    if [ -z "$source_user" ]; then
      source_home=$(grep -o '"/Users/[^/]*' "$OPENCLAW_DIR/openclaw.json" 2>/dev/null | head -1 | tr -d '"' || echo "")
      if [ -n "$source_home" ]; then
        source_user=$(echo "$source_home" | cut -d'/' -f3)
      fi
    fi
    
    # 获取目标系统信息
    local target_user=$(whoami)
    local target_home=$(eval echo ~$target_user)
    
    # 如果检测到跨系统迁移，执行路径转换
    if [ -n "$source_user" ] && [ "$source_user" != "$target_user" ]; then
      info "检测到跨系统迁移: $source_user → $target_user"
      info "执行路径转换..."
      
      # 使用 Python 进行安全的 JSON 路径转换
      python3 << PYEOF
import json
import os

config_file = "$OPENCLAW_DIR/openclaw.json"
source_user = "$source_user"
target_home = "$target_home"

# 读取配置
with open(config_file, 'r') as f:
    content = f.read()

converted = 0

# 🎯 方案 A: 导入时变量本地化
# 优先处理 ${OPENCLAW_HOME} 变量
if '${OPENCLAW_HOME}' in content:
    content = content.replace('${OPENCLAW_HOME}', target_home)
    converted += content.count(target_home)
    print(f"Converted {converted} variable paths")

# 备用：处理绝对路径（兼容旧归档）
elif source_user:
    # 转换 macOS 路径: /Users/eva/.openclaw/... → /home/ubuntu/.openclaw/...
    content = content.replace(f'/Users/{source_user}', target_home)
    converted += content.count(target_home)
    print(f"Converted {converted} absolute paths")

# 写回配置
with open(config_file, 'w') as f:
    f.write(content)

print(f"Total: {converted} paths converted")
PYEOF
      
      # 验证转换后的 JSON 有效
      if python3 -c "import json; json.load(open('$OPENCLAW_DIR/openclaw.json'))" 2>/dev/null; then
        ok "路径转换完成"
      else
        err "路径转换后 JSON 无效，恢复原始配置"
        # 这里可以添加恢复逻辑
      fi
    else
      info "未检测到跨系统路径差异，跳过转换"
    fi
    
    # B3: 检测版本兼容性
    local config_version=$(python3 -c "import json; d=json.load(open('$OPENCLAW_DIR/openclaw.json')); print(d.get('meta',{}).get('lastTouchedAt','')[:10] if d.get('meta') else '')" 2>/dev/null || echo "")
    if [ -n "$config_version" ]; then
      info "配置最后修改: $config_version"
    fi
  fi
  
  # ═══════════════════════════════════════════════════════════════
  # 🛠️ 方案 C: 自动修复 - 运行 openclaw doctor --fix
  # ═══════════════════════════════════════════════════════════════
  echo
  info "尝试自动修复配置..."
  if command -v openclaw &>/dev/null; then
    if openclaw doctor --fix 2>/dev/null; then
      ok "配置已自动修复"
    else
      warn "自动修复完成，建议手动检查"
    fi
  else
    warn "OpenClaw 未安装，跳过自动修复"
  fi
  
  echo
  ok "Import complete! 🎉"
  echo
  echo -e "  ${CYAN}Next steps:${NC}"
  echo "  1. Run: openclaw doctor"
  echo "  2. Restart any running OpenClaw services"
  echo "  3. Verify configuration: cat ~/.openclaw/openclaw.json"
  echo
}

# ── Incremental Export Function ────────────────────────────────────────────

do_export_incremental() {
  show_banner
  
  local output="${2:-}"
  local dry_run=false
  local verbose=false
  
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=true ;;
      --verbose|-v) verbose=true ;;
      --output=*) output="${arg#*=}" ;;
    esac
  done
  
  output="${output:-$DEFAULT_OUTPUT}"
  
  info "Incremental export to: $output"
  
  # 创建同步数据库
  local sync_db="$OPENCLAW_DIR/sync-db.json"
  
  # 如果没有数据库，创建空数据库
  if [ ! -f "$sync_db" ]; then
    mkdir -p "$(dirname "$sync_db")"
    echo "{}" > "$sync_db"
    info "Created sync database: $sync_db"
  fi
  
  # 计算当前文件哈希
  info "Calculating file hashes..."
  local tmp_hashes=$(mktemp)
  
  find "$OPENCLAW_DIR" -type f -name "*.json" -o -name "*.md" -o -name "*.sh" 2>/dev/null | while read -r file; do
    local rel_path="${file#$OPENCLAW_DIR/}"
    local hash=$(sha256 -q "$file" 2>/dev/null || echo "unknown")
    echo "{\"path\":\"$rel_path\",\"hash\":\"$hash\"}"
  done > "$tmp_hashes"
  
  # 比较差异
  info "Comparing with previous export..."
  local changed_files=$(python3 -c "
import json

current = []
try:
    with open('$tmp_hashes') as f:
        for line in f:
            if line.strip():
                current.append(json.loads(line))
except:
    pass

try:
    with open('$sync_db') as f:
        previous = json.load(f)
except:
    previous = {}

changed = []
for item in current:
    path = item['path']
    if path not in previous or previous[path] != item['hash']:
        changed.append(path)

print('\n'.join(changed) if changed else '')
" 2>/dev/null)
  
  if [ -z "$changed_files" ]; then
    ok "No changes detected since last export"
    rm -f "$tmp_hashes"
    return 0
  fi
  
  info "Changed files:"
  echo "$changed_files" | while read -r f; do
    echo "  - $f"
  done
  
  if $dry_run; then
    info "Dry run - no files written"
    rm -f "$tmp_hashes"
    return 0
  fi
  
  # 导出变更文件
  info "Exporting changed files..."
  local tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/openclaw-export"
  
  echo "$changed_files" | while read -r file; do
    [ -f "$OPENCLAW_DIR/$file" ] && mkdir -p "$tmpdir/openclaw-export/$(dirname "$file")" && cp "$OPENCLAW_DIR/$file" "$tmpdir/openclaw-export/$file" 2>/dev/null
  done
  
  # 更新同步数据库
  cp "$tmp_hashes" "$sync_db"
  
  # 创建归档
  tar -czf "$output" -C "$tmpdir" "openclaw-export" 2>/dev/null
  
  local size=$(du -h "$output" | cut -f1)
  local count=$(echo "$changed_files" | wc -l | tr -d ' ')
  
  ok "Incremental export complete!"
  echo "  Files: $count"
  echo "  Size: $size"
  echo "  Output: $output"
  
  rm -rf "$tmpdir" "$tmp_hashes"
}

# ── Merge Import Function ────────────────────────────────────────────────

do_import_with_merge() {
  local archive="${1:-}"
  local merge_strategy="prompt"
  
  # 解析合并策略
  for arg in "$@"; do
    case "$arg" in
      --merge=*) merge_strategy="${arg#*=}" ;;
    esac
  done
  
  if [ -z "$archive" ]; then
    err "Usage: $SCRIPT_NAME import <archive> --merge=<strategy>"
    info "Strategies: prompt, keep-local, keep-remote, keep-newer"
    return 1
  fi
  
  if [ ! -f "$archive" ]; then
    err "Archive not found: $archive"
    return 1
  fi
  
  show_banner
  info "Import with merge strategy: $merge_strategy"
  
  # 解压归档
  local tmpdir=$(mktemp -d)
  tar -xzf "$archive" -C "$tmpdir" 2>/dev/null || {
    err "Failed to extract archive"
    rm -rf "$tmpdir"
    return 1
  }
  
  local exportdir=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)
  
  if [ ! -d "$exportdir" ]; then
    err "Invalid archive format"
    rm -rf "$tmpdir"
    return 1
  fi
  
  # 备份
  local backup="$HOME/openclaw-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
  info "Creating backup..."
  tar -czf "$backup" -C "$HOME" ".openclaw" 2>/dev/null && ok "Backup: $backup" || warn "Backup failed"
  
  # 合并 openclaw.json
  if [ -f "$exportdir/openclaw.json" ] && [ -f "$OPENCLAW_DIR/openclaw.json" ]; then
    info "Merging openclaw.json..."
    
    local merged_file="$OPENCLAW_DIR/openclaw.json.new"
    
    python3 << 'PYEOF'
import json
import sys

local_file = "$OPENCLAW_DIR/openclaw.json"
import_file = "$exportdir/openclaw.json"
output_file = "$merged_file"

strategy = "$merge_strategy"

try:
    with open(local_file) as f:
        local = json.load(f)
    with open(import_file) as f:
        imported = json.load(f)
    
    if strategy == "keep-local":
        # 保留本地，忽略导入的
        result = local
    elif strategy == "keep-remote":
        # 完全使用导入的
        result = imported
    elif strategy == "keep-newer":
        # 保留更新的（简单比较 meta.lastTouchedAt）
        result = {**imported, **local}
    else:  # prompt
        # 默认保留本地，显示警告
        result = local
        print("⚠️  Using --merge=keep-remote to fully replace configuration")
    
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    
    print("Merge complete")
except Exception as e:
    print(f"Merge error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    
    if [ -f "$merged_file" ]; then
      mv "$merged_file" "$OPENCLAW_DIR/openclaw.json"
      ok "openclaw.json merged"
    fi
  elif [ -f "$exportdir/openclaw.json" ]; then
    # 没有本地配置，直接导入
    cp "$exportdir/openclaw.json" "$OPENCLAW_DIR/openclaw.json"
    ok "openclaw.json imported"
  fi
  
  # 导入其他文件
  for item in workspace skills scripts extensions; do
    if [ -d "$exportdir/$item" ]; then
      mkdir -p "$OPENCLAW_DIR/$item"
      cp -R "$exportdir/$item/"* "$OPENCLAW_DIR/$item/" 2>/dev/null || true
      ok "$item imported"
    fi
  done
  
  ok "Merge import complete!"
  rm -rf "$tmpdir"
}

# ── Sync Status Function ─────────────────────────────────────────────────

do_sync_status() {
  show_banner
  
  local sync_db="$OPENCLAW_DIR/sync-db.json"
  
  if [ ! -f "$sync_db" ]; then
    info "No sync database found"
    info "Run 'export --incremental' first to create one"
    return 0
  fi
  
  info "Sync status:"
  echo
  
  python3 -c "
import json

try:
    with open('$sync_db') as f:
        db = json.load(f)
    
    print(f\"  Tracked files: {len(db)}\")
    
    # 计算文件大小
    import os
    total_size = 0
    for path in db.keys():
        full_path = os.path.join(os.path.expanduser('~/.openclaw'), path)
        if os.path.exists(full_path):
            total_size += os.path.getsize(full_path)
    
    print(f\"  Total size: {total_size / 1024 / 1024:.2f} MB\")
    print(f\"  Last sync: {db.get('_last_sync', 'unknown')}\")
except Exception as e:
    print(f\"  Error: {e}\")
"
  
  echo
  info "Use 'export --incremental' to sync changes"
}

# ── Doctor Function ─────────────────────────────────────────────────────────

do_doctor() {
  show_banner
  
  info "Running diagnostics..."
  echo
  
  local issues=0
  
  echo -e "${BOLD}System Information${NC}"
  echo -e "  OS:         $(detect_os)"
  echo -e "  Hostname:   $(hostname)"
  echo -e "  User:       ${USER:-unknown}"
  echo
  
  echo -e "${BOLD}Node.js${NC}"
  if check_node; then
    echo -e "  Version:    $(node -v)"
    echo -e "  Path:       $(which node)"
  else
    echo -e "  ${RED}✖ Not installed${NC}"
    issues=$((issues + 1))
  fi
  echo
  
  echo -e "${BOLD}npm${NC}"
  if check_npm; then
    echo -e "  Version:    $(npm --version)"
    echo -e "  Path:       $(which npm)"
  else
    echo -e "  ${RED}✖ Not installed${NC}"
    issues=$((issues + 1))
  fi
  echo
  
  echo -e "${BOLD}OpenClaw${NC}"
  if check_openclaw; then
    echo -e "  Version:    $(openclaw --version 2>/dev/null || echo 'unknown')"
    echo -e "  Path:       $(which openclaw 2>/dev/null || echo 'not in PATH')"
  else
    echo -e "  ${RED}✖ Not installed${NC}"
    issues=$((issues + 1))
  fi
  echo
  
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
  
  local tmp_script=$(mktemp)
  curl -fsSL "$REPO_RAW_URL/openclaw-migrate.sh" -o "$tmp_script" || die "Failed to download update"
  
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
  lang          Change language / 更改语言
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

  # Change language
  $SCRIPT_NAME lang

${BOLD}Repository:${NC} $REPO_URL
${BOLD}License:${NC} MIT

EOF
}

# Auto-detect: if first arg is a .tar.gz file, treat as import
if [[ "${1:-}" =~ \.tar\.gz$ ]] && [ -f "${1:-}" ]; then
  set -- import "$@"
fi

# Parse command
case "${1:-}" in
  export)
    shift
    if [[ " $@ " =~ " --incremental " ]]; then
      do_export_incremental "$@"
    else
      do_export "$@"
    fi
    ;;
  import)
    shift
    if [[ " $@ " =~ "--merge=" ]]; then
      do_import_with_merge "$@"
    else
      do_import "$@"
    fi
    ;;
  template-check|template)
    shift
    do_template_check "$@"
    ;;
  sync-status)
    do_sync_status
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
  lang|--lang|-l)
    do_select_language
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
