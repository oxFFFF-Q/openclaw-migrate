# OpenClaw Migration Tool

跨平台 OpenClaw 配置迁移工具。

## 功能

- 🔄 **三种迁移模式**：replicate / full / skills
- 🖥️ **跨平台支持**：macOS / Linux / Windows
- 🔧 **自动安装依赖**：OpenClaw / Node.js
- 🔒 **安全备份**：导入前自动备份现有配置

## 使用方法

### 导出（源设备）

```bash
# 复刻架构模式（推荐）
./openclaw-migrate.sh export --mode=replicate

# 完整迁移
./openclaw-migrate.sh export --mode=full

# 只复制技能
./openclaw-migrate.sh export --mode=skills
```

### 导入（目标设备）

```bash
./openclaw-migrate.sh import openclaw-config-*.tar.gz
```

## 迁移模式

| 模式 | 内容 |
|---|---|
| `replicate` | 配置 + 技能 + 文档（不含记忆/凭证） |
| `full` | 全部文件 |
| `skills` | 只复制技能目录 |

## License

MIT
