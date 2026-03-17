# openclaw-migrate

[![GitHub release](https://img.shields.io/github/release/oxFFFF-Q/openclaw-migrate.svg)](https://github.com/oxFFFF-Q/openclaw-migrate/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

**Cross-platform migration tool for OpenClaw.** Export on one system, import on another — everything works out of the box.

---

## Features

- ✅ **Full Backup**: Workspace, config, credentials, sessions, cron, scripts, agents, extensions
- ✅ **Cross-Platform Path Conversion**: macOS → Ubuntu, Ubuntu → macOS, any to any
- ✅ **Zero Re-pairing**: Channels reconnect automatically after restore
- ✅ **Gateway Token Preservation**: Prevents dashboard token mismatch
- ✅ **Old Archive Compatible**: Auto-detects and converts paths from legacy backups
- ✅ **Safe Restore**: Dry-run mode, auto-backup before overwrite

---

## Requirements

| System | Requirements |
|--------|-------------|
| **macOS** | 10.15+ (Catalina or later) |
| **Ubuntu/Debian** | 18.04+ |
| **Windows** | Windows 10+ with WSL2 |
| **Raspberry Pi** | Raspberry Pi OS (64-bit) |

**Prerequisites**:
- [OpenClaw](https://openclaw.ai) must be installed on both source and target systems
- Bash 4.0+ (pre-installed on macOS/Linux)

---

## Installation

### Quick Install (Recommended)

```bash
# Download the latest release
curl -fsSL https://raw.githubusercontent.com/oxFFFF-Q/openclaw-migrate/main/openclaw-migrate.sh -o openclaw-migrate.sh

# Make it executable
chmod +x openclaw-migrate.sh

# Optional: Move to PATH for easy access
sudo mv openclaw-migrate.sh /usr/local/bin/openclaw-migrate
```

### Manual Install (Git)

```bash
# Clone the repository
git clone https://github.com/oxFFFF-Q/openclaw-migrate.git
cd openclaw-migrate

# The scripts are ready to use
./backup.sh --help
./restore.sh --help
```

---

## Quick Start

### Step 1: Export on Source System

```bash
# On your Mac (or any source system)
cd openclaw-migrate

# Create a backup
./backup.sh ~/openclaw-backup.tar.gz
```

This creates a backup archive with:
- All workspace files (MEMORY.md, skills, agents)
- OpenClaw configuration (openclaw.json)
- Credentials and channel pairing state
- Session history and cron jobs
- **MANIFEST.json** with `home_dir` for cross-platform restore

### Step 2: Transfer to Target System

Transfer the backup file to your target system using any method:
- USB drive
- Network transfer (scp, rsync)
- Cloud storage (Google Drive, Dropbox, etc.)
- Any file transfer method you prefer

### Step 3: Import on Target System

```bash
# On your Ubuntu (or any target system)
cd openclaw-migrate

# Preview what will be restored (recommended)
./restore.sh ~/openclaw-backup.tar.gz --dry-run

# Perform the actual restore
./restore.sh ~/openclaw-backup.tar.gz

# Verify everything works
openclaw doctor
openclaw gateway status
```

**That's it!** All paths are automatically converted, channels reconnect, no re-pairing needed.

---

## What Gets Backed Up

| Component | Description |
|-----------|-------------|
| 🧠 **Workspace** | MEMORY.md, skills, agents, SOUL.md, USER.md, PLANS/ |
| ⚙️ **Config** | openclaw.json (bot tokens, API keys, model config) |
| 🔑 **Credentials** | Channel pairing state — no re-pairing after restore |
| 📜 **Sessions** | Full agent conversation history |
| ⏰ **Cron Jobs** | All scheduled tasks |
| 🛡️ **Scripts** | Guardian, watchdog, start-gateway |
| 🤖 **Agents** | Multi-agent configurations and workspaces |
| 🔌 **Extensions** | Installed OpenClaw extensions |

---

## Usage

### Backup (Export)

```bash
# Basic backup
./backup.sh ~/openclaw-backup.tar.gz

# The archive will include:
# - All OpenClaw data
# - MANIFEST.json with home_dir field for cross-platform restore
```

### Restore (Import)

```bash
# Always preview first
./restore.sh ~/backup.tar.gz --dry-run

# Restore with automatic path conversion
./restore.sh ~/backup.tar.gz

# The restore process:
# 1. Validates the archive
# 2. Backs up current ~/.openclaw
# 3. Restores all files
# 4. Converts paths to match current system
# 5. Preserves gateway token
# 6. Restarts OpenClaw Gateway
```

### Diagnostics

```bash
# Check system compatibility
./openclaw-migrate.sh doctor

# View current OpenClaw status
openclaw gateway status
```

---

## Cross-Platform Examples

### macOS → Ubuntu

```bash
# === On macOS ===
./backup.sh ~/my-openclaw.tar.gz

# Transfer to Ubuntu (your preferred method)
# ...

# === On Ubuntu ===
./restore.sh ~/my-openclaw.tar.gz --dry-run  # Preview
./restore.sh ~/my-openclaw.tar.gz           # Restore

# Paths like /Users/eva/.openclaw/... 
# are automatically converted to /home/ubuntu/.openclaw/...
```

### Ubuntu → macOS

```bash
# === On Ubuntu ===
./backup.sh ~/my-openclaw.tar.gz

# Transfer to macOS (your preferred method)
# ...

# === On macOS ===
./restore.sh ~/my-openclaw.tar.gz --dry-run  # Preview
./restore.sh ~/my-openclaw.tar.gz           # Restore

# Paths like /home/ubuntu/.openclaw/...
# are automatically converted to /Users/eva/.openclaw/...
```

### Raspberry Pi → Mac

```bash
# Works the same way!
# Pi paths: /home/pi/.openclaw/...
# Mac paths: /Users/eva/.openclaw/...
```

---

## Path Conversion Details

The tool automatically converts these path types:

| Source Pattern | Target Pattern |
|---------------|----------------|
| `/Users/xxx/.openclaw/...` | `$HOME/.openclaw/...` |
| `/home/xxx/.openclaw/...` | `$HOME/.openclaw/...` |
| `C:\Users\xxx\.openclaw\...` | `$HOME/.openclaw/...` (WSL) |

**Files with path conversion:**
- `openclaw.json` (JSON-aware recursive conversion)
- `*.md` files in workspace
- `*.sh` scripts
- `agents/*.json` configurations
- `cron/*.json` scheduled tasks

---

## Security Notes

⚠️ **Backup archives contain sensitive data**:
- Bot tokens
- API keys
- Channel credentials
- Session history

**Best practices:**
- Always use `--dry-run` before restore
- Keep backups in secure locations
- Use `chmod 600` on backup files (applied automatically)
- Don't expose backup server to public internet

---

## Troubleshooting

### "OpenClaw not found"

```bash
# Install OpenClaw first
curl -fsSL https://openclaw.ai/install.sh | bash
```

### "Permission denied"

```bash
# Make scripts executable
chmod +x backup.sh restore.sh path-convert.sh
```

### "Paths not converted"

This happens with very old archives. The tool will:
1. Try to read `home_dir` from MANIFEST.json
2. If not found, infer from openclaw.json content
3. If still not found, warn and skip conversion

```bash
# Manual fix if needed
openclaw doctor --fix
```

### "Gateway token mismatch"

This shouldn't happen with v3.0.0+, as the tool preserves the target system's gateway token. If you see this:

```bash
# Get the current token
cat ~/.openclaw/openclaw.json | grep -A2 '"auth"'

# Update in OpenClaw Dashboard settings
```

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

## Contributing

Issues and pull requests are welcome! See [GitHub](https://github.com/oxFFFF-Q/openclaw-migrate).

---

## License

[MIT License](LICENSE)

---

## Credits

- Based on [openclaw-backup](https://github.com/LeoYeAI/openclaw-backup) (944⭐) by LeoYeAI
- Path conversion design by Jarvis (architect)
- Implementation by Walle (builder)
- Testing by Walle + Otto (ops)
