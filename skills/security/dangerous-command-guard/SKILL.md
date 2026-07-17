---
name: dangerous-command-guard
description: 在执行 Shell 命令前扫描危险模式，拦截破坏性操作。覆盖 rm -rf、curl|sh、chmod 777、git push --force 等 20+ 种危险模式。遵循 OWASP Agentic AI Security 标准。Use when the agent is about to execute a Bash or shell command, when the user mentions "safety check", "command guard", "危险命令", "安全检查", or when operating in a production environment.
metadata:
  pattern: reviewer
  category: security
  severity-levels:
    - CRITICAL: 不可逆破坏（rm -rf /、磁盘格式化、fork bomb）
    - HIGH: 权限提升、凭证泄露、强制推送主分支
    - MEDIUM: 系统配置修改、批量删除
    - LOW: 非标准但可恢复的操作
  interaction: confirm  # 拦截时要求用户确认
  steps:
    - command-parsing
    - pattern-matching
    - severity-classification
    - user-confirmation
tags:
  - security
  - command-guard
  - owasp
  - chinese
  - safety
  - agent-guardrail
license: MIT
allowed-tools:
  - Bash
  - Read
version: 0.1.0
---

# Dangerous Command Guard — AI Agent 危险命令拦截器
> 又名：命令护栏

**Leading word: _guardrail_** — 不是"拦截器"（否定→对抗），而是"护栏"（正向→保护）。每个命令都被保护，而非被审查。

在 Agent 执行任何 Shell 命令前，对命令进行结构化安全检查。拒绝执行危险命令，要求用户明确确认后才能继续。

> 理念："围栏优于马力"（Fences over Horsepower）— 安全不是 Agent 的附属功能，而是基础设施。

## 工作流

### 步骤 1：解析命令

当 Agent 准备调用 Bash 工具时：

1. 提取完整命令字符串
2. 识别命令类型（shell 内置、系统命令、包管理器、git、docker 等）
3. 解析参数树（递归展开 `$()`、反引号、管道）

**完成标准**：命令树已被解析为 `{command, args[], subcommands[], pipes[]}` 结构。

### 步骤 2：匹配模式库

将解析后的命令与 `scripts/patterns.json` 中的模式进行匹配：

1. **精确匹配** — 命令名 + 标志组合完全命中（如 `rm -rf /`）
2. **模式匹配** — 正则表达式匹配（如 `curl.*\|.*sh`）
3. **上下文匹配** — 结合当前工作目录、分支名等上下文判断（如 `git push --force` 在 `main` 分支）

所有模式分为四个严重级别（见 `references/severity-guide.md`）。

**完成标准**：返回匹配列表 `[{pattern_id, severity, matched_string, description}]` 或空列表。

### 步骤 3：分类决策

根据匹配结果决定行动：

| 最高严重级别 | 行为 |
|------------|------|
| CRITICAL | **立即拒绝**，不提供绕过选项。返回被拦截的原因和安全建议。 |
| HIGH | **阻止 + 确认**。显示命令风险，要求用户输入 `yes` 确认。记录审计日志。 |
| MEDIUM | **警告 + 继续**。显示风险提示，用户回复 `ok` 后放行。 |
| LOW | **静默放行**，但写入审计日志。 |
| 空匹配 | **放行**，命令安全。 |

CRITICAL 级别的命令**永不执行**，无论用户是否要求——这是硬护栏。

### 步骤 4：用户交互与审计

- **HIGH/MEDIUM**：用中文向用户说明风险，格式如下：

  ```
  🛡️ 命令护栏拦截
  命令：<原始命令>
  风险级别：HIGH
  匹配模式：<pattern_id>
  原因：<一句话解释>
  建议：<更安全的替代方案>
  
  确认执行？回复 "yes" 继续 / "no" 取消
  ```

- **所有拦截事件**写入 `~/.claude/logs/command-guard.jsonl` 审计日志，格式见 `references/audit-log-format.md`。

## 护栏外的补充检查

即使命令未命中模式库，也执行以下**软检查**：

- **凭证存在性**：命令参数中是否包含 `ghp_`、`sk-`、`AKIA` 等模式 → 警告
- **外部管道**：是否包含 `curl`/`wget` + 管道 → 提升至 HIGH
- **批量操作**：是否包含 `xargs rm`、`find -exec rm` → 提升至 MEDIUM
- **系统目录写**：是否向 `/etc/`、`/System32/`、`~/.ssh/` 写入 → 提升至 HIGH

## 参考文件

- `scripts/patterns.json` — 危险命令模式库（正则 + 描述 + 严重级别），护栏的核心数据
- `scripts/guard.sh` — 独立可执行的命令检查脚本（在 Agent 外也可用）
- `references/severity-guide.md` — 四级严重性分类标准和决策矩阵
- `references/owasp-agent.md` — OWASP Agentic AI Security 相关标准摘要
- `references/audit-log-format.md` — 审计日志 JSONL 格式规范
- `examples/blocked-cases.md` — 10 个真实拦截案例及处理结果
