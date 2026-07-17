#!/usr/bin/env bash
# ============================================================
# extract-deps.sh — 从项目中提取依赖清单
# 支持 npm / pip / cargo / go mod / gem / maven
#
# 用法: bash extract-deps.sh [project_dir] --json
# ============================================================

set -uo pipefail

TARGET="${1:-.}"
JSON_OUTPUT=false

[[ "$*" == *"--json"* ]] && JSON_OUTPUT=true

declare -a DEPS=()
TOTAL=0

# ---- npm (package.json) ----
extract_npm() {
  local dir="$1"
  local pkg="$dir/package.json"
  [[ ! -f "$pkg" ]] && return

  local name=$(grep -o '"name"\s*:\s*"[^"]*"' "$pkg" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  [[ -z "$name" ]] && name="unknown"

  # 提取 dependencies
  local deps_json=$(grep -A 1000 '"dependencies"' "$pkg" | grep -B 1000 '"devDependencies"' | grep -o '"[^"]*"\s*:\s*"[^"]*"' | head -50)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local pkg_name=$(echo "$line" | sed 's/"\([^"]*\)".*/\1/')
    local pkg_ver=$(echo "$line" | sed 's/.*"\s*:\s*"\([^"]*\)".*/\1/')
    DEPS+=("{\"name\":\"$pkg_name\",\"version\":\"$pkg_ver\",\"ecosystem\":\"npm\",\"is_direct\":true,\"project\":\"$name\"}")
    ((TOTAL++))
  done <<< "$deps_json"
}

# ---- Python (requirements.txt) ----
extract_pip() {
  local dir="$1"
  local req="$dir/requirements.txt"
  [[ ! -f "$req" ]] && req="$dir/pyproject.toml"
  [[ ! -f "$req" ]] && return

  if [[ "$req" == *"requirements.txt"* ]]; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      local pkg_name=$(echo "$line" | sed 's/[>=<~!].*//' | xargs)
      local pkg_ver=$(echo "$line" | grep -o '[0-9][0-9.]*' | head -1)
      [[ -z "$pkg_name" ]] && continue
      DEPS+=("{\"name\":\"$pkg_name\",\"version\":\"${pkg_ver:-unknown}\",\"ecosystem\":\"pypi\",\"is_direct\":true,\"project\":\"python\"}")
      ((TOTAL++))
    done < "$req"
  fi
}

# ---- Rust (Cargo.toml) ----
extract_cargo() {
  local dir="$1"
  local cargo="$dir/Cargo.toml"
  [[ ! -f "$cargo" ]] && return

  local in_deps=false
  while IFS= read -r line; do
    [[ "$line" =~ ^\[dependencies\] ]] && { in_deps=true; continue; }
    [[ "$line" =~ ^\[ ]] && { in_deps=false; continue; }
    $in_deps || continue
    local pkg_name=$(echo "$line" | sed 's/[[:space:]]*=[[:space:]]*.*//' | tr -d '"')
    local pkg_ver=$(echo "$line" | grep -o '"[0-9][^"]*"' | sed 's/"//g')
    [[ -z "$pkg_name" || "$pkg_name" =~ ^[[:space:]]*$ ]] && continue
    DEPS+=("{\"name\":\"$pkg_name\",\"version\":\"${pkg_ver:-unknown}\",\"ecosystem\":\"cargo\",\"is_direct\":true,\"project\":\"rust\"}")
    ((TOTAL++))
  done < "$cargo"
}

# ---- Go (go.mod) ----
extract_go() {
  local dir="$1"
  local gomod="$dir/go.mod"
  [[ ! -f "$gomod" ]] && return

  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*module ]] && continue
    [[ "$line" =~ ^[[:space:]]*go[[:space:]] ]] && continue
    local pkg_name=$(echo "$line" | awk '{print $1}')
    local pkg_ver=$(echo "$line" | awk '{print $2}')
    [[ -z "$pkg_name" ]] && continue
    DEPS+=("{\"name\":\"$pkg_name\",\"version\":\"${pkg_ver:-unknown}\",\"ecosystem\":\"go\",\"is_direct\":true,\"project\":\"go\"}")
    ((TOTAL++))
  done < "$gomod"
}

# ============================================================
main() {
  extract_npm "$TARGET"
  extract_pip "$TARGET"
  extract_cargo "$TARGET"
  extract_go "$TARGET"

  local deps_json
  deps_json=$(IFS=','; echo "${DEPS[*]}")

  cat <<EOF
{
  "total_dependencies": $TOTAL,
  "ecosystems": {
    "npm": $(echo "${DEPS[@]}" | grep -c '"ecosystem":"npm"' 2>/dev/null || echo 0),
    "pypi": $(echo "${DEPS[@]}" | grep -c '"ecosystem":"pypi"' 2>/dev/null || echo 0),
    "cargo": $(echo "${DEPS[@]}" | grep -c '"ecosystem":"cargo"' 2>/dev/null || echo 0),
    "go": $(echo "${DEPS[@]}" | grep -c '"ecosystem":"go"' 2>/dev/null || echo 0)
  },
  "dependencies": [$deps_json],
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

main
