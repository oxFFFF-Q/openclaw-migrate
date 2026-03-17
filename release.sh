#!/usr/bin/env bash
#
# OpenClaw Migration Tool - Release Script
# Creates versioned release archives with checksums
#
# Usage:
#   ./release.sh [version]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get version
if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    VERSION=$(cat VERSION 2>/dev/null || echo "1.0.0")
fi

# Remove 'v' prefix if present
VERSION="${VERSION#v}"

log_info "Creating release for version: v$VERSION"

# Create archive name
ARCHIVE_NAME="openclaw-migrate-v${VERSION}.tar.gz"
CHECKSUM_NAME="openclaw-migrate-v${VERSION}.sha256"

# Files to include in release
FILES=(
    "openclaw-migrate.sh"
    "openclaw-migrate.ps1"
    "README.md"
    "README_CN.md"
    "CHANGELOG.md"
    "LICENSE"
    "VERSION"
    ".gitignore"
    "CONTRIBUTING.md"
    "SECURITY.md"
    "CODEOWNERS"
)

# Check all files exist
log_info "Checking files..."
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        log_error "Missing file: $file"
        exit 1
    fi
done

# Create archive
log_info "Creating archive: $ARCHIVE_NAME"
tar -czf "$ARCHIVE_NAME" "${FILES[@]}"

# Generate SHA256 checksum
log_info "Generating SHA256 checksum..."
if command -v sha256sum &>/dev/null; then
    sha256sum "$ARCHIVE_NAME" > "$CHECKSUM_NAME"
else
    # macOS fallback
    shasum -a 256 "$ARCHIVE_NAME" > "$CHECKSUM_NAME"
fi

# Update versions.json
log_info "Updating versions.json..."
python3 << PYTHON_SCRIPT
import json
from datetime import datetime, timezone, timedelta
import os

tz = timezone(timedelta(hours=8))
version = "$VERSION"

versions_file = "versions.json"
download_url = f"https://github.com/oxFFFF-Q/openclaw-migrate/releases/download/v{version}/openclaw-migrate-v{version}.tar.gz"
checksum_url = f"https://github.com/oxFFFF-Q/openclaw-migrate/releases/download/v{version}/openclaw-migrate-v{version}.sha256"

if os.path.exists(versions_file):
    with open(versions_file, 'r') as f:
        data = json.load(f)
    
    # Check if version already exists
    exists = any(v['version'] == version for v in data.get('versions', []))
    if not exists:
        new_entry = {
            "version": version,
            "date": datetime.now(tz).strftime('%Y-%m-%d'),
            "download_url": download_url,
            "checksum_url": checksum_url,
            "notes": f"Release v{version}"
        }
        data['versions'].insert(0, new_entry)
        data['latest'] = version
        
        with open(versions_file, 'w') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"Added version {version} to versions.json")
    else:
        print(f"Version {version} already exists in versions.json")
else:
    data = {
        "latest": version,
        "versions": [
            {
                "version": version,
                "date": datetime.now(tz).strftime('%Y-%m-%d'),
                "download_url": download_url,
                "checksum_url": checksum_url,
                "notes": f"Release v{version}"
            }
        ]
    }
    
    with open(versions_file, 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f"Created versions.json with version {version}")
PYTHON_SCRIPT

# Summary
echo
log_info "Release v$VERSION created successfully!"
echo
echo "Artifacts:"
echo "  - $ARCHIVE_NAME"
echo "  - $CHECKSUM_NAME"
echo
echo "Checksum:"
cat "$CHECKSUM_NAME"
echo

# Update VERSION file
echo "$VERSION" > VERSION
log_info "Updated VERSION file to $VERSION"
