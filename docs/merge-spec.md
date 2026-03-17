# 合并策略规范 (Merge Strategy Specification)

> OpenClaw 配置智能合并引擎设计文档

## 1. 概述

本规范定义了配置合并的核心策略，用于处理不同来源配置的智能合并场景。

### 1.1 设计目标

- **数据安全** - 不丢失任何有效配置
- **冲突透明** - 明确标识和处理冲突
- **策略灵活** - 支持多种合并模式
- **报告清晰** - 生成可读的合并报告

---

## 2. 合并规则详解

### 2.1 数据类型处理

#### 2.1.1 原始类型 (Primitive)

| 类型 | 合并策略 | 说明 |
|------|----------|------|
| `null` | **replace** | 空值总是被非空值替换 |
| `boolean` | **replace** | 布尔值完全替换 |
| `number` | **replace** | 数值完全替换 |
| `string` | **replace** | 字符串完全替换 |

#### 2.1.2 复合类型 (Composite)

| 类型 | 默认策略 | 可选策略 |
|------|----------|----------|
| `object` | **deep_merge** | shallow, replace |
| `array` | **unique_merge** | replace, concat |
| 其他 | **replace** | - |

### 2.2 对象合并规则

#### 深度合并 (deep_merge) - 默认

```json
// base.json
{
  "database": {
    "host": "localhost",
    "port": 5432,
    "pool": 10
  },
  "logging": {
    "level": "info"
  }
}

// override.json
{
  "database": {
    "port": 5433
  },
  "logging": {
    "level": "debug",
    "file": "/var/log/app.log"
  }
}

// 合并结果
{
  "database": {
    "host": "localhost",    // 保留 base
    "port": 5433,          // 覆盖
    "pool": 10             // 保留 base
  },
  "logging": {
    "level": "debug",      // 覆盖
    "file": "/var/log/app.log"  // 新增
  }
}
```

#### 浅层合并 (shallow_merge)

```json
// 仅合并顶层键，嵌套对象整体替换
{
  "database": { ...entire object replaced... },
  "logging": { ...entire object replaced... }
}
```

### 2.3 数组合并规则

#### 2.3.1 去重合并 (unique_merge) - 默认

```bash
# base: ["a", "b", "c"]
# override: ["b", "c", "d"]

# 结果: ["a", "b", "c", "d"]
# 去重策略: 基于值唯一
```

#### 2.3.2 追加合并 (concat)

```bash
# base: ["a", "b"]
# override: ["c", "d"]

# 结果: ["a", "b", "c", "d"]
```

#### 2.3.3 替换合并 (replace)

```bash
# base: ["a", "b"]
# override: ["c", "d"]

# 结果: ["c", "d"]
```

#### 2.3.4 对象数组合并 (特殊)

```json
// base
{
  "users": [
    {"id": 1, "name": "Alice", "role": "admin"},
    {"id": 2, "name": "Bob", "role": "user"}
  ]
}

// override
{
  "users": [
    {"id": 2, "role": "superuser"},
    {"id": 3, "name": "Carol", "role": "user"}
  ]
}

// 结果 (基于 id 匹配)
{
  "users": [
    {"id": 1, "name": "Alice", "role": "admin"},     // 保留
    {"id": 2, "name": "Bob", "role": "superuser"},  // 合并
    {"id": 3, "name": "Carol", "role": "user"}      // 新增
  ]
}
```

---

## 3. 冲突检测逻辑

### 3.1 冲突类型

| 冲突类型 | 代码 | 说明 |
|----------|------|------|
| UPDATE | `U` | 修改了已有值 |
| ADD | `A` | 新增了键 |
| DELETE | `D` | 删除了键 |
| TYPE_CHANGE | `T` | 类型改变 |

### 3.2 冲突检测算法

