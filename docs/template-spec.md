# 模板语法规范 (Template Specification)

> 用于 OpenClaw 配置差异化的纯 Bash 模板引擎

## 1. 概述

本规范定义了一种轻量级、纯 Bash 实现的模板语法，用于配置差异化处理。设计原则：

- **零外部依赖** - 仅使用 Bash 内置功能
- **直观易学** - 类似 Handlebars/Jinja 简化版
- **错误友好** - 清晰的错误定位和提示

---

## 2. 语法规范

### 2.1 变量替换

#### 基本语法
```
${VAR_NAME}
$VAR_NAME
```

#### 带默认值
```
${VAR_NAME:-default_value}
${VAR_NAME:-$DEFAULT_VAR}
```

#### 示例
```bash
# 模板内容
Name: ${USER_NAME}
Home: ${HOME_DIR:-~/.openclaw}
Debug: ${DEBUG_MODE:-false}

# 渲染结果 (假设 USER_NAME=eva, DEBUG_MODE=true)
Name: eva
Home: ~/.openclaw
Debug: true
```

### 2.2 条件判断

#### 单分支
```
{{#if VAR_NAME}}
content here
{{/if}}
```

#### 双分支
```
{{#if VAR_NAME}}
true content
{{#else}}
false content
{{/if}}
```

#### 多条件
```
{{#if VAR1}}
content A
{{#else if VAR2}}
content B
{{#else}}
content C
{{/if}}
```

#### 比较运算
```
{{#if VAR == value}}      # 相等
{{#if VAR != value}}      # 不等
{{#if VAR > num}}         # 大于 (数值)
{{#if VAR < num}}         # 小于 (数值)
{{#if VAR >= num}}        # 大于等于
{{#if VAR <= num}}        # 小于等于
{{#if -z VAR}}            # 空字符串
{{#if -n VAR}}            # 非空
{{#if -f path}}           # 文件存在
{{#if -d path}}           # 目录存在
```

#### 示例
```bash
# 模板
{{#if DEBUG}}
debug: true
log_level: verbose
{{#else}}
debug: false
log_level: info
{{/if}}

{{#if -z CUSTOM_PATH}}
path: default_path
{{#else}}
path: ${CUSTOM_PATH}
{{/if}}

{{#if VERSION >= 2}}
feature_v2: enabled
{{/if}}

# 渲染结果 (假设 DEBUG=true, CUSTOM_PATH="", VERSION=3)
debug: true
log_level: verbose
path: default_path
feature_v2: enabled
```

### 2.3 循环迭代

#### 数组遍历
```
{{#each ARRAY_VAR}}
{{this}}           # 当前元素
{{@index}}         # 索引 (从 0 开始)
{{@first}}         # 是否第一个
{{@last}}          # 是否最后一个
{{/each}}
```

#### 示例
```bash
# 变量定义
# SKILLS="alpha beta gamma"

# 模板
Skills:
{{#each SKILLS}}
- {{this}} (index: {{@index}})
{{/each}}

# 渲染结果
Skills:
- alpha (index: 0)
- beta (index: 1)
- gamma (index: 2)
```

### 2.4 注释

```
{{! 这是注释 }}
{{! 多行
    注释 }}
```

---

## 3. 实现算法

### 3.1 渲染流程

```
┌─────────────────┐
│  读取模板文件   │
└────────┬────────┘
         ▼
┌─────────────────┐
│  词法分析       │ ← 标记化 (Tokenization)
│  识别语法元素   │
└────────┬────────┘
         ▼
┌─────────────────┐
│  语法验证       │ ← 错误检测
│  配对检查       │
└────────┬────────┘
         ▼
┌─────────────────┐
│  解析执行       │ ← 解释执行
│  变量替换       │
│  条件判断       │
│  循环处理       │
└────────┬────────┘
         ▼
┌─────────────────┐
│  输出结果       │
└─────────────────┘
```

### 3.2 核心函数设计

```bash
# ═══════════════════════════════════════════════════════════════
# 模板引擎核心
# ═══════════════════════════════════════════════════════════════

# 主渲染函数
# 用法: template_render "template_content" [var1=val1 var2=val2 ...]
template_render() {
    local template="$1"
    shift
    
    # 1. 设置变量到环境
    while [[ $# -gt 0 ]]; do
        local var="${1%%=*}"
        local val="${1#*=}"
        export "$var"="$val"
        shift
    done
    
    # 2. 词法分析
    local tokens
    tokens=$(template_tokenize "$template")
    
    # 3. 语法验证
    if ! template_validate "$tokens"; then
        return 1
    fi
    
    # 4. 解析执行
    template_parse "$tokens"
}

# 词法分析 - 标记化
# 输出: TYPE|START|END|CONTENT
template_tokenize() {
    local content="$1"
    local pos=0
    
    # 识别变量: ${VAR} 或 $VAR
    while [[ "$content" =~ ^([^{]*)\$\{([a-zA-Z_][a-zA-Z0-9_:-]*)\}(.*)$ ]]; do
        echo "TEXT|0|${#BASH_REMATCH[1]}|$BASH_REMATCH[1]"
        echo "VAR|${#BASH_REMATCH[1]}|$((${#BASH_REMATCH[1]} + ${#BASH_REMATCH[2]} + 3))|$BASH_REMATCH[2]"
        content="$BASH_REMATCH[3]"
    done
    
    # 识别条件块: {{#if}}, {{#else}}, {{/if}}
    # ... (类似逻辑)
}
```

### 3.3 变量替换算法

