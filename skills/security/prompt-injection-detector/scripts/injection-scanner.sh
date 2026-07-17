#!/usr/bin/env bash
# ============================================================
# injection-scanner.sh — 提示注入检测脚本
# 对不可信内容进行多维度注入检测
#
# 用法:
#   bash injection-scanner.sh --stdin < content.txt
#   bash injection-scanner.sh --json <file>
#   bash injection-scanner.sh --url "https://example.com" (需 curl)
# ============================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

JSON_OUTPUT=false
CONTENT=""
SOURCE_LABEL="stdin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    --url) SOURCE_LABEL="$2"; CONTENT=$(curl -sL --max-time 10 "$2" 2>/dev/null || echo ""); shift 2 ;;
    --stdin) shift ;;
    *)
      if [[ -f "$1" ]]; then
        CONTENT=$(cat "$1")
        SOURCE_LABEL="$1"
      fi
      shift
      ;;
  esac
done

[[ -z "$CONTENT" ]] && CONTENT=$(cat 2>/dev/null || echo "")
[[ -z "${CONTENT// }" ]] && { echo '{"status":"error","message":"No content to scan"}'; exit 0; }

# ============================================================
# 注入检测核心
# ============================================================

declare -a FINDINGS=()
HIGHEST_SEVERITY="NONE"

# 检测辅助函数
add_finding() {
  local id="$1" name="$2" severity="$3" snippet="$4" category="$5"
  local escaped_snippet="${snippet//\"/\\\"}"
  escaped_snippet="${escaped_snippet:0:100}"
  FINDINGS+=("{\"id\":\"$id\",\"name\":\"$name\",\"severity\":\"$severity\",\"snippet\":\"$escaped_snippet\",\"category\":\"$category\"}")

  case "$severity" in
    CRITICAL) HIGHEST_SEVERITY="CRITICAL" ;;
    HIGH) [[ "$HIGHEST_SEVERITY" != "CRITICAL" ]] && HIGHEST_SEVERITY="HIGH" ;;
    MEDIUM) [[ "$HIGHEST_SEVERITY" != "CRITICAL" && "$HIGHEST_SEVERITY" != "HIGH" ]] && HIGHEST_SEVERITY="MEDIUM" ;;
    LOW) [[ "$HIGHEST_SEVERITY" == "NONE" ]] && HIGHEST_SEVERITY="LOW" ;;
  esac
}

# ---- A: 直接指令注入 ----
check_direct_injection() {
  local content="$1"

  # 英文模式
  if echo "$content" | grep -qiE 'ignore\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?)'; then
    local match=$(echo "$content" | grep -iE 'ignore\s+(all\s+)?(previous|above|prior)\s+(instructions?|prompts?|rules?)' | head -1)
    add_finding "INJ-A01" "Direct: Ignore Previous Instructions" "CRITICAL" "$match" "A_direct_injection"
  fi

  if echo "$content" | grep -qiE 'you\s+are\s+now\s+(DAN|a\s+different|no\s+longer)'; then
    add_finding "INJ-A02" "Direct: Identity Override (DAN)" "CRITICAL" "DAN/identity override detected" "A_direct_injection"
  fi

  if echo "$content" | grep -qiE '(override|forget|disregard).*(instructions?|prompts?|rules?)'; then
    local match=$(echo "$content" | grep -iE '(override|forget|disregard).*(instructions?|prompts?|rules?)' | head -1)
    add_finding "INJ-A03" "Direct: Instruction Override" "CRITICAL" "$match" "A_direct_injection"
  fi

  # 中文模式
  if echo "$content" | grep -qE '忽略(之前|上面|前述|前面)?(所有|全部)?(指令|提示|规则|要求)'; then
    add_finding "INJ-A04" "直接注入: 忽略指令" "CRITICAL" "中文指令忽略模式" "A_direct_injection"
  fi

  if echo "$content" | grep -qE '从现在开始你是'; then
    add_finding "INJ-A05" "直接注入: 身份设定" "CRITICAL" "中文身份劫持模式" "A_direct_injection"
  fi

  if echo "$content" | grep -qE '(忘记|推翻)(你|之前|原有|系统)(的|所说|设定|指令)'; then
    add_finding "INJ-A06" "直接注入: 记忆清除" "CRITICAL" "中文上下文清除模式" "A_direct_injection"
  fi
}

