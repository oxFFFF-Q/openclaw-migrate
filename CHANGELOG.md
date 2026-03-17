# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-03-17

### Added
- 🚀 Incremental export (`--incremental`) - only export changed files
- 🔄 Sync status command (`sync-status`) - track file changes  
- 📦 Merge import (`--merge=`) - smart merge (keep-local/remote/newer)
- 🛡️ JSON validation on import - prevent corruption
- ⚡ Atomic import operation - temp file then replace
- 🔧 Version management (`versions`, `use`)
- 📥 install.sh - one-click install
- 📦 release.sh + GitHub Actions automation

### Fixed
- Critical: openclaw.json validation before import

## [1.2.0] - 2026-03-16

### Added
- 📦 `--install-deps` flag for import command - auto-install missing OpenClaw plugins
- 🔍 `check_plugin_exists()` function to detect installed plugins
- 🔧 `install_plugin()` function to install missing plugins
- 🤖 `install_missing_plugins()` to batch install all missing dependencies

### Changed
- Import command now supports optional dependency auto-installation
- Better error messages when plugins are missing

## [1.1.0] - 2026-03-15

### Added
- 🎨 Beautiful ASCII banner and colored output
- 📊 Progress indicators and detailed logging
- 🔍 `doctor` command for system diagnostics
- 🔄 `update` command for self-updating
- 📝 Detailed manifest.json with system info
- 🛡️ Enhanced error handling and validation
- 📦 Support for PLANS directory in replicate mode
- 🔧 Auto-install Node.js and OpenClaw when missing
- 📋 `--dry-run` mode for export preview
- 📝 JSON formatting for manifest output (jq/python3)
- 🖥️ Extended OS detection (arch, alpine, windows)

### Improved
- Better file counting and size reporting
- More comprehensive help messages
- Clearer success/failure feedback
- Backup confirmation before import

## [1.0.0] - 2026-03-15

### Added
- Initial release
- Three export modes: `replicate`, `full`, `skills`
- Cross-platform support (macOS, Linux, Windows)
- Automatic dependency detection
- Safe import with backup
- manifest.json generation
- Basic documentation
