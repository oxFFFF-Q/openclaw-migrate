#!/usr/bin/env bash
#
# OpenClaw Migration Tool - One-Click Install Script
# Supports macOS and Linux
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/oxFFFF-Q/openclaw-migrate/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/oxFFFF-Q/openclaw-migrate/main/install.sh | bash -s -- --version=1.3.0
#

set -euo pipefail

# Configuration
REPO_OWNER="oxFFFF-Q"
REPO_NAME="openclaw-migrate"
SCRIPT_NAME="openclaw-migrate"
INSTALL_DIR="/usr/local/bin"
VERSION_FILE="$HOME/.openclaw-migrate-version"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        *)        echo "unknown" ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64)   echo "x86_64" ;;
        arm64|aarch64) echo "arm64" ;;
        *)        echo "unknown" ;;
    esac
}

# Check dependencies
check_dependencies() {
    log_step "Checking dependencies..."
    
    local missing=()
    
    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi
    
    if ! command -v tar &>/dev/null; then
        missing+=("tar")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Please install them and try again."
        exit 1
    fi
    
    log_info "All dependencies satisfied"
}

# Get latest version from GitHub
get_latest_version() {
    local version
    version=$(curl -fsSL "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest" | \
        python3 -c "import sys, json; print(json.load(sys.stdin).get('tag_name', '').lstrip('v'))" 2>/dev/null || echo "")
    
    if [ -z "$version" ]; then
        log_error "Failed to fetch latest version"
        exit 1
    fi
    
    echo "$version"
}

# Get specific version
get_version() {
    local version="$1"
    
    # Validate version exists by checking releases
    local exists
    exists=$(curl -fsSL "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/v${version}" | \
        python3 -c "import sys, json; print(json.load(sys.stdin).get('tag_name', ''))" 2>/dev/null || echo "")
    
    if [ -z "$exists" ]; then
        log_error "Version v$version not found"
        log_info "Available versions can be found at: https://github.com/${REPO_OWNER}/${REPO_NAME}/releases"
        exit 1
    fi
    
    echo "$version"
}

# Download and install version
install_version() {
    local version="$1"
    local download_url="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${version}/${SCRIPT_NAME}-v${version}.tar.gz"
    local checksum_url="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${version}/${SCRIPT_NAME}-v${version}.sha256"
    
    log_step "Downloading openclaw-migrate v$version..."
    
    # Create temp directory
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Download archive
    local archive="${temp_dir}/${SCRIPT_NAME}-v${version}.tar.gz"
    if ! curl -fsSL "$download_url" -o "$archive"; then
        log_error "Failed to download version $version"
        log_info "URL: $download_url"
        exit 1
    fi
    
    # Download checksum
    local checksum_file="${temp_dir}/${SCRIPT_NAME}-v${version}.sha256"
    if ! curl -fsSL "$checksum_url" -o "$checksum_file" 2>/dev/null; then
        log_warn "Checksum file not found, skipping verification"
    else
        log_step "Verifying checksum..."
        cd "$temp_dir"
        # Use sha256sum if available, otherwise shasum for macOS
        if command -v sha256sum &>/dev/null; then
            if ! sha256sum -c "$checksum_file" --status; then
                log_error "Checksum verification failed!"
                exit 1
            fi
        else
            # macOS fallback
            if ! shasum -a 256 -c "$checksum_file" --status 2>/dev/null; then
                log_error "Checksum verification failed!"
                exit 1
            fi
        fi
        log_info "Checksum verified"
    fi
    
    # Extract
    log_step "Extracting archive..."
    tar -xzf "$archive" -C "$temp_dir"
    
    # Check if script exists
    if [ ! -f "${temp_dir}/${SCRIPT_NAME}.sh" ]; then
        log_error "Script not found in archive"
        exit 1
    fi
    
    # Create OpenClaw directory if needed
    mkdir -p "$HOME/.openclaw"
    
    # Install
    log_step "Installing to $INSTALL_DIR..."
    
    # Check write permission
    if [ ! -w "$INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR" ]; then
        log_warn "Cannot write to $INSTALL_DIR, using ~/bin instead"
        INSTALL_DIR="$HOME/bin"
        mkdir -p "$INSTALL_DIR"
    fi
    
    # Copy script
    cp "${temp_dir}/${SCRIPT_NAME}.sh" "${INSTALL_DIR}/${SCRIPT_NAME}"
    chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"
    
    # Save version
    echo "$version" > "$VERSION_FILE"
    
    log_info "Installed openclaw-migrate v$version"
    log_info "Location: ${INSTALL_DIR}/${SCRIPT_NAME}"
    
    # Verify installation
    if command -v "$SCRIPT_NAME" &>/dev/null; then
        log_info "Run '$SCRIPT_NAME version' to verify"
    else
        log_info "Add $INSTALL_DIR to your PATH if not already added"
    fi
}

# Parse arguments
parse_args() {
    local version=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version=*)
                version="${1#*=}"
                shift
                ;;
            --version)
                version="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--version=VERSION]"
                echo ""
                echo "Options:"
                echo "  --version=VERSION  Install specific version"
                echo "  --help, -h          Show this help"
                echo ""
                echo "Examples:"
                echo "  # Install latest version"
                echo "  curl -fsSL ... | bash"
                echo ""
                echo "  # Install specific version"
                echo "  curl -fsSL ... | bash -s -- --version=1.3.0"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo "$version"
}

# Main
main() {
    echo
    log_info "OpenClaw Migration Tool - Installer"
    echo
    
    # Check OS
    local os
    os=$(detect_os)
    log_info "Detected OS: $os"
    
    # Check dependencies
    check_dependencies
    
    # Parse version from args
    local version
    version=$(parse_args "$@")
    
    # Get version
    if [ -n "$version" ]; then
        version=$(get_version "$version")
    else
        version=$(get_latest_version)
        log_info "Latest version: v$version"
    fi
    
    # Install
    install_version "$version"
    
    echo
    log_info "Installation complete!"
}

main "$@"
