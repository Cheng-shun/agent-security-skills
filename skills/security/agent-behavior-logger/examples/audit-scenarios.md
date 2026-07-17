# 5 个审计场景示例

---

## 场景 1：团队复盘——"谁改了这个配置文件？"

**需求**：生产环境配置文件被修改，需要找出是哪个 Agent 会话、什么时间、什么上下文。

**查询**：
```bash
bash query-log.sh --file "config/production.yml" --since "2026-07-15"
```

**输出**：
```
2026-07-17 14:23:01 | Write | config/production.yml | session: sess_abc123
2026-07-17 14:23:05 | Bash  | git commit -m "update config" | exit: 0
```

**结论**：sess_abc123 在 14:23 修改了配置并提交。可以追溯到那个会话的完整上下文。

---

## 场景 2：安全审计——"上个月有多少次安全拦截？"

**需求**：月度安全审计，统计 4 个 Skill 的拦截次数和趋势。

**查询**：
```bash
# 7 月拦截统计
grep '"intercepted":true' ~/.claude/logs/agent-behavior.jsonl | \
  grep '2026-07-' | \
  jq -r '.security.events[].skill' | sort | uniq -c
```

**输出**：
```
12 dangerous-command-guard
 8 secret-leak-prevention
 3 prompt-injection-detector
 1 dependency-audit
```

**结论**：命令护栏拦截最多（12 次），主要是 `npm install -g` 和 `git push --force`。密钥扫描拦截了 3 次真实密钥泄露。建议加强全局安装政策的团队教育。

---

## 场景 3：性能优化——"为什么 Agent 这么慢？"

**需求**：Agent 操作变慢，需要找出耗时最长的操作。

**查询**：
```bash
cat ~/.claude/logs/agent-behavior.jsonl | \
  jq -r 'select(.duration_ms > 5000) | [.timestamp, .tool, .duration_ms, .command_summary] | @tsv' | \
  sort -k3 -rn | head -10
```

**输出**：
```
14:30:12  WebFetch  8234ms  https://api.example.com/large-response
14:28:45  Bash      7123ms  npm install
14:15:33  Agent     6540ms  code-review sub-agent
```

**结论**：WebFetch 是最大的延迟来源（外部 API 响应慢），Agent 子任务次之。可以考虑缓存策略。

---

## 场景 4：合规审计——"EU AI Act 要求的所有记录都在吗？"

**需求**：EU AI Act 要求 Agent 的所有高风险操作有完整记录。审计员需要验证。

**查询**：
```bash
# 导出本月所有安全相关事件为合规报告
bash query-log.sh --since "2026-07-01" --export csv --output eu-ai-act-report.csv
```

**CSV 输出包含**：
- 每个高风险操作的时间戳、命令 hash、拦截决策
- 关联的安全 Skill 和事件 ID
- 用户确认状态

**结论**：所有高风险操作均有记录，满足 EU AI Act Article 14 的审计要求。

---

## 场景 5：异常检测——"Agent 行为模式变了？"

**需求**：今天的 Agent 操作数异常增多，需要快速确认是否为攻击行为。

**查询**：
```bash
# 对比今天和昨天的操作数
echo "Today:   $(grep '2026-07-17' ~/.claude/logs/agent-behavior.jsonl | wc -l) ops"
echo "Yesterday: $(grep '2026-07-16' ~/.claude/logs/agent-behavior.jsonl | wc -l) ops"

# 查看今天新增的操作类型
grep '2026-07-17' ~/.claude/logs/agent-behavior.jsonl | \
  jq -r '.tool' | sort | uniq -c | sort -rn
```

**输出**：
```
Today:   234 ops
Yesterday: 47 ops   ← 异常增长 5×

工具分布:
187 WebFetch        ← 异常：正常日均 3 次
 23 Bash
 12 Write
```

**结论**：WebFetch 激增明显异常。查看具体 URL 后发现 Agent 被引导批量抓取外部网站——通过 `prompt-injection-detector` 回溯，确认是一次间接注入攻击。攻击已被拦截，但日志让我们能在 30 秒内定位。

---

## 审计价值总结

| 场景 | 使用 Skill | 价值 |
|------|-----------|------|
| 团队复盘 | 所有 | 可追溯性 — 每个操作都有"纸面轨迹" |
| 安全审计 | 命令护栏 + 密钥扫描 | 合规性 — 统计拦截数据满足审计要求 |
| 性能优化 | 所有 | 可观测性 — duration_ms 定位瓶颈 |
| 合规审计 | 所有 | 法律合规 — EU AI Act / 中国 AI 法规 |
| 异常检测 | 注入检测 + 行为日志 | 防御纵深 — 发现未知攻击模式 |
