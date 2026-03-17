# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-03-17

### Added (基于 openclaw-backup 重构)
- 🎯 **完整备份功能**: 基于 openclaw-backup (944⭐) 重构
  - 备份 10 类数据: workspace, config, credentials, sessions, cron, scripts, devices, identity, agent, channels
  - Gateway token 保留机制（防止 Dashboard token mismatch）
  - 自动备份当前状态（pre-restore snapshot）
- 🔄 **跨平台路径转换**: 完整路径转换方案
  - 路径变量化（导出）: 将绝对路径记录到 MANIFEST.json 的 `home_dir` 字段
  - 路径本地化（导入）: 自动转换为目标系统路径
  - 支持 macOS → Ubuntu / Ubuntu → macOS / 同系统不同用户
  - 旧归档兼容（自动推断源路径）
  - 覆盖文件: openclaw.json, *.md, *.sh, agents/*.json, cron/*.json
- 🛡️ **安全性增强**:
  - dry-run 模式（预览不执行）
  - 二进制文件检测（跳过非文本文件）
  - JSON 格式验证（防止损坏）
  - 错误处理（set -euo pipefail）

### Changed
- 重构为基于 openclaw-backup 的模块化架构
- backup.sh: 增加路径变量化，MANIFEST.json 包含 home_dir
- restore.sh: 集成路径转换，在步骤 9 和 gateway restart 之间

### Tested
- ✅ 单元测试: 5/5 通过（macOS→Ubuntu, Ubuntu→macOS, 旧归档推断, 空路径, JSON递归）
- ✅ 集成测试: 15/15 通过（导出/导入, 路径转换, 安全性）

### Credits
- 基于 [LeoYeAI/openclaw-backup](https://github.com/LeoYeAI/openclaw-backup) (944⭐)
- 路径转换方案由贾维斯（architect）设计
- 实现由瓦力（builder）完成
- 测试由瓦力 + 奥托（ops）验证

## [2.0.0] - 2026-03-17

### Added (方案 A: 导出/导入双向路径处理)
- 🎯 **导出时路径变量化**: 将 `/Users/eva/.openclaw/...` 转换为 `${OPENCLAW_HOME}/...`
- 🎯 **导入时变量本地化**: 将 `${OPENCLAW_HOME}/...` 转换为当前系统路径
- 🔄 **兼容旧归档**: 仍支持绝对路径转换（向后兼容）

### Changed
- 归档完全平台无关，跨系统迁移更可靠

### Fixed
- 修复 macOS → Ubuntu 路径不兼容问题

## [1.7.0] - 2026-03-17

### Added (关键修复！)
- 🧹 **智能路径转换**: 自动将 macOS 路径转换为当前系统路径
  - `/Users/eva/.openclaw/...` → `/home/ubuntu/.openclaw/...`
  - 支持跨平台一键迁移
- 🔄 **自动检测源/目标系统**: 从 manifest 或配置文件推断

### Changed
- 路径转换在导入时自动执行，无需手动 doctor --fix

## [1.6.0] - 2026-03-17

### Added (A+B+C 完整方案)
- 🛡️ **移除危险选项**: 取消"完全覆盖"模式
- 🧹 **配置清洗**: 检测端口冲突、路径不兼容
- 🛠️ **自动修复**: 导入后自动运行 openclaw doctor --fix

### Changed
- 交互简化为 3 选项：智能合并/仅导入文件/取消
- 智能合并：保留本地系统配置，合并用户数据

## [1.5.2] - 2026-03-17

### Fixed
- 🐛 修复重复交互问题：已选择合并策略后跳过后续"是否导入"询问

## [1.5.1] - 2026-03-17

### Added
- 🧠 智能导入：自动检测 OpenClaw 安装状态
- 📦 新系统：支持一键安装 OpenClaw 并导入配置
- 🔄 已安装：提供合并/替换/保留本地三种选项
- 🎯 统一用法：只需传归档文件路径即可

### Changed
- 导入命令不再需要 `import` 关键字（自动检测 .tar.gz 文件）

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