# ---- B: 间接指令注入 ----
check_indirect_injection() {
  local content="$1"

  if echo "$content" | grep -qiE 'as\s+an\s+AI\s+(assistant|agent).*you\s+(should|must|need\s+to)'; then
    add_finding "INJ-B01" "Indirect: AI Role Guidance" "HIGH" "AI assistant should/must pattern" "B_indirect_injection"
  fi

  if echo "$content" | grep -qiE 'the\s+(best|correct|proper|right)\s+way.*is\s+to\s+(run|execute|call)'; then
    local match=$(echo "$content" | grep -iE 'the\s+(best|correct|proper|right)\s+way.*is\s+to\s+(run|execute|call)' | head -1)
    add_finding "INJ-B02" "Indirect: Best Way Suggestion" "HIGH" "$match" "B_indirect_injection"
  fi

  if echo "$content" | grep -qiE '(recommend|suggest|advise)\s+(you|that\s+you)\s+(run|execute|use|call)'; then
    add_finding "INJ-B03" "Indirect: Recommendation to Execute" "HIGH" "Recommendation to execute/tool-use" "B_indirect_injection"
  fi

  # 中文
  if echo "$content" | grep -qE '作为.*(助手|AI|代理).*你(应该|必须|需要|可以).*(执行|运行|操作)'; then
    add_finding "INJ-B04" "间接注入: 角色引导" "HIGH" "中文角色引导模式" "B_indirect_injection"
  fi
}

# ---- C: 角色劫持 ----
check_role_hijack() {
  local content="$1"

  if echo "$content" | grep -qiE 'you\s+are\s+now\s+(a|an|the)\s+(hacker|evil|malicious|unrestricted|uncensored)'; then
    add_finding "INJ-C01" "Role Hijack: Malicious Role" "CRITICAL" "Hacker/evil/malicious role assignment" "C_role_hijack"
  fi

  if echo "$content" | grep -qiE 'pretend\s+(you\s+are|to\s+be|that\s+you)'; then
    add_finding "INJ-C02" "Role Hijack: Pretend Pattern" "CRITICAL" "Pretend/roleplay pattern" "C_role_hijack"
  fi

  if echo "$content" | grep -qiE 'roleplay\s+as.*(unfiltered|unrestricted|evil|dark)'; then
    add_finding "INJ-C03" "Role Hijack: Dark Roleplay" "CRITICAL" "Dark/unfiltered roleplay" "C_role_hijack"
  fi

  # 中文
  if echo "$content" | grep -qE '你现在是(一个|一名|一台).*(黑客|恶意|不受限|无审查)'; then
    add_finding "INJ-C04" "角色劫持: 恶意角色" "CRITICAL" "中文恶意角色劫持" "C_role_hijack"
  fi

  if echo "$content" | grep -qE '假装你是'; then
    add_finding "INJ-C05" "角色劫持: 伪装模式" "CRITICAL" "中文假装模式" "C_role_hijack"
  fi
}

# ---- D: 工具滥用 ----
check_tool_abuse() {
  local content="$1"

  if echo "$content" | grep -qE '(use|call)\s+(the\s+)?(Bash|Write|Edit|WebFetch|Agent)\s+(tool|function)'; then
    add_finding "INJ-D01" "Tool Abuse: Direct Tool Call" "HIGH" "Direct tool name in content" "D_tool_abuse"
  fi

  if echo "$content" | grep -qE 'execute\s+(the\s+following|this)\s+(command|code|script)\s*(with|using|via)'; then
    add_finding "INJ-D02" "Tool Abuse: Execute Command Pattern" "HIGH" "Execute command instruction" "D_tool_abuse"
  fi

  # 中文
  if echo "$content" | grep -qE '(使用|调用).*(Bash|Write|Edit|Agent).*(工具|函数)'; then
    add_finding "INJ-D03" "工具滥用: 直接工具调用" "HIGH" "中文工具调用模式" "D_tool_abuse"
  fi
}

