```
  ____                    ____ _                 
 / __ \                  / ___| | __ ___      __ 
| |  | |_ __   ___ _ __ | |   | |/ _` \ \ /\ / / 
| |  | | '_ \ / _ \ '_ \| |   | | (_| |\ V  V /  
| |__| | |_) |  __/ | | | |___| |\__,_| \_/\_/   
 \____/| .__/ \___|_| |_|\____|_|\__,_| migrate  
       |_|                                        
```

# openclaw-migrate

**一行命令，把你的 AI 助手搬到任何设备。**

跨平台 OpenClaw 配置迁移工具 — 导出、导入、一气呵成。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](openclaw-migrate.sh)
[![Version](https://img.shields.io/badge/Version-1.1.0-purple.svg)]()

---

## ✨ 功能特性

- 🔄 **三种迁移模式** — replicate / full / skills，按需选择
- 🖥️ **全平台覆盖** — macOS (Intel/Apple Silicon) · Linux (Debian/RHEL/Arch/Alpine) · Windows (MSYS/WSL)
- 🔧 **智能依赖管理** — 自动检测并安装 Node.js 和 OpenClaw
- 🔒 **安全备份** — 导入前自动备份现有配置，可回滚
- 📋 **导出清单** — 自动生成 `manifest.json`，记录来源环境和版本信息
- 🩺 **内置诊断** — `doctor` 命令一键检查系统健康状态
- 🔃 **自更新** — `update` 命令从 GitHub 拉取最新版本
- 📦 **零依赖** — 纯 Bash 实现，无需额外安装

---

## 🚀 快速开始

**3 步完成迁移：**

```bash
# ① 下载脚本
curl -fsSL https://raw.githubusercontent.com/oxFFFF-Q/openclaw-migrate/main/openclaw-migrate.sh -o openclaw-migrate.sh
chmod +x openclaw-migrate.sh

# ② 在旧设备导出
./openclaw-migrate.sh export

# ③ 在新设备导入
./openclaw-migrate.sh import openclaw-export-*.tar.gz
```

就这么简单。✅

---

## 📖 详细用法

### 导出配置

```bash
# 推荐：复刻模式（配置 + 技能 + 文档，不含记忆和凭证）
./openclaw-migrate.sh export --mode=replicate

# 完整导出（含记忆、凭证等所有内容）
./openclaw-migrate.sh export --mode=full

# 只导出技能
./openclaw-migrate.sh export --mode=skills

# 自定义输出路径
./openclaw-migrate.sh export --output=/tmp/my-backup.tar.gz

# 预览模式（不实际创建文件）
./openclaw-migrate.sh export --dry-run --verbose
```

**导出输出示例：**
```
ℹ  Exporting in 'replicate' mode...
✔  openclaw.json
✔  Skills
✔  Scripts
✔  AGENTS.md
✔  SOUL.md

✔  Export complete!

  Output:     /Users/you/openclaw-export-20260315_143022.tar.gz
  Size:       2.1M
  Files:      47
  Mode:       replicate
```

### 导入配置

```bash
# 标准导入（会提示确认 + 自动备份）
./openclaw-migrate.sh import openclaw-export-20260315.tar.gz

# 静默导入（跳过确认）
./openclaw-migrate.sh import export.tar.gz --force

# 不备份现有配置
./openclaw-migrate.sh import export.tar.gz --no-backup
```

### 系统诊断

```bash
./openclaw-migrate.sh doctor
```

### 自更新

```bash
./openclaw-migrate.sh update
```

---

## 📊 迁移模式对比

| 模式 | 内容 | 适用场景 | 包含凭证 |
|:---:|:---|:---|:---:|
| `replicate` | 配置 + 技能 + 脚本 + 文档 | 🟢 新设备复刻（推荐） | ❌ |
| `full` | 全部文件（含记忆、凭证） | 🟡 完整备份/迁移 | ✅ |
| `skills` | 仅技能目录 | 🔵 分享技能给他人 | ❌ |

> 💡 **推荐使用 `replicate` 模式**：安全地复刻你的 AI 助手架构，不泄露敏感信息。

---

## 🔧 命令一览

| 命令 | 说明 |
|:---|:---|
| `export [--mode=MODE]` | 导出配置到 `.tar.gz` |
| `import <archive>` | 从归档文件导入配置 |
| `doctor` | 检查系统环境和依赖 |
| `version` | 显示版本号 |
| `update` | 自更新到最新版本 |
| `help` | 显示帮助信息 |

---

## ❓ 常见问题

<details>
<summary><b>Q: 支持哪些操作系统？</b></summary>
macOS (Intel & Apple Silicon)、Linux (Debian/Ubuntu/CentOS/Arch/Alpine) 和 Windows (MSYS2/Cygwin/WSL)。
</details>

<details>
<summary><b>Q: replicate 模式会导出我的密码/Token 吗？</b></summary>
不会。<code>replicate</code> 模式只导出配置文件、技能和文档，不包含 <code>credentials</code>、<code>memory</code> 或会话数据。只有 <code>full</code> 模式会包含敏感数据。
</details>

<details>
<summary><b>Q: 导入会覆盖我现有的配置吗？</b></summary>
导入前会自动备份你的现有配置到 <code>~/openclaw-backup-*.tar.gz</code>，你可以随时回滚。使用 <code>--no-backup</code> 可跳过备份。
</details>

<details>
<summary><b>Q: 目标设备没有 Node.js 怎么办？</b></summary>
导入时脚本会自动检测并提示安装 Node.js 和 OpenClaw，无需手动操作。
</details>

<details>
<summary><b>Q: 如何验证导入是否成功？</b></summary>
运行 <code>./openclaw-migrate.sh doctor</code> 检查所有依赖和配置状态。
</details>

---

## 🤝 贡献

欢迎贡献！请查看 [GitHub Issues](https://github.com/oxFFFF-Q/openclaw-migrate/issues) 了解待办事项。

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/amazing-feature`
3. 提交更改：`git commit -m 'Add amazing feature'`
4. 推送分支：`git push origin feature/amazing-feature`
5. 提交 Pull Request

---

## 📄 License

[MIT](LICENSE) © [oxFFFF-Q](https://github.com/oxFFFF-Q)

---

## 🙏 致谢

- [OpenClaw](https://github.com/nicepkg/openclaw) — 让 AI 助手真正属于你
- 所有提交 Issue 和 PR 的贡献者们

---

<p align="center">
  <sub>Made with ❤️ for the OpenClaw community</sub>
</p>
