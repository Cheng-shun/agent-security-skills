#!/usr/bin/env bash
# ============================================================
# daily-report.sh — 每日 Agent 操作审计报告
#
# 用法:
#   bash daily-report.sh                  # 今天的报告
#   bash daily-report.sh 2026-07-16       # 指定日期
#   bash daily-report.sh --json           # JSON 格式输出
# ============================================================

set -uo pipefail

DATE="${1:-$(date +%Y-%m-%d)}"
JSON_OUTPUT=false
[[ "$*" == *"--json"* ]] && JSON_OUTPUT=true

LOG_DIR="${AGENT_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/agent-behavior.jsonl"

[[ ! -f "$LOG_FILE" ]] && {
  echo '{"status":"empty","message":"No log file found. Agent behavior logging is not active."}'
  exit 0
}

# 提取当天数据
TODAY_DATA=$(grep "$DATE" "$LOG_FILE" 2>/dev/null || echo "")

if [[ -z "$TODAY_DATA" ]]; then
  $JSON_OUTPUT && echo "{\"status\":\"empty\",\"date\":\"$DATE\",\"message\":\"No agent activity recorded\"}"
  $JSON_OUTPUT || echo "📊 $DATE — 无 Agent 操作记录"
  exit 0
fi

# 统计
TOTAL=$(echo "$TODAY_DATA" | wc -l)
BASH=$(echo "$TODAY_DATA" | grep -c '"tool":"Bash"' 2>/dev/null || echo 0)
WRITE=$(echo "$TODAY_DATA" | grep -c '"tool":"Write"' 2>/dev/null || echo 0)
EDIT=$(echo "$TODAY_DATA" | grep -c '"tool":"Edit"' 2>/dev/null || echo 0)
READ=$(echo "$TODAY_DATA" | grep -c '"tool":"Read"' 2>/dev/null || echo 0)
WEBFETCH=$(echo "$TODAY_DATA" | grep -c '"tool":"WebFetch"' 2>/dev/null || echo 0)
AGENT=$(echo "$TODAY_DATA" | grep -c '"tool":"Agent"' 2>/dev/null || echo 0)
INTERCEPTED=$(echo "$TODAY_DATA" | grep -c '"intercepted":true' 2>/dev/null || echo 0)
ERRORS=$(echo "$TODAY_DATA" | grep -c '"exit_code":[1-9]' 2>/dev/null || echo 0)

# 平均耗时
AVG_DURATION=0
if [[ "$BASH" -gt 0 ]]; then
  durations=$(echo "$TODAY_DATA" | grep '"tool":"Bash"' | grep -o '"duration_ms":[0-9]*' | cut -d: -f2)
  sum=0; count=0
  for d in $durations; do
    sum=$((sum + d))
    ((count++))
  done
  [[ $count -gt 0 ]] && AVG_DURATION=$((sum / count))
fi

# 安全事件详情
SECURITY_EVENTS=""
if [[ "$INTERCEPTED" -gt 0 ]]; then
  SECURITY_EVENTS=$(echo "$TODAY_DATA" | grep '"intercepted":true' | while IFS= read -r line; do
    local ts=$(echo "$line" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4 | cut -d'T' -f2 | cut -d'.' -f1)
    local cmd=$(echo "$line" | grep -o '"command_summary":"[^"]*"' | cut -d'"' -f4)
    local sev=$(echo "$line" | grep -o '"severity":"[^"]*"' | cut -d'"' -f4)
    echo "  ⚠️  $ts [$sev] $cmd"
  done)
fi

if $JSON_OUTPUT; then
  cat <<EOF
{
  "date": "$DATE",
  "total_operations": $TOTAL,
  "breakdown": {
    "bash": $BASH,
    "write": $WRITE,
    "edit": $EDIT,
    "read": $READ,
    "webfetch": $WEBFETCH,
    "agent": $AGENT
  },
  "avg_bash_duration_ms": $AVG_DURATION,
  "errors": $ERRORS,
  "security_interceptions": $INTERCEPTED,
  "risk_level": "$([[ $INTERCEPTED -gt 2 ]] && echo "HIGH" || echo "LOW")"
}
EOF
else
  cat <<EOF
📊 Agent 操作日报 — $DATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
操作统计
──────────────────────────────────────
🖥️  命令执行:  $BASH 次 (平均 ${AVG_DURATION}ms)
📝 文件写入:  $WRITE 次
✏️  文件编辑:  $EDIT 次
📖 文件读取:  $READ 次
🌐 外部通信:  $WEBFETCH 次
🤖 子 Agent:  $AGENT 次
──────────────────────────────────────
❌ 错误退出:  $ERRORS 次
🛡️  安全拦截:  $INTERCEPTED 次
──────────────────────────────────────
总操作数:    $TOTAL
风险等级:    $([[ $INTERCEPTED -gt 2 ]] && echo "🔴 HIGH" || echo "🟢 LOW")
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

  if [[ -n "$SECURITY_EVENTS" ]]; then
    echo ""
    echo "🛡️ 安全拦截详情:"
    echo "$SECURITY_EVENTS"
  fi
fi