```bash
# ═══════════════════════════════════════════════════════════════
# 冲突检测
# ═══════════════════════════════════════════════════════════════

# 检测两个 JSON 值的冲突
# 用法: detect_conflict "base_value" "override_value"
detect_conflict() {
    local base="$1"
    local override="$2"
    
    # 类型检测
    local base_type override_type
    base_type=$(json_type "$base")
    override_type=$(json_type "$override")
    
    # 类型冲突
    if [[ "$base_type" != "$override_type" ]]; then
        echo "T|$base_type->$override_type"
        return
    fi
    
    # 对象递归检测
    if [[ "$base_type" == "object" ]]; then
        local conflicts
        conflicts=$(detect_object_conflict "$base" "$override")
        if [[ -n "$conflicts" ]]; then
            echo "$conflicts"
        fi
        return
    fi
    
    # 数组检测 (检查新增元素)
    if [[ "$base_type" == "array" ]]; then
        local new_items
        new_items=$(array_detect_new "$base" "$override")
        if [[ -n "$new_items" ]]; then
            echo "A|$new_items"
        fi
        return
    fi
    
    # 值比较
    if [[ "$base" != "$override" ]]; then
        echo "U|$base->$override"
    fi
}

# 对象冲突递归检测
detect_object_conflict() {
    local base="$1"
    local override="$2"
    local result=""
    
    # 获取所有键
    local base_keys override_keys all_keys
    base_keys=$(json_keys "$base")
    override_keys=$(json_keys "$override")
    
    # 检测删除和更新
    for key in $base_keys; do
        if ! json_has_key "$override" "$key"; then
            result+="D:$key|"
        else
            local base_val override_val conflict
            base_val=$(json_get "$base" "$key")
            override_val=$(json_get "$override" "$key")
            conflict=$(detect_conflict "$base_val" "$override_val")
            if [[ -n "$conflict" ]]; then
                result+="$conflict at $key|"
            fi
        fi
    done
    
    # 检测新增
    for key in $override_keys; do
        if ! json_has_key "$base" "$key"; then
            result+="A:$key|"
        fi
    done
    
    echo "$result"
}
```

### 3.3 冲突解决策略

#### 策略对比

| 策略 | 符号 | 行为 | 适用场景 |
|------|------|------|----------|
| **prefer_base** | `>` | 保留基础配置 | 生产配置优先 |
| **prefer_override** | `<` | 保留覆盖配置 | 用户设置优先 |
| **merge** | `M` | 智能合并 | 组合配置 |
| **prompt** | `?` | 交互式询问 | 需人工确认 |
| **fail** | `!` | 冲突报错 | 严格模式 |

#### 策略应用示例

```bash
# CLI 参数指定
--strategy=prefer_override    # 默认
--strategy=prefer_base
--strategy=merge
--strategy=prompt

# 配置文件指定
{
  "merge_strategy": {
    "default": "prefer_override",
    "paths": {
      "database.password": "prefer_base",
      "plugins": "merge"
    }
  }
}

# 按路径指定不同策略
--strategy "database:=prefer_base" \
--strategy "plugins:=merge" \
--strategy "user_settings:=prefer_override"
```

---

## 4. 合并报告格式

### 4.1 报告结构

```json
{
  "merge_report": {
    "version": "1.0",
    "timestamp": "2026-03-17T08:51:00Z",
    "base_file": "base.json",
    "override_file": "user.json",
    "strategy": "prefer_override",
    "summary": {
      "total_keys": 42,
      "unchanged": 35,
      "modified": 5,
      "added": 2,
      "deleted": 0,
      "conflicts": 0
    },
    "changes": [
      {
        "path": "database.port",
        "type": "modified",
        "base_value": 5432,
        "override_value": 5433,
        "result_value": 5433,
        "strategy_used": "prefer_override"
      },
      {
        "path": "plugins",
        "type": "modified",
        "merge_type": "array_unique",
        "added_items": ["new_plugin"],
        "removed_items": []
      }
    ],
    "conflicts": [],
    "warnings": [
      {
        "path": "database.host",
        "message": "类型改变: string -> number"
      }
    ]
  }
}
```

### 4.2 人类可读报告

