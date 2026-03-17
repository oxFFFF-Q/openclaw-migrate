# openclaw-migrate

一行命令，把你的 AI 助手搬到任何设备。

## 快速开始

```bash
# 下载
curl -fsSL https://raw.githubusercontent.com/oxFFFF-Q/openclaw-migrate/main/openclaw-migrate.sh -o openclaw-migrate.sh
chmod +x openclaw-migrate.sh

# 导出（交互式）
./openclaw-migrate.sh export

# 导入（交互式）
./openclaw-migrate.sh import xxx.tar.gz
```

## 预设

| 预设 | 内容 | 大小 |
|------|------|------|
| 快速 | 核心配置 + 自建技能 | ~2MB |
| 标准 | + 扩展插件 + 多 Agent | ~5MB |
| 完整 | 全部内容（含凭证） | ~50MB |
| 自定义 | 手动选择 | 视情况 |

## 命令

- `export` - 导出配置（交互式）
- `import` - 导入配置（交互式）
- `doctor` - 诊断系统环境
- `update` - 更新到最新版本

## 语言

脚本支持英文和中文。
运行 `./openclaw-migrate.sh export` 并选择语言。

## 常见问题

**Q: 支持哪些系统？**
macOS (Intel/Apple Silicon)、Linux (Debian/RHEL/Arch/Alpine)、Windows (MSYS/WSL)。

**Q: 导出包含密码/Token 吗？**
默认模式不含凭证。完整模式包含所有内容。

**Q: 导入会覆盖现有配置吗？**
导入前自动备份到 `~/openclaw-backup-*.tar.gz`。

**Q: 目标设备没有 Node.js 怎么办？**
脚本自动检测并提示安装。

## 许可证

MIT