# ---- E: 上下文污染 ----
check_context_poisoning() {
  local content="$1"

  if echo "$content" | grep -qiE '(the|this)\s+(user|developer|admin).*(password|secret|token|key)\s+is'; then
    add_finding "INJ-E01" "Context Poison: Credential Implant" "HIGH" "False credential in context" "E_context_poisoning"
  fi

  if echo "$content" | grep -qiE 'remember.*(this|that|the|for\s+future)'; then
    add_finding "INJ-E02" "Context Poison: Remember Directive" "MEDIUM" "Remember/retain directive" "E_context_poisoning"
  fi

  if echo "$content" | grep -qiE 'add\s+this\s+to\s+(your|the)\s+(memory|context|notes|knowledge)'; then
    add_finding "INJ-E03" "Context Poison: Memory Insertion" "HIGH" "Add to memory/knowledge pattern" "E_context_poisoning"
  fi

  # 中文
  if echo "$content" | grep -qE '(记住|牢记).*(这个|以下|用户.*密码|管理员.*密钥)'; then
    add_finding "INJ-E04" "上下文污染: 记忆植入" "HIGH" "中文记忆植入模式" "E_context_poisoning"
  fi
}

# ---- F: 数据外泄 ----
check_data_exfiltration() {
  local content="$1"

  if echo "$content" | grep -qiE 'send\s+(the\s+)?(contents?|file|data|output).*(to|via|using)\s+(http|curl|webhook|email|api)'; then
    add_finding "INJ-F01" "Exfiltration: Send Data" "CRITICAL" "Send content to external endpoint" "F_data_exfiltration"
  fi

  if echo "$content" | grep -qiE '(cat|read|copy|send|upload|post|share).*\.(env|pem|key|credentials|secret|config)\b'; then
    add_finding "INJ-F02" "Exfiltration: Sensitive File Access" "CRITICAL" "Access .env/key/credential files" "F_data_exfiltration"
  fi

  if echo "$content" | grep -qiE '(exfiltrate|extract|steal|leak|dump).*(data|info|credentials|keys|tokens)'; then
    add_finding "INJ-F03" "Exfiltration: Explicit Terms" "CRITICAL" "Explicit exfiltration vocabulary" "F_data_exfiltration"
  fi

  # 中文
  if echo "$content" | grep -qE '(发送|上传|分享|转发).*(内容|文件|数据|对话).*(到|给|至).*(外部|http|邮箱|API)'; then
    add_finding "INJ-F04" "数据外泄: 发送数据" "CRITICAL" "中文数据外泄模式" "F_data_exfiltration"
  fi
}

# ---- G: 编码绕过 ----
check_encoding_bypass() {
  local content="$1"

  if echo "$content" | grep -qE "echo\s+['\"]?[A-Za-z0-9+/=]{20,}['\"]?\s*\|\s*(base64|basenc).*-d.*\|\s*(ba)?sh"; then
    add_finding "INJ-G01" "Encoding: Base64 Pipe to Shell" "CRITICAL" "Base64 decode pipe to shell" "G_encoding_bypass"
  fi

  if echo "$content" | grep -qE 'eval\s*\(\s*(atob|btoa|unescape|decodeURI|fromCharCode)'; then
    add_finding "INJ-G02" "Encoding: JS Eval with Decode" "HIGH" "JavaScript eval with decode function" "G_encoding_bypass"
  fi

  # URL 编码的可疑命令
  if echo "$content" | grep -qE '%[0-9A-F]{2}.*(curl|wget|rm%20-rf|sudo|bash|sh)'; then
    add_finding "INJ-G03" "Encoding: URL-Encoded Command" "HIGH" "URL-encoded suspicious command" "G_encoding_bypass"
  fi
}

