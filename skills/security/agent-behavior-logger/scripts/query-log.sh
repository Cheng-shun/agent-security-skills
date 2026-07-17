#!/usr/bin/env bash
# ============================================================
# query-log.sh — Agent 行为审计日志查询工具
#
# 用法:
#   bash query-log.sh --today --summary        # 今日摘要
#   bash query-log.sh --last 1h                # 最近 1 小时
#   bash query-log.sh --filter "tool==Bash"    # 过滤命令执行
#   bash query-log.sh --skill command-guard    # 某技能相关事件
#   bash query-log.sh --export csv             # 导出 CSV
# ============================================================

set -uo pipefail

LOG_DIR="${AGENT_LOG_DIR:-$HOME/.claude/logs}"
LOG_FILE="$LOG_DIR/agent-behavior.jsonl"
FILTER=""
MODE=""
OUTPUT="pretty"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --today) FILTER="today"; shift ;;
    --last) MODE="last"; shift ;;
    --filter) FILTER="$2"; shift 2 ;;
    --skill) FILTER="skill=$2"; shift 2 ;;
    --file) FILTER="file=$2"; shift 2 ;;
    --summary) MODE="summary"; shift ;;
    --export) OUTPUT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[[ ! -f "$LOG_FILE" ]] && { echo '{"status":"empty","message":"No log file found"}'; exit 0; }

# ---- 时间过滤 ----
time_filter() {
  case "$1" in
    today)
      local today=$(date +%Y-%m-%d)
      grep "$today" "$LOG_FILE"
      ;;
    *)
      cat "$LOG_FILE"
      ;;
  esac
}

# ---- 摘要模式 ----
generate_summary() {
  local data="$1"

  local total=$(echo "$data" | wc -l)
  local bash_calls=$(echo "$data" | grep -c '"tool":"Bash"' 2>/dev/null || echo 0)
  local writes=$(echo "$data" | grep -c '"tool":"Write"' 2>/dev/null || echo 0)
  local reads=$(echo "$data" | grep -c '"tool":"Read"' 2>/dev/null || echo 0)
  local webfetch=$(echo "$data" | grep -c '"tool":"WebFetch"' 2>/dev/null || echo 0)
  local security_intercepts=$(echo "$data" | grep -c '"intercepted":true' 2>/dev/null || echo 0)
  local errors=$(echo "$data" | grep -c '"exit_code":[1-9]' 2>/dev/null || echo 0)

  cat <<EOF
📊 Agent 操作摘要
━━━━━━━━━━━━━━━━━━━━━━━━
总操作数:    $total
🖥️  命令执行:  $bash_calls
📝 文件修改:  $writes
📖 文件读取:  $reads
🌐 外部通信:  $webfetch
🛡️  安全拦截:  $security_intercepts
❌ 错误退出:  $errors
EOF

  # 安全拦截详情
  if [[ "$security_intercepts" -gt 0 ]]; then
    echo ""
    echo "🛡️ 安全拦截详情:"
    echo "$data" | grep '"intercepted":true' | while IFS= read -r line; do
      local cmd=$(echo "$line" | grep -o '"command_summary":"[^"]*"' | cut -d'"' -f4)
      local severity=$(echo "$line" | grep -o '"severity":"[^"]*"' | cut -d'"' -f4)
      echo "  [$severity] $cmd"
    done
  fi
}

# ---- 主流程 ----
data=$(time_filter "$FILTER")

case "$MODE" in
  summary)
    generate_summary "$data"
    ;;
  *)
    if [[ "$OUTPUT" == "csv" ]]; then
      echo "timestamp,tool,command_summary,exit_code,duration_ms,intercepted"
      echo "$data" | grep -o '"timestamp":"[^"]*"|"tool":"[^"]*"|"command_summary":"[^"]*"|"exit_code":[0-9]*|"duration_ms":[0-9]*|"intercepted":[a-z]*' | head -20
    else
      echo "$data" | tail -20
    fi
    ;;
esac
