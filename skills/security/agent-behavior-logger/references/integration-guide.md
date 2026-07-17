# 与其他 Skill 的集成指南

## 集成架构

```
agent-behavior-logger (审计基础设施)
       ↑ 写入统一日志格式
       │
       ├── dangerous-command-guard
       │   写入事件: CRIT-xxx, HIGH-xxx
       │   写入时机: 命令被拦截时
       │
       ├── secret-leak-prevention
       │   写入事件: SEC-xxx
       │   写入时机: 密钥被检测到时
       │
       ├── prompt-injection-detector
       │   写入事件: INJ-xxx
       │   写入时机: 注入攻击被检测到时
       │
       └── dependency-audit
           写入事件: DEP-xxx
           写入时机: 依赖问题被发现时
```

## 集成方式

### 方法 1：直接追加 JSONL（推荐）

每个 Skill 在拦截/检测事件发生后，调用：

```bash
bash skills/security/agent-behavior-logger/scripts/log-event.sh \
  --skill "dangerous-command-guard" \
  --event "CRIT-001" \
  --severity "CRITICAL" \
  --action "blocked" \
  --command "rm -rf /" \
  --summary "递归根目录删除被拦截"
```

这会在 `~/.claude/logs/agent-behavior.jsonl` 中追加一条记录。

### 方法 2：环境变量传递

在 Skill 的 SKILL.md 中设置：

```yaml
metadata:
  audit_log: "~/.claude/logs/agent-behavior.jsonl"
  audit_schema: "agent-behavior-logger/references/log-schema.json"
```

Agent 运行时自动识别并写入统一格式。

### 方法 3：事件订阅（进阶）

通过文件系统事件监听：

```bash
# 监听新日志
tail -f ~/.claude/logs/agent-behavior.jsonl | while IFS= read -r line; do
  # 实时告警逻辑
done
```

## 跨 Skill 查询示例

```bash
# 今天所有安全拦截事件（跨 4 个 Skill）
grep '"intercepted":true' ~/.claude/logs/agent-behavior.jsonl | jq '.security.events[].skill' | sort | uniq -c

# 某个文件被哪些 Skill 处理过
bash query-log.sh --file "src/config.ts"

# 过去 7 天安全趋势
for d in {1..7}; do
  date=$(date -d "$d days ago" +%Y-%m-%d)
  echo -n "$date: "
  grep "$date" ~/.claude/logs/agent-behavior.jsonl | grep -c '"intercepted":true'
done
```

## 日志轮转

```bash
# 手动归档
tar czf "audit-$(date +%Y%m%d).tar.gz" ~/.claude/logs/agent-behavior.jsonl
rm ~/.claude/logs/agent-behavior.jsonl

# 自动清理（添加到 crontab）
0 0 1 * * find ~/.claude/logs/ -name "audit-*.tar.gz" -mtime +90 -delete
```