```
══════════════════════════════════════════════════════════
                    合并报告
══════════════════════════════════════════════════════════

基础文件:  base.json
覆盖文件:  user.json
合并策略:  prefer_override (用户配置优先)

──────────────────────────────────────────────────────────
                         摘要
──────────────────────────────────────────────────────────
  键总数:      42
  未修改:      35  ████████████████████
  修改:        5   ██
  新增:        2   
  删除:        0   
  冲突:        0   

──────────────────────────────────────────────────────────
                       变更详情
──────────────────────────────────────────────────────────

[修改] database.port
  5432 → 5433

[修改] logging.level  
  "info" → "debug"

[新增] logging.file
  + "/var/log/openclaw.log"

[新增] plugins
  + ["new_skill", "custom_extension"]

──────────────────────────────────────────────────────────
                       警告
──────────────────────────────────────────────────────────

[!] database.host
    类型改变: string → number (已自动转换)

──────────────────────────────────────────────────────────
                    ✅ 合并完成
══════════════════════════════════════════════════════════
```

---

## 5. 实现示例

### 5.1 核心合并函数

```bash
# ═══════════════════════════════════════════════════════════════
# JSON 合并引擎
# ═══════════════════════════════════════════════════════════════

# 主合并函数
# 用法: json_merge "base.json" "override.json" [strategy]
json_merge() {
    local base_file="$1"
    local override_file="$2"
    local strategy="${3:-prefer_override}"
    
    local base override result
    
    # 读取文件
    base=$(cat "$base_file")
    override=$(cat "$override_file")
    
    # 类型检查
    if ! json_valid "$base" || ! json_valid "$override"; then
        echo "错误: 无效的 JSON 文件" >&2
        return 1
    fi
    
    # 执行合并
    result=$(json_merge_impl "$base" "$override" "$strategy")
    
    # 生成报告
    local report
    report=$(generate_merge_report "$base_file" "$override_file" "$strategy")
    
    # 输出
    echo "$result"
    
    # 可选: 保存报告
    # echo "$report" > "merge-report-$(date +%s).json"
}

# 深度合并实现
json_merge_impl() {
    local base="$1"
    local override="$2"
    local strategy="$3"
    
    local base_type override_type
    base_type=$(json_type "$base")
    override_type=$(json_type "$override")
    
    # 类型不匹配: 根据策略处理
    if [[ "$base_type" != "$override_type" ]]; then
        case "$strategy" in
            prefer_override)  echo "$override"; return ;;
            prefer_base)     echo "$base"; return ;;
            fail)
                echo "错误: 类型冲突" >&2
                return 1
                ;;
        esac
    fi
    
    # 两者都是对象: 深度合并
    if [[ "$base_type" == "object" && "$override_type" == "object" ]]; then
        json_merge_objects "$base" "$override" "$strategy"
        return
    fi
    
    # 两者都是数组: 数组合并
    if [[ "$base_type" == "array" && "$override_type" == "array" ]]; then
        json_merge_arrays "$base" "$override" "unique"
        return
    fi
    
    # 其他情况: 替换
    echo "$override"
}

# 对象深度合并
json_merge_objects() {
    local base="$1"
    local override="$2"
    local strategy="$3"
    
    local result="{"
    local first=true
    
    # 获取所有唯一键
    local all_keys
    all_keys=$(jq -s '.[0] * .[1] | keys' -c <(echo "$base") <(echo "$override"))
    
    for key in $(echo "$all_keys" | jq -r '.[]'); do
        $first || result+=","
        first=false
        
        local base_val override_val new_val
        base_val=$(echo "$base" | jq -r ".$key")
        override_val=$(echo "$override" | jq -r ".$key")
        
        # 键不存在于 base: 使用 override
        if [[ "$base_val" == "null" ]]; then
            new_val="$override_val"
        # 键不存在于 override: 使用 base
        elif [[ "$override_val" == "null" ]]; then
            new_val="$base_val"
        # 都存在: 递归合并
        else
            new_val=$(json_merge_impl "$base_val" "$override_val" "$strategy")
        fi
        
        result+="\"$key\": $new_val"
    done
    
    result+="}"
    echo "$result"
}
```

### 5.2 数组合并

```bash
# 数组合并 (去重)
# 用法: json_merge_arrays "array1" "array2" [mode]
# mode: unique(默认) | concat | replace
json_merge_arrays() {
    local arr1="$1"
    local arr2="$2"
    local mode="${3:-unique}"
    
    case "$mode" in
        unique)
            # 合并并去重
            echo "$arr1 $arr2" | jq -s 'flatten | unique'
            ;;
        concat)
            # 简单拼接
            echo "$arr1 $arr2" | jq -s 'flatten'
            ;;
        replace)
            # 完全替换
            echo "$arr2"
            ;;
    esac
}
```

