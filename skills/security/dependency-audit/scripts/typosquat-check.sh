#!/usr/bin/env bash
# ============================================================
# typosquat-check.sh — 拼写欺诈检测
# 对比依赖名与流行包名，检测 typosquatting 攻击
#
# 用法: bash typosquat-check.sh <package_name>
#       bash typosquat-check.sh --check-all < deps.json
# ============================================================

set -uo pipefail

# Top 50 最流行的 npm/PyPI 包名（高仿冒风险目标）
TOP_PACKAGES=(
  "react" "vue" "angular" "next" "express" "lodash" "moment"
  "axios" "redux" "webpack" "babel" "typescript" "eslint" "prettier"
  "react-dom" "react-native" "node-fetch" "dotenv" "commander" "chalk"
  "jest" "mocha" "uuid" "tslib" "classnames" "prop-types" "redux-thunk"
  "flask" "django" "requests" "numpy" "pandas" "tensorflow" "torch"
  "scipy" "matplotlib" "pytest" "sqlalchemy" "celery" "fastapi" "pydantic"
  "serde" "tokio" "clap" "reqwest" "actix" "axum" "rocket" "diesel" "wasm-bindgen"
)

# Levenshtein 距离计算（简化版）
levenshtein() {
  local s1="$1" s2="$2"
  local len1=${#s1} len2=${#s2}
  local d i j

  # 创建距离矩阵
  for ((i=0; i<=len1; i++)); do
    for ((j=0; j<=len2; j++)); do
      if [[ $i -eq 0 ]]; then
        d[$i,$j]=$j
      elif [[ $j -eq 0 ]]; then
        d[$i,$j]=$i
      else
        local cost=1
        [[ "${s1:$((i-1)):1}" == "${s2:$((j-1)):1}" ]] && cost=0
        local del=$(( ${d[$((i-1)),$j]} + 1 ))
        local ins=$(( ${d[$i,$((j-1))]} + 1 ))
        local sub=$(( ${d[$((i-1)),$((j-1))]} + cost ))
        d[$i,$j]=$del
        [[ $ins -lt ${d[$i,$j]} ]] && d[$i,$j]=$ins
        [[ $sub -lt ${d[$i,$j]} ]] && d[$i,$j]=$sub
      fi
    done
  done
  echo "${d[$len1,$len2]}"
}

# 混淆字符检测
check_confusable_chars() {
  local name="$1"
  local issues=()

  # 0 ↔ o, 1 ↔ l, 5 ↔ s, 8 ↔ b
  if echo "$name" | grep -q '[0-9]'; then
    local cleaned="${name//0/o}"
    cleaned="${cleaned//1/l}"
    cleaned="${cleaned//5/s}"
    cleaned="${cleaned//8/b}"
    for popular in "${TOP_PACKAGES[@]}"; do
      if [[ "$cleaned" == "$popular" ]] && [[ "$name" != "$popular" ]]; then
        issues+=("数字替换: $name 可能与 $popular 混淆")
      fi
    done
  fi

  # 连字符混淆 react-native vs reactnative
  local nohyphen="${name//-/}"
  for popular in "${TOP_PACKAGES[@]}"; do
    local pop_nohyphen="${popular//-/}"
    if [[ "$nohyphen" == "$pop_nohyphen" ]] && [[ "$name" != "$popular" ]]; then
      issues+=("连字符混淆: $name 可能与 $popular 混淆")
    fi
  done

  printf '%s\n' "${issues[@]}"
}

# ============================================================
main() {
  local pkg_name="${1:-}"

  if [[ -z "$pkg_name" ]]; then
    # 从 stdin 读取 JSON
    local deps_json=$(cat)
    local names=$(echo "$deps_json" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    for name in $names; do
      bash "$0" "$name"
    done
    exit 0
  fi

  local findings=()
  local lowest_distance=999
  local closest_match=""

  for popular in "${TOP_PACKAGES[@]}"; do
    local dist
    dist=$(levenshtein "$pkg_name" "$popular")

    if [[ $dist -lt $lowest_distance ]]; then
      lowest_distance=$dist
      closest_match="$popular"
    fi

    # 距离 0 = 完全匹配（正常）
    # 距离 1-2 = 高仿冒风险
    if [[ $dist -ge 1 && $dist -le 2 ]]; then
      findings+=("{\"package\":\"$pkg_name\",\"similar_to\":\"$popular\",\"distance\":$dist,\"risk\":\"HIGH\"}")
    fi
  done

  # 混淆字符检查
  local confusable
  confusable=$(check_confusable_chars "$pkg_name")
  if [[ -n "$confusable" ]]; then
    findings+=("{\"package\":\"$pkg_name\",\"issue\":\"confusable_chars\",\"detail\":\"$confusable\",\"risk\":\"CRITICAL\"}")
  fi

  if [[ ${#findings[@]} -gt 0 ]]; then
    local findings_json
    findings_json=$(IFS=','; echo "${findings[*]}")
    cat <<EOF
{
  "package": "$pkg_name",
  "status": "suspicious",
  "closest_legitimate": "$closest_match",
  "levenshtein_distance": $lowest_distance,
  "findings": [$findings_json]
}
EOF
  else
    cat <<EOF
{
  "package": "$pkg_name",
  "status": "clean",
  "closest_legitimate": "$closest_match",
  "levenshtein_distance": $lowest_distance,
  "findings": []
}
EOF
  fi
}

main "$@"
