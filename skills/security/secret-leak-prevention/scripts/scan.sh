#!/usr/bin/env bash
# ============================================================
# scan.sh — 密钥泄露检测脚本
# 可脱离 Agent 独立运行，也可作为 git hook 或 CI step 使用
#
# 用法:
#   bash scan.sh <file>                    # 扫描单个文件
#   bash scan.sh --stdin <<< "$content"     # 扫描管道输入
#   bash scan.sh --staged                   # 扫描 git 暂存区
#   bash scan.sh --all                      # 扫描整个仓库（排除 .gitignore 路径）
#   bash scan.sh --json <file>              # JSON 格式输出
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERNS_FILE="$SCRIPT_DIR/secret-patterns.json"
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

JSON_OUTPUT=false
MODE=""
TARGET=""

# ============================================================
# 参数解析
# ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    --stdin) MODE="stdin"; shift ;;
    --staged) MODE="staged"; shift ;;
    --all) MODE="all"; shift ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$1"
      fi
      shift
      ;;
  esac
done

# ============================================================
# Shannon 熵值计算（简化版 — 对 256 个可能字符做频率统计）
# ============================================================
shannon_entropy() {
  local str="$1"
  local len=${#str}
  [[ $len -lt 12 ]] && { echo "0"; return; }

  # 统计字节频率
  local freq_str
  freq_str=$(echo -n "$str" | fold -w1 | sort | uniq -c | awk '{print $1}')

  local entropy=0
  local count
  for count in $freq_str; do
    if [[ "$count" -gt 0 ]] 2>/dev/null; then
      local prob
      prob=$(echo "scale=6; $count / $len" | bc 2>/dev/null || echo "0")
      if [[ "$prob" != "0" ]]; then
        local term
        term=$(echo "scale=6; $prob * l($prob)/l(2)" | bc -l 2>/dev/null || echo "0")
        entropy=$(echo "scale=6; $entropy - $term" | bc -l 2>/dev/null || echo "$entropy")
      fi
    fi
  done

  echo "${entropy:-0}"
}

# ============================================================
# 模式匹配引擎（简化版 — 在 Agent 中由 LLM 补充复杂匹配）
# ============================================================
scan_content() {
  local content="$1"
  local file_path="${2:-stdin}"
  local findings=()
  local line_num=0
  local total=0

  # 高置信度模式 — 这些是硬匹配，几乎无误报
  local -A HARD_PATTERNS=(
    ["SEC-001:Anthropic API Key"]='sk-ant-[a-z]+[0-9]*-[A-Za-z0-9]{32,}'
    ["SEC-002:OpenAI API Key"]='sk-(proj-)?[A-Za-z0-9-_]{32,}'
    ["SEC-010:AWS Access Key"]='AKIA[0-9A-Z]{16}'
    ["SEC-020:GitHub Token (Classic)"]='ghp_[A-Za-z0-9]{36}'
    ["SEC-021:GitHub Token (Fine-grained)"]='github_pat_[A-Za-z0-9_]{36,}'
    ["SEC-022:GitLab Token"]='glpat-[A-Za-z0-9\-_]{20,}'
    ["SEC-040:SSH Private Key"]='-----BEGIN (RSA|DSA|EC|OPENSSH|PGP) PRIVATE KEY-----'
    ["SEC-041:PEM Private Key"]='-----BEGIN PRIVATE KEY-----'
    ["SEC-060:阿里云 AccessKey"]='LTAI[0-9A-Za-z]{16,20}'
    ["SEC-061:腾讯云 SecretId"]='AKID[0-9A-Za-z]{32,48}'
    ["SEC-003:DeepSeek API Key"]='sk-[a-z0-9]{32}'
    ["SEC-004:Google AI Key"]='AIza[0-9A-Za-z\-_]{35}'
    ["SEC-053:Slack Webhook"]='https://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+'
  )

  # 中等置信度模式 — 可能有误报，需要上下文过滤
  # 注意：使用 grep -iE（不区分大小写），模式中不含 (?i) 等 Perl 语法
  local -A SOFT_PATTERNS=(
    ["SEC-030:MySQL Connection"]='mysql://[a-zA-Z0-9._-]+:[^@]+@[a-zA-Z0-9._-]+/[a-zA-Z0-9_]+'
    ["SEC-031:PostgreSQL Connection"]='postgres(ql)?://[a-zA-Z0-9._-]+:[^@]+@[a-zA-Z0-9._-]+/[a-zA-Z0-9_]+'
    ["SEC-050:Generic Password"]='(password|passwd|pwd|secret)[[:space:]]*[=:][[:space:]]*['"'"'"][^'"'"'"]{4,}['"'"'"]'
    ["SEC-051:Generic API Key"]='(api[_]?key|apikey|api[_]?secret|access[_]?key)[[:space:]]*[=:][[:space:]]*['"'"'"][^'"'"'"]{8,}['"'"'"]'
  )

  while IFS= read -r line; do
    ((line_num++))

    # 跳过空行和纯注释行
    [[ -z "${line// }" ]] && continue

    # 硬匹配
    for entry in "${!HARD_PATTERNS[@]}"; do
      local pattern_id="${entry%%:*}"
      local pattern_name="${entry#*:}"
      local regex="${HARD_PATTERNS[$entry]}"

      if echo "$line" | grep -qoE "$regex" 2>/dev/null; then
        local matched
        matched=$(echo "$line" | grep -oE "$regex" | head -1)
        local snippet="${matched:0:40}..."

        # 上下文过滤：检查是否是占位符/示例
        if echo "$line" | grep -qiE '(example|placeholder|your-|xxx|test|fake|dummy|REPLACE_ME|TODO)'; then
          findings+=("{\"id\":\"$pattern_id\",\"name\":\"$pattern_name\",\"file\":\"$file_path\",\"line\":$line_num,\"severity\":\"FALSE_POSITIVE\",\"snippet\":\"$snippet\",\"note\":\"上下文包含占位符/示例关键词\"}")
        else
          findings+=("{\"id\":\"$pattern_id\",\"name\":\"$pattern_name\",\"file\":\"$file_path\",\"line\":$line_num,\"severity\":\"CRITICAL\",\"snippet\":\"$snippet\"}")
        fi
        ((total++))
      fi
    done

    # 软匹配（使用 grep -iE 不区分大小写）
    for entry in "${!SOFT_PATTERNS[@]}"; do
      local pattern_id="${entry%%:*}"
      local pattern_name="${entry#*:}"
      local regex="${SOFT_PATTERNS[$entry]}"

      if echo "$line" | grep -qiE "$regex" 2>/dev/null; then
        local matched
        matched=$(echo "$line" | grep -oiE "$regex" | head -1)
        local snippet="${matched:0:40}..."

        # 检查环境变量引用
        if echo "$line" | grep -qE '(process\.env\.|\$\{|os\.getenv\(|System\.getenv\()'; then
          findings+=("{\"id\":\"$pattern_id\",\"name\":\"$pattern_name\",\"file\":\"$file_path\",\"line\":$line_num,\"severity\":\"MEDIUM\",\"snippet\":\"$snippet\",\"note\":\"使用了环境变量引用\"}")
        # 检查是否在注释中
        elif echo "$line" | grep -qE '^\s*(#|//|/\*|\*|<!--)'; then
          findings+=("{\"id\":\"$pattern_id\",\"name\":\"$pattern_name\",\"file\":\"$file_path\",\"line\":$line_num,\"severity\":\"MEDIUM\",\"snippet\":\"$snippet\",\"note\":\"位于注释中\"}")
        else
          findings+=("{\"id\":\"$pattern_id\",\"name\":\"$pattern_name\",\"file\":\"$file_path\",\"line\":$line_num,\"severity\":\"HIGH\",\"snippet\":\"$snippet\"}")
        fi
        ((total++))
      fi
    done

    # 熵值检查（高熵字符串）
    local words
    IFS=' ' read -ra words <<< "$line"
    for word in "${words[@]}"; do
      # 去除引号和等号
      local clean_word="${word//[\"\']/}"
      clean_word="${clean_word#*=}"
      local word_len=${#clean_word}
      if [[ $word_len -ge 20 && $word_len -le 80 ]]; then
        local entropy
        entropy=$(shannon_entropy "$clean_word")
        if [[ -n "$entropy" ]] && echo "$entropy > 4.5" | bc -l 2>/dev/null | grep -q 1; then
          findings+=("{\"id\":\"SEC-052\",\"name\":\"High Entropy String\",\"file\":\"$file_path\",\"line\":$line_num,\"severity\":\"MEDIUM\",\"snippet\":\"${clean_word:0:30}...\",\"entropy\":$entropy}")
          ((total++))
        fi
      fi
    done
  done <<< "$content"

  # 确定最高严重级别
  local highest="NONE"
  for f in "${findings[@]}"; do
    if echo "$f" | grep -q '"severity":"CRITICAL"'; then highest="CRITICAL"; break; fi
    if echo "$f" | grep -q '"severity":"HIGH"'; then highest="HIGH"; fi
    if [[ "$highest" != "HIGH" ]] && echo "$f" | grep -q '"severity":"MEDIUM"'; then highest="MEDIUM"; fi
  done

  local findings_json
  findings_json=$(IFSEP=","; echo "${findings[*]}" | sed 's/} {/}, {/g')

  cat <<SCANRESULT
{
  "status": "$([[ "$highest" == "NONE" ]] && echo "clean" || echo "found")",
  "highest_severity": "$highest",
  "total_count": $total,
  "critical_count": $(echo "${findings[@]}" | grep -c '"CRITICAL"' || echo 0),
  "high_count": $(echo "${findings[@]}" | grep -c '"HIGH"' || echo 0),
  "medium_count": $(echo "${findings[@]}" | grep -c '"MEDIUM"' || echo 0),
  "findings": [$findings_json],
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
SCANRESULT
}

# ============================================================
# 主流程
# ============================================================

main() {
  local content
  local file_label

  case "$MODE" in
    stdin)
      content=$(cat)
      file_label="stdin"
      ;;
    staged)
      content=$(git diff --cached 2>/dev/null || echo "")
      file_label="git-staged"
      if [[ -z "$content" ]]; then
        echo '{"status":"clean","message":"No staged changes","total_count":0}' >&2
        exit 0
      fi
      ;;
    all)
      local files
      files=$(git ls-files 2>/dev/null | grep -vE '\.(png|jpg|jpeg|gif|ico|exe|dll|bin|lock|min\.js|min\.css)$' | grep -v 'node_modules/' | grep -v '\.git/' || echo "")
      if [[ -z "$files" ]]; then
        echo '{"status":"clean","message":"No files to scan","total_count":0}' >&2
        exit 0
      fi
      local all_findings=()
      while IFS= read -r f; do
        [[ ! -f "$f" ]] && continue
        [[ $(wc -c < "$f" 2>/dev/null || echo 0) -gt 1048576 ]] && continue
        content=$(cat "$f" 2>/dev/null || echo "")
        [[ -z "$content" ]] && continue
        local result
        result=$(scan_content "$content" "$f")
        local count
        count=$(echo "$result" | grep -o '"total_count":[0-9]*' | head -1 | cut -d: -f2)
        [[ "$count" -gt 0 ]] && all_findings+=("$result")
      done <<< "$files"
      echo "${all_findings[@]}"
      exit 0
      ;;
    *)
      if [[ -n "$TARGET" && -f "$TARGET" ]]; then
        content=$(cat "$TARGET")
        file_label="$TARGET"
      else
        echo '{"status":"error","message":"No target file or mode specified. Usage: scan.sh [--stdin|--staged|--all|<file>]"}' >&2
        exit 1
      fi
      ;;
  esac

  local result
  result=$(scan_content "$content" "$file_label")

  if $JSON_OUTPUT; then
    echo "$result"
  else
    local severity
    severity=$(echo "$result" | grep -o '"highest_severity":"[^"]*"' | cut -d'"' -f4)
    local total
    total=$(echo "$result" | grep -o '"total_count":[0-9]*' | cut -d: -f2)

    case "$severity" in
      NONE)
        echo -e "${GREEN}🔐 密钥扫描通过${NC} — 未发现凭证泄露"
        ;;
      CRITICAL)
        echo -e "${RED}🚨 发现密钥泄露！${NC} — $total 条发现（含 CRITICAL 级别）"
        echo -e "${RED}   写入已阻止。请将密钥替换为环境变量引用。${NC}"
        ;;
      HIGH)
        echo -e "${YELLOW}⚠️ 疑似密钥${NC} — $total 条发现，请人工确认"
        ;;
      MEDIUM)
        echo -e "${CYAN}💡 提示${NC} — $total 条低置信度发现"
        ;;
    esac
    echo "$result" | grep -o '"snippet":"[^"]*"' | while read -r s; do
      echo "  → ${s:11:-1}"
    done
  fi
}

main
