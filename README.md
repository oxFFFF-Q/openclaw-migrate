# openclaw-migrate

One command to migrate your AI assistant to any device.

## Quick Start

```bash
# Download
curl -fsSL https://raw.githubusercontent.com/oxFFFF-Q/openclaw-migrate/main/openclaw-migrate.sh -o openclaw-migrate.sh
chmod +x openclaw-migrate.sh

# Export (interactive)
./openclaw-migrate.sh export

# Import (interactive)
./openclaw-migrate.sh import xxx.tar.gz
```

## Presets

| Preset | Content | Size |
|--------|---------|------|
| Quick | Core config + custom skills | ~2MB |
| Standard | + Extensions + Multi-Agent | ~5MB |
| Full | Everything including credentials | ~50MB |
| Custom | Manual selection | Varies |

## Commands

- `export` - Export (interactive)
- `import` - Import (interactive)
- `doctor` - Diagnostics
- `update` - Self-update

## Language

The script supports English and Chinese (中文).
Run `./openclaw-migrate.sh export` and select your preferred language.

## FAQ

**Q: What systems are supported?**
macOS (Intel/Apple Silicon), Linux (Debian/RHEL/Arch/Alpine), Windows (MSYS/WSL).

**Q: Does export include passwords/tokens?**
Default mode excludes credentials. Full mode includes everything.

**Q: Will import overwrite existing config?**
Backups are automatically created to `~/openclaw-backup-*.tar.gz` before import.

**Q: What if target device has no Node.js?**
The script detects and prompts for installation automatically.

## License

MIT