### 5.3 使用示例

```bash
# 基本使用
result=$(json_merge "base.json" "user.json")
echo "$result" > "merged.json"

# 指定策略
result=$(json_merge "base.json" "user.json" "prefer_base")

# 生成报告
json_merge_with_report() {
    local base="$1"
    local override="$2"
    local strategy="${3:-prefer_override}"
    
    # 执行合并
    local merged
    merged=$(json_merge "$base" "$override" "$strategy")
    
    # 生成详细报告
    local report
    report=$(jq -n \
        --argjson base "$(cat "$base")" \
        --argjson override "$(cat "$override")" \
        --argjson result "$merged" \
        --arg strategy "$strategy" \
        '{
            base: $base,
            override: $override,
            result: $result,
            strategy: $strategy,
            changes: []
        }')
    
    echo "$merged"
    echo "---REPORT---"
    echo "$report"
}
```

---

## 6. 冲突场景处理

### 6.1 完整冲突解决流程

```
┌─────────────────┐
│   读取配置      │
│  base / target │
└────────┬────────┘
         ▼
┌─────────────────┐
│  类型兼容性检查  │
└────────┬────────┘
         ▼
    ┌────┴────┐
    │ 兼容?   │
    └────┬────┘
      Yes│  No
         ▼      ┌─────────────────┐
┌───────────────┤  策略选择       │
│               │  prefer_base    │
│  深度递归合并  │  prefer_override│
│               │  merge          │
└───────┬───────┘  prompt/fail   │
        │         └─────────────────┘
        ▼
┌─────────────────┐
│  生成变更报告   │
└────────┬────────┘
         ▼
┌─────────────────┐
│  输出合并结果   │
└─────────────────┘
```

### 6.2 特殊场景

| 场景 | 处理方式 |
|------|----------|
| 环形引用 | 检测并报错 |
| 极大数组 (>10k) | 分批处理 + 进度显示 |
| 嵌套过深 (>20层) | 警告 + 截断 |
| 编码问题 | UTF-8 自动检测 |

---

## 7. 策略选择指南

### 7.1 场景推荐

| 场景 | 推荐策略 | 说明 |
|------|----------|------|
| 开发 → 生产 | `prefer_base` | 生产配置不可覆盖 |
| 用户配置 → 默认 | `prefer_override` | 用户设置优先 |
| 多环境配置 | `merge` | 智能组合 |
| 安全敏感配置 | `prompt` | 人工确认 |
| CI/CD 自动化 | `fail` | 冲突即失败 |

### 7.2 路径级策略

```bash
# 复杂项目的策略配置示例
{
  "merge_policy": {
    # 全局默认
    "default": "merge",
    
    # 特定路径
    "paths": {
      # 敏感配置: 使用基础值
      "database.password": "prefer_base",
      "api_keys": "prefer_base",
      
      # 用户配置: 优先用户
      "user_preferences": "prefer_override",
      "theme": "prefer_override",
      
      # 插件: 智能合并
      "enabled_plugins": "merge",
      "plugin_config": "merge",
      
      # 危险操作: 失败
      "commands": "fail"
    },
    
    # 数组特殊处理
    "array_policy": {
      "whitelist": "unique",
      "blacklist": "subtract",
      "extensions": "concat"
    }
  }
}
```

---

## 8. 性能优化

| 优化点 | 实现方式 |
|--------|----------|
| 大文件处理 | 流式读取 + 分块处理 |
| 重复键检测 | 哈希缓存 |
| 增量合并 | 只处理变更部分 |
| 并行处理 | 多文件独立合并 |

---

## 9. 错误码参考

| 错误码 | 含义 | 处理建议 |
|--------|------|----------|
| `E001` | JSON 解析失败 | 检查语法 |
| `E002` | 类型冲突 | 使用显式策略 |
| `E003` | 循环引用 | 检查配置结构 |
| `E004` | 权限不足 | 检查文件权限 |
| `E005` | 策略不支持 | 检查策略名称 |
