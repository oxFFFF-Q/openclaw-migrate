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

一行命令，把你的 AI 助手搬到任何设备。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.3.0-purple.svg)]()

---

## 快速开始

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/oxFFFF-Q/openclaw-migrate/main/openclaw-migrate.sh -o openclaw-migrate.sh
chmod +x openclaw-migrate.sh

# 导出（交互式）
./openclaw-migrate.sh export

# 导入（交互式）
./openclaw-migrate.sh import
```

---

## 预设选项

选择导出内容：

- **快速** — 核心配置 + 自建技能
- **标准** — + 扩展插件 + 多 Agent
- **完整** — 全部内容
- **自定义** — 手动选择

---

## 命令

| 命令 | 说明 |
|:---|:---|
| `export` | 导出配置（交互式） |
| `import` | 导入配置（交互式） |
| `doctor` | 诊断系统环境 |
| `update` | 更新到最新版本 |

---

## 常见问题

**Q: 支持哪些系统？**
macOS (Intel/Apple Silicon)、Linux (Debian/RHEL/Arch/Alpine)、Windows (MSYS/WSL)。

**Q: 导出包含密码/Token 吗？**
默认模式只导出配置、技能和文档，不含凭证。可选完整模式包含所有内容。

**Q: 导入会覆盖现有配置吗？**
导入前自动备份现有配置到 `~/openclaw-backup-*.tar.gz`，可随时回滚。

**Q: 目标设备没有 Node.js 怎么办？**
导入时自动检测并提示安装，无需手动操作。

---

<p align="center">
  <sub>Made with ❤️ for the OpenClaw community</sub>
</p>
