---
name: agent-behavior-logger
description: 审计 Agent 所有操作——工具调用、文件变更、命令执行、安全拦截事件。生成结构化 JSONL 日志并支持查询/汇总。Use when the user wants to audit agent behavior, review what the agent did, generate activity reports, or mentions "审计日志", "行为记录", "agent log", "activity report".
metadata:
  pattern: tool-wrapper
  category: security
  interaction: silent
  steps:
    - intercept-tool-call
    - record-event
    - generate-summary
tags:
  - security
  - audit
  - logging
  - chinese
license: MIT
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
version: 0.1.0
---

# Agent Behavior Logger — Agent 行为审计日志
> 又名：行为日志

**Leading word: _paper trail_**（纸面轨迹）— 不是"监控"（对抗），而是"记日记"（透明）。Agent 做的每一件事都留下一张"纸"，事后可以追溯、复盘、举证。审计不是事后追责，而是让每一次操作都经得起追问。

> Tool Wrapper 模式 — 在所有工具调用外层包裹日志记录。不改变工具行为，只在静默中记录。

## 设计原理

### 为什么是 Tool Wrapper？

Agent 的操作分布在以下工具中：
- `Bash` — Shell 命令执行
- `Write` / `Edit` — 文件修改
- `Read` / `Glob` / `Grep` — 文件读取
- `WebFetch` / `WebSearch` — 外部通信
- `Agent` — 子 Agent 创建

如果每个 Skill 各自记日志，会出现：格式不一致、时间戳不同步、无法跨 Skill 关联。Tool Wrapper 在最外层统一拦截记录。

### 与其他 Skill 的关系

```
agent-behavior-logger  ← 审计基础设施（本 Skill）
       ↑
       ├── dangerous-command-guard   写入: 命令拦截事件
       ├── secret-leak-prevention    写入: 密钥检测事件
       ├── prompt-injection-detector 写入: 注入检测事件
       └── dependency-audit          写入: 依赖审计事件
```

其他 4 个 Skill 仍保留自己的事件日志，但**统一写入本 Skill 的日志文件格式**。这样可以运行跨 Skill 的关联查询，例如："帮我找到今天所有安全相关的拦截事件"。

---

## 工作流

### 步骤 1：拦截工具调用

在每次工具调用时，静默记录元数据（不改变工具行为）：

| 字段 | 来源 | 示例 |
|------|------|------|
| `event_id` | UUID v4 | `a1b2c3d4-...` |
| `timestamp` | ISO 8601 | `2026-07-17T14:30:00+08:00` |
| `tool_name` | 工具名 | `Bash`, `Write`, `WebFetch` |
| `command_hash` | SHA256 (前 12 位) | `a1b2c3d4e5f6` |
| `command_summary` | 前 80 字符 | `git commit -m "feat: add..."` |
| `working_directory` | 当前路径 | `/project/src` |
| `file_path` | Write/Edit 的目标文件 | `src/config.ts` |
| `duration_ms` | 工具调用耗时 | `234` |
| `exit_code` | 退出码 (Bash) | `0` |
| `security_events` | 关联的安全事件 ID | `["CRIT-001", "SEC-020"]` |
| `session_id` | 当前会话 ID | 环境变量 `CLAUDE_SESSION_ID` |

**敏感数据脱敏**：
- 命令中包含凭证 → hash 后不记录原始命令
- 文件内容 → 只记录文件路径 + hash，不记录内容
- 用户输入 → 不记录

### 步骤 2：写入日志

日志文件位置（可配置）：

```
默认: ~/.claude/logs/agent-behavior.jsonl
环境变量: AGENT_LOG_PATH
```

每行一条 JSON：

```json
{
  "event_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "timestamp": "2026-07-17T14:30:00.123+08:00",
  "tool": "Bash",
  "command_hash": "a1b2c3d4e5f6",
  "command_summary": "git commit -m \"feat: add dependency-audit\"",
  "directory": "/project",
  "duration_ms": 234,
  "exit_code": 0,
  "security": {
    "intercepted": false,
    "events": []
  },
  "session_id": "sess_xyz"
}
```

安全事件示例：

```json
{
  "security": {
    "intercepted": true,
    "events": [
      {"skill": "dangerous-command-guard", "event_id": "CRIT-001", "severity": "CRITICAL", "action": "blocked"}
    ]
  }
}
```

### 步骤 3：日志查询

提供 `scripts/query-log.sh` 用于查询审计日志：

```bash
# 今日操作摘要
bash query-log.sh --today --summary

# 查看所有被拦截的命令
bash query-log.sh --filter 'security.intercepted==true'

# 查看最近 1 小时的操作
bash query-log.sh --since "1 hour ago"

# 查看特定文件的所有修改
bash query-log.sh --file "src/config.ts"

# 导出 CSV 报告
bash query-log.sh --export csv --output report.csv
```

### 步骤 4：定期报告

`scripts/daily-report.sh` 生成每日审计摘要：

```
📊 Agent 操作日报 — 2026-07-17
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖥️  命令执行: 47 次 (平均耗时 1.2s)
📝 文件修改: 12 次 (6 个文件)
📖 文件读取: 23 次
🌐 外部通信: 3 次
🛡️  安全拦截: 2 次 (HIGH×1, MEDIUM×1)

⚠️ 需要关注:
- 14:23 尝试写入 .env.local（被密钥扫描拦截）
- 15:01 git push --force 主分支（被命令护栏拦截）
```

---

## 隐私与合规

| 原则 | 实现 |
|------|------|
| **最少记录** | 只记录元数据（命令 hash + 摘要），不记录文件内容 |
| **本地存储** | 日志仅存储在本地 `~/.claude/logs/`，不上传 |
| **自动清理** | 默认保留 30 天，可通过 `AGENT_LOG_RETENTION_DAYS` 配置 |
| **脱敏** | 凭证自动 hash，不存储原始 key |
| **访问控制** | 日志文件权限 600 |

---

## 参考文件

- `scripts/query-log.sh` — 日志查询工具
- `scripts/daily-report.sh` — 每日审计报告生成器
- `references/log-schema.json` — 完整 JSON Schema
- `references/integration-guide.md` — 与其他 Skill 的集成指南
- `examples/audit-scenarios.md` — 5 个审计场景示例