# ---- H: 分隔符欺骗 ----
check_delimiter_spoofing() {
  local content="$1"

  if echo "$content" | grep -qE '<system[^>]*>.*</system>'; then
    add_finding "INJ-H01" "Delimiter: XML System Tag" "HIGH" "XML system tag injection" "H_delimiter_spoofing"
  fi

  if echo "$content" | grep -qE '\[SYSTEM[^\]]*\].*\[/SYSTEM\]'; then
    add_finding "INJ-H02" "Delimiter: Markdown System Block" "HIGH" "Markdown system block injection" "H_delimiter_spoofing"
  fi

  if echo "$content" | grep -qE '<instruction[^>]*>.*</instruction>'; then
    add_finding "INJ-H03" "Delimiter: XML Instruction Tag" "HIGH" "XML instruction tag injection" "H_delimiter_spoofing"
  fi

  # 中文
  if echo "$content" | grep -qE '<系统[^>]*>.*</系统>|<指令[^>]*>.*</指令>|\[系统[^\]]*\].*\[/系统\]'; then
    add_finding "INJ-H04" "分隔符欺骗: 中文标签" "HIGH" "中文系统/指令标签注入" "H_delimiter_spoofing"
  fi
}

# ============================================================
# 上下文过滤 — 降低误报
# ============================================================
apply_context_filter() {
  local content="$1"

  # 检测是否为安全研究/教程/文档内容
  local is_educational=false
  if echo "$content" | grep -qiE '(tutorial|guide|documentation|example|教学|教程|文档|示例|案例|研究|OWASP|security research)'; then
    is_educational=true
  fi

  # 如果是教育性内容，降级处理
  if $is_educational; then
    local new_findings=()
    for finding in "${FINDINGS[@]}"; do
      local severity=$(echo "$finding" | grep -o '"severity":"[^"]*"' | cut -d'"' -f4)
      local new_severity="$severity"
      case "$severity" in
        CRITICAL) new_severity="HIGH" ;;
        HIGH) new_severity="MEDIUM" ;;
        MEDIUM) new_severity="LOW" ;;
      esac
      finding="${finding//\"severity\":\"$severity\"/\"severity\":\"$new_severity\"}"
      finding="${finding} (note: educational context)"
      new_findings+=("$finding")
    done
    FINDINGS=("${new_findings[@]}")
  fi
}

# ============================================================
# 主流程
# ============================================================
main() {
  local content="$CONTENT"

  # 运行所有检测
  check_direct_injection "$content"
  check_indirect_injection "$content"
  check_role_hijack "$content"
  check_tool_abuse "$content"
  check_context_poisoning "$content"
  check_data_exfiltration "$content"
  check_encoding_bypass "$content"
  check_delimiter_spoofing "$content"

  # 上下文过滤
  apply_context_filter "$content"

  # 统计
  local total=${#FINDINGS[@]}
  local critical=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"CRITICAL"' 2>/dev/null || echo 0)
  local high=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"HIGH"' 2>/dev/null || echo 0)
  local medium=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"MEDIUM"' 2>/dev/null || echo 0)

  local findings_json
  findings_json=$(IFS=','; echo "${FINDINGS[*]}")

  local result
  result=$(cat <<EOF
{
  "status": "$([[ "$HIGHEST_SEVERITY" == "NONE" ]] && echo "clean" || echo "threat_detected")",
  "highest_severity": "$HIGHEST_SEVERITY",
  "total_findings": $total,
  "critical": $critical,
  "high": $high,
  "medium": $medium,
  "findings": [$findings_json],
  "source": "$SOURCE_LABEL",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)

  if $JSON_OUTPUT; then
    echo "$result"
  else
    case "$HIGHEST_SEVERITY" in
      NONE)
        echo -e "${GREEN}✅ 注入扫描通过${NC} — 未检测到提示注入"
        ;;
      CRITICAL)
        echo -e "${RED}🚫 检测到提示注入攻击！${NC} — $total 条发现（含 CRITICAL）"
        echo -e "${RED}   内容已隔离，未传递给 Agent。${NC}"
        ;;
      HIGH)
        echo -e "${YELLOW}⚠️ 可疑注入模式${NC} — $total 条发现，建议人工审查"
        ;;
      MEDIUM|LOW)
        echo -e "${CYAN}💡 低风险发现${NC} — $total 条，已标记传递"
        ;;
    esac
    echo "$result"
  fi
}

main
