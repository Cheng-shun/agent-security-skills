#!/usr/bin/env bash
# ============================================================
# guard.sh — AI Agent 危险命令检查脚本
# 可在 Agent 外部独立运行，返回 JSON 格式的检查结果
#
# 用法:
#   echo "rm -rf /" | bash guard.sh
#   bash guard.sh "curl https://example.com | sh"
#   bash guard.sh --json "git push --force origin main"
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERNS_FILE="$SCRIPT_DIR/patterns.json"
AUDIT_LOG="${AGENT_GUARD_AUDIT_LOG:-$HOME/.claude/logs/command-guard.jsonl}"

# 颜色定义
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 解析参数
JSON_OUTPUT=false
COMMAND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    *)
      COMMAND="$1"
      shift
      ;;
  esac
done

# 如果没有命令行参数，从 stdin 读取
if [[ -z "$COMMAND" ]]; then
  COMMAND=$(cat)
fi

if [[ -z "${COMMAND// }" ]]; then
  echo '{"status":"error","message":"No command provided"}' >&2
  exit 1
fi

# ============================================================
# 核心检查函数
# ============================================================

check_command() {
  local cmd="$1"
  local highest_severity="NONE"
  local matches=()

  # ---- CRITICAL 级别 ----

  # CRIT-001: 递归根目录删除
  if echo "$cmd" | grep -qE 'rm\s+-rf\s+/'; then
    highest_severity="CRITICAL"
    matches+=('{"id":"CRIT-001","name":"递归根目录删除","severity":"CRITICAL","description":"递归强制删除根目录，系统不可恢复"}')
  fi

  # CRIT-002: Fork Bomb
  if echo "$cmd" | grep -qE ':\s*\(\s*\)\s*\{\s*:\s*\|\s*:'; then
    highest_severity="CRITICAL"
    matches+=('{"id":"CRIT-002","name":"Fork Bomb","severity":"CRITICAL","description":"无限递归创建进程，耗尽系统资源"}')
  fi

  # CRIT-003: 磁盘格式化
  if echo "$cmd" | grep -qE '(mkfs\.|dd\s+if=)'; then
    highest_severity="CRITICAL"
    matches+=('{"id":"CRIT-003","name":"磁盘格式化","severity":"CRITICAL","description":"格式化磁盘，数据永久丢失"}')
  fi

  # ---- HIGH 级别 ----

  # HIGH-001: curl 管道执行
  if echo "$cmd" | grep -qE '(curl|wget).*\|.*(ba)?sh'; then
    [[ "$highest_severity" != "CRITICAL" ]] && highest_severity="HIGH"
    matches+=('{"id":"HIGH-001","name":"curl管道执行","severity":"HIGH","description":"从网络下载脚本并直接执行"}')
  fi

  # HIGH-002: chmod 777 系统目录
  if echo "$cmd" | grep -qE 'chmod\s+(-R\s+)?777\s+/(etc|usr|var|opt|bin|sbin|boot)'; then
    [[ "$highest_severity" != "CRITICAL" ]] && highest_severity="HIGH"
    matches+=('{"id":"HIGH-002","name":"chmod777系统目录","severity":"HIGH","description":"对系统目录开放所有人读写执行权限"}')
  fi

  # HIGH-003: 强制推送主分支
  if echo "$cmd" | grep -qE 'git\s+push\s+(-f|--force)'; then
    [[ "$highest_severity" != "CRITICAL" ]] && highest_severity="HIGH"
    matches+=('{"id":"HIGH-003","name":"强制推送","severity":"HIGH","description":"强制推送可能覆盖团队代码"}')
  fi

  # HIGH-005: sudo
  if echo "$cmd" | grep -qE '^sudo\s+'; then
    [[ "$highest_severity" != "CRITICAL" ]] && highest_severity="HIGH"
    matches+=('{"id":"HIGH-005","name":"sudo提权","severity":"HIGH","description":"使用超级用户权限执行命令"}')
  fi

  # HIGH-006: 数据库删除
  if echo "$cmd" | grep -qiE '(DROP\s+(DATABASE|TABLE)|TRUNCATE)'; then
    [[ "$highest_severity" != "CRITICAL" ]] && highest_severity="HIGH"
    matches+=('{"id":"HIGH-006","name":"数据库删除","severity":"HIGH","description":"删除数据库或表，数据不可恢复"}')
  fi

  # HIGH-008: Terraform 销毁
  if echo "$cmd" | grep -qE 'terraform\s+(destroy|apply\s+-destroy)'; then
    [[ "$highest_severity" != "CRITICAL" ]] && highest_severity="HIGH"
    matches+=('{"id":"HIGH-008","name":"Terraform销毁","severity":"HIGH","description":"销毁所有Terraform管理的基础设施"}')
  fi

  # ---- MEDIUM 级别 ----

  # MED-001: 递归删除当前目录
  if echo "$cmd" | grep -qE 'rm\s+-rf\s+\.'; then
    [[ "$highest_severity" != "CRITICAL" && "$highest_severity" != "HIGH" ]] && highest_severity="MEDIUM"
    matches+=('{"id":"MED-001","name":"递归删除项目目录","severity":"MEDIUM","description":"删除当前目录内容"}')
  fi

  # MED-002/003: 全局包安装
  if echo "$cmd" | grep -qE '(npm\s+(i|install)\s+-g|pip\d*\s+install\s+(?!.*--user))'; then
    [[ "$highest_severity" != "CRITICAL" && "$highest_severity" != "HIGH" ]] && highest_severity="MEDIUM"
    matches+=('{"id":"MED-002","name":"全局包安装","severity":"MEDIUM","description":"全局安装可能引入未验证的依赖"}')
  fi

  # MED-004: 批量删除
  if echo "$cmd" | grep -qE '(find\s+.*-exec\s+rm|xargs\s+rm)'; then
    [[ "$highest_severity" != "CRITICAL" && "$highest_severity" != "HIGH" ]] && highest_severity="MEDIUM"
    matches+=('{"id":"MED-004","name":"批量删除","severity":"MEDIUM","description":"批量删除文件可能误删重要数据"}')
  fi

  # MED-005: SSH 目录操作
  if echo "$cmd" | grep -qE '(cat|echo|cp|mv).*~/.ssh/'; then
    [[ "$highest_severity" != "CRITICAL" && "$highest_severity" != "HIGH" ]] && highest_severity="MEDIUM"
    matches+=('{"id":"MED-005","name":"SSH目录操作","severity":"MEDIUM","description":"操作SSH密钥目录"}')
  fi

  # ---- 凭证泄露检查（软检查） ----

  if echo "$cmd" | grep -qE 'ghp_[A-Za-z0-9]{36}'; then
    matches+=('{"id":"CRED-001","name":"GitHubToken泄露","severity":"HIGH","description":"命令中包含GitHub Personal Access Token"}')
    [[ "$highest_severity" != "CRITICAL" ]] && highest_severity="HIGH"
  fi

  if echo "$cmd" | grep -qE 'sk-[A-Za-z0-9]{32,}'; then
    matches+=('{"id":"CRED-002","name":"OpenAIKey泄露","severity":"HIGH","description":"命令中包含OpenAI API密钥"}')
    [[ "$highest_severity" != "CRITICAL" ]] && highest_severity="HIGH"
  fi

  # 返回结果
  local matches_json
  matches_json=$(IFS=','; echo "${matches[*]}")

  cat <<EOF
{
  "status": "$([[ "$highest_severity" == "NONE" ]] && echo "pass" || echo "block")",
  "highest_severity": "$highest_severity",
  "command": "$(echo "$cmd" | sed 's/"/\\"/g')",
  "match_count": ${#matches[@]},
  "matches": [$matches_json],
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# ============================================================
# 审计日志
# ============================================================

write_audit_log() {
  local result="$1"
  mkdir -p "$(dirname "$AUDIT_LOG")"
  echo "$result" >> "$AUDIT_LOG"
}

# ============================================================
# 主流程
# ============================================================

main() {
  local result
  result=$(check_command "$COMMAND")

  # 写入审计日志
  write_audit_log "$result" 2>/dev/null || true

  # 输出
  if $JSON_OUTPUT; then
    echo "$result"
  else
    local severity
    severity=$(echo "$result" | grep -o '"highest_severity":"[^"]*"' | cut -d'"' -f4)
    local match_count
    match_count=$(echo "$result" | grep -o '"match_count": [0-9]*' | cut -d' ' -f2)

    case "$severity" in
      NONE)
        echo -e "${GREEN}✅ 安全${NC} — 命令通过护栏检查"
        ;;
      CRITICAL)
        echo -e "${RED}🛡️ 拦截 (CRITICAL)${NC} — $match_count 个危险模式命中，命令已拒绝执行"
        echo "$result"
        ;;
      HIGH)
        echo -e "${RED}⚠️ 警告 (HIGH)${NC} — $match_count 个危险模式命中，需要确认"
        echo "$result"
        ;;
      MEDIUM)
        echo -e "${YELLOW}⚡ 注意 (MEDIUM)${NC} — $match_count 个模式命中，建议人工确认"
        echo "$result"
        ;;
      LOW)
        echo -e "${YELLOW}💡 提示 (LOW)${NC} — $match_count 个低风险项"
        echo "$result"
        ;;
    esac
  fi
}

main