```bash
# 变量替换 - 使用参数展开
template_replace_vars() {
    local text="$1"
    
    # 替换 ${VAR:-default}
    while [[ "$text" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*):-([^{}]*)\} ]]; do
        local var="${BASH_REMATCH[1]}"
        local default="${BASH_REMATCH[2]}"
        local value="${!var:-$default}"
        text="${text//\$\{$var:-$default\}/$value}"
    done
    
    # 替换 ${VAR}
    while [[ "$text" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*)\} ]]; do
        local var="${BASH_REMATCH[1]}"
        local value="${!var}"
        text="${text//\$\{$var\}/$value}"
    done
    
    echo "$text"
}
```

### 3.4 条件判断算法

```bash
# 条件解析
template_eval_condition() {
    local cond="$1"
    
    # 处理 -z (空)
    if [[ "$cond" == "-z"* ]]; then
        local var="${cond#*-z }"
        [[ -z "${!var}" ]] && return 0 || return 1
    fi
    
    # 处理 -n (非空)
    if [[ "$cond" == "-n"* ]]; then
        local var="${cond#*-n }"
        [[ -n "${!var}" ]] && return 0 || return 1
    fi
    
    # 处理 -f (文件存在)
    if [[ "$cond" == "-f"* ]]; then
        local path="${cond#*-f }"
        [[ -f "$path" ]] && return 0 || return 1
    fi
    
    # 处理比较 ==
    if [[ "$cond" == *"=="* ]]; then
        local var="${cond%%==*}"
        local val="${cond#*== }"
        [[ "${!var}" == "$val" ]] && return 0 || return 1
    fi
    
    # 处理比较 !=
    if [[ "$cond" == *"!="* ]]; then
        local var="${cond%%!=*}"
        local val="${cond#*!= }"
        [[ "${!var}" != "$val" ]] && return 0 || return 1
    fi
    
    # 默认: 变量存在且非空为真
    [[ -n "${!cond}" ]]
}
```

---

## 4. 边界情况处理

### 4.1 变量相关

| 场景 | 处理方式 |
|------|----------|
| 变量未定义 | 使用默认值（如果有），否则输出空 |
| 变量名为空 | 语法错误，提示缺少变量名 |
| 默认值包含 `}` | 不支持，需转义（未来版本） |
| 递归变量 `${${VAR}}` | 不支持，保留原样 |

### 4.2 条件相关

| 场景 | 处理方式 |
|------|----------|
| 未闭合的 `{{` | 错误: "未闭合的模板标记" |
| 未匹配的 `{{/if}}` | 错误: "缺少 {{#if}} 匹配" |
| 嵌套条件块 | 支持，最多 5 层 |
| 空条件 `{{#if}}` | 错误: "条件表达式不能为空" |

### 4.3 循环相关

| 场景 | 处理方式 |
|------|----------|
| 变量非数组 | 视为单元素数组 |
| 空数组 | 不输出内容 |
| 嵌套循环 | 支持，`@index` 仅在最内层生效 |

---

## 5. 错误提示示例

### 5.1 变量错误

```
❌ 模板错误 [line 5]
   {{ ${} }}
          ^
   错误: 变量名不能为空

❌ 模板错误 [line 10]
   {{ ${UNDEFINED_VAR} }}
                     ^
   错误: 变量未定义，且没有默认值
   提示: 使用 ${VAR:-default} 提供默认值
```

### 5.2 条件块错误

```
❌ 模板错误 [line 15]
   {{#if}}
              ^
   错误: if 条件表达式不能为空

❌ 模板错误 [line 20]
   content here
   {{/if}}
              ^
   错误: 缺少 {{#if}} 开始标签
```

### 5.3 配对错误

```
❌ 模板错误 [line 8-12]
   {{#if DEBUG}}
     debug: true
   {{/if}}
   ────────────────
   错误: if/else/else if 未正确配对
   预期: {{#else}} 或 {{/if}}
```

---

## 6. 使用示例

### 6.1 基础用法

```bash
# 定义变量
export USER_NAME="eva"
export THEME="dark"
export FEATURES='("a" "b" "c")'

# 模板文件 (config.template)
cat > config.template << 'EOF'
# OpenClaw Configuration
user: ${USER_NAME}
theme: ${THEME:-light}
{{#if DEBUG}}
debug: true
{{#else}}
debug: false
{{/if}}
EOF

# 渲染
result=$(template_render "$(cat config.template)" USER_NAME="$USER_NAME" THEME="$THEME")
echo "$result"
```

### 6.2 在迁移工具中使用

```bash
# 根据目标平台生成配置
PLATFORM="darwin"
TEMPLATE=$(cat <<'EOF'
{{#ifeq PLATFORM "darwin"}}
config_path: ~/Library/Application Support/OpenClaw
{{#else ifeq PLATFORM "linux"}}
config_path: ~/.config/openclaw
{{#else}}
config_path: ~/.openclaw
{{/if}}
EOF

template_render "$TEMPLATE" PLATFORM="$PLATFORM")
```

---

## 7. 性能考量

| 优化项 | 说明 |
|--------|------|
| 变量缓存 | 环境变量只读取一次 |
| 正则优化 | 使用 BASH_REMATCH 而非多次 grep |
| 惰性求值 | 条件块仅在被需要时求值 |
| 最大迭代 | 循环默认上限 1000 次 |

---

## 8. 未来扩展

- [ ] 支持模板继承 `{{#include "base.tpl"}}`
- [ ] 支持过滤器 `{{VAR|upper}}`
- [ ] 支持宏定义 `{{#def FOO}}...{{/def}}`
- [ ] 支持 JSON 访问 `${config.database.host}`
