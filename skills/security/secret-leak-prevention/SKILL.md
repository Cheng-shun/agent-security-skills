---
name: secret-leak-prevention
description: 在代码写入前扫描密钥泄露——API Key、Token、私钥、连接字符串等 20+ 种凭证模式。可独立运行脚本或作为 git pre-commit hook 使用。Use when the agent is about to Write files, commit code, generate config files, or when the user mentions "secret scan", "密钥检测", "凭证泄露", "git hook", "pre-commit check".
metadata:
  pattern: reviewer
  category: security
  severity-levels:
    - CRITICAL: 高置信度真实密钥（ghp_、sk-、AKIA + 高熵值）
    - HIGH: 疑似密钥或连接字符串含密码
    - MEDIUM: 低置信度匹配或注释中的密钥
    - FALSE_POSITIVE: 已知的非密钥匹配（示例、占位符、已撤销密钥）
  interaction: confirm
  steps:
    - file-scan
    - entropy-check
    - context-verification
    - user-resolution
tags:
  - security
  - secret-detection
  - git-hook
  - credential-safety
  - chinese
license: MIT
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
version: 0.1.0
---

# Secret Leak Prevention — 代码写入前密钥检测
> 又名：密钥扫描

**Leading word: _quarantine_**（隔离）— 发现可疑密钥时不是直接删除（可能误判），而是将其放入"隔离区"等待人工裁决。这是一个安全流程，不是一个删除按钮。

> 核心理念: "Never trust a string that looks like a secret." — 任何看起来像密钥的字符串，在写入磁盘前都必须被审查。

当 Agent 准备调用 Write/Edit 工具向文件写入内容时，自动触发密钥扫描。在文件落盘前拦截，比事后 git push 时发现泄露要好——因为此时密钥还没有进入任何版本历史。

## 工作流

### 步骤 1：捕获写入内容

当 Agent 调用 Write 或 Edit 时：

1. 提取目标文件路径
2. 提取即将写入的完整内容（或 Edit 后的结果内容）
3. 记录操作类型（新文件 / 修改已有文件 / 删除）

**跳过扫描的情况**（减少噪音）：
- 文件大小 > 1MB（配置项 `MAX_FILE_SIZE`）
- 文件类型为二进制（通过扩展名判断: .png, .jpg, .exe, .bin 等）
- 文件路径匹配 `.git/` 目录
- 文件为 `.lock` / `package-lock.json` 等自动生成文件

**完成标准**：已获取待扫描内容，或已决定跳过。

### 步骤 2：运行密钥检测

使用 `scripts/scan.sh` 对待写入内容进行结构化扫描：

1. **模式匹配** — 匹配 `scripts/secret-patterns.json` 中定义的 20+ 种密钥格式
2. **熵值检查** — 对长度 >16 的高熵字符串（Shannon entropy > 4.5）标记为可疑
3. **上下文验证** — 检查匹配行是否包含以下"安全信号"：
   - `EXAMPLE_` / `placeholder` / `your-key-here` / `xxx` / `test` → 降级为 FALSE_POSITIVE
   - `process.env.` / `$ENV_VAR` / `${VARIABLE}` → 降级为 MEDIUM（可能是安全引用）
   - 在注释中（`//` / `#` / `/* */`） → 降级为 MEDIUM
   - 字符串长度 < 8 → 降级为 FALSE_POSITIVE

检测到的每条匹配应包含：
- `{file, line, column, pattern_id, severity, matched_snippet, entropy_score}`

**完成标准**：返回 `{findings: [], total_count: N, has_critical: bool}`。

### 步骤 3：分类决策

| 最高严重级别 | 行为 |
|------------|------|
| CRITICAL | **阻止写入**。告知用户："此文件包含高置信度真实密钥，写入前必须脱敏"。提供自动替换为环境变量的选项。 |
| HIGH | **警告 + 确认**。显示匹配片段（脱敏后），要求用户确认或跳过。 |
| MEDIUM | **提示 + 继续**。在输出中显示"注意：发现 X 处疑似密钥"，但不阻止写入。 |
| FALSE_POSITIVE | **静默放行**。不通知用户。 |
| 空匹配 | **放行**，文件安全。 |

CRITICAL 级别**永不自动跳过**——Agent 不得自行判断"这可能是测试密钥"。

### 步骤 4：自动修复建议

对于 CRITICAL 和 HIGH 级别发现，提供**一键替换**选项：

```
🔐 密钥检测 — 发现 2 个问题

📄 .env.local:3 — CRITICAL
  ANTHROPIC_AUTH_TOKEN="sk-ant-abc123..."
  → 建议：替换为 ANTHROPIC_AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN}"

📄 config.json:12 — HIGH
  "password": "admin123"
  → 建议：替换为 "password": "${DB_PASSWORD}"

回复:
  "fix all" — 全部替换为环境变量引用
  "fix N" — 替换指定项
  "skip" — 跳过本次检查（写入审计日志）
  "show" — 查看完整脱敏内容
```

## 集成方式

### 作为 Agent Skill（模型调用）

Agent 在 Write/Edit 前自动调用本 Skill——这是默认方式。

### 作为 Git Pre-commit Hook（独立运行）

```bash
# 在 .git/hooks/pre-commit 中添加：
#!/bin/bash
bash path/to/scripts/scan.sh --staged
```

### 作为 CI 检查

```yaml
# .github/workflows/secret-scan.yml
- name: Secret Scan
  run: bash skills/security/secret-leak-prevention/scripts/scan.sh --all
```

## 参考文件

- `scripts/scan.sh` — 独立密钥扫描脚本（可在 Agent 外运行）
- `scripts/secret-patterns.json` — 20+ 种密钥格式正则库
- `references/false-positive-guide.md` — 误报处理指南和白名单策略
- `references/credential-types.md` — 各平台密钥类型完整对照表
- `examples/caught-leaks.md` — 8 个真实密钥泄露拦截案例
