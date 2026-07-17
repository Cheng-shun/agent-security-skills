---
name: dependency-audit
description: 对项目依赖进行安全审计——漏洞扫描、typosquatting 检测、许可证合规、供应链风险评估。支持 npm、pip、cargo、go mod。Use when the user wants to audit dependencies, check for vulnerabilities, verify package integrity, or mentions "依赖审计", "供应链安全", "npm audit", "dependency check", "supply chain".
metadata:
  pattern: pipeline
  category: security
  stages:
    - dependency-discovery
    - vulnerability-scan
    - typosquatting-check
    - license-audit
    - risk-report
  interaction: confirm
  steps:
    - parse-manifest
    - resolve-versions
    - scan-vulnerabilities
    - check-typosquatting
    - audit-licenses
    - generate-report
tags:
  - security
  - supply-chain
  - dependencies
  - vulnerability
  - chinese
license: MIT
allowed-tools:
  - Bash
  - Read
  - Glob
  - WebSearch
version: 0.1.0
---

# Dependency Audit — 依赖安全审计

**Leading word: _supply chain_**（供应链）— 不只看"有没有漏洞"，而是追查每个依赖从何而来、谁在维护、是否值得信任。现代软件 80% 的代码来自第三方依赖，供应链是最大的攻击面。

> Pipeline 模式 — 5 个有序阶段，每个阶段有验证门控，任意阶段失败即终止后续阶段。

```
依赖发现 → 漏洞扫描 → 拼写欺诈检测 → 许可证审计 → 风险报告
  │            │           │            │           │
  └─ Gate 1 ───┘─ Gate 2 ──┘─ Gate 3 ───┘─ Gate 4 ──┘
```

---

## 阶段 1：依赖发现 (Dependency Discovery)

### 输入
项目根目录中的依赖清单文件。

### 流程

1. 搜索项目中的依赖清单文件：
   - `package.json` → npm 依赖
   - `requirements.txt` / `pyproject.toml` → Python 依赖
   - `Cargo.toml` → Rust 依赖
   - `go.mod` → Go 依赖
   - `Gemfile` → Ruby 依赖
   - `pom.xml` / `build.gradle` → Java 依赖

2. 解析每个文件，提取：
   - 包名、当前版本、版本范围
   - 是否为直接依赖还是传递依赖
   - 来源（npm registry / PyPI / crates.io 等）

3. 运行 `scripts/extract-deps.sh` 生成结构化依赖列表。

**门控 1**：依赖列表非空。如果项目无第三方依赖 → 跳过后续阶段，报告"无外部依赖"。

**完成标准**：`deps.json` 已生成，包含 `[{name, version, ecosystem, is_direct}]`。

---

## 阶段 2：漏洞扫描 (Vulnerability Scan)

### 流程

1. 对每个依赖，查询已知漏洞数据库：
   - npm: `npm audit --json` 或 OSV API
   - Python: `pip-audit` 或 Safety DB
   - Rust: `cargo audit` 或 RustSec Advisory DB
   - Go: `govulncheck` 或 OSV API

2. 如果原生工具不可用，使用 OSV (Open Source Vulnerabilities) API：
   ```bash
   curl -X POST https://api.osv.dev/v1/querybatch -d '{"queries": [...]}'
   ```

3. 对每个漏洞记录：CVE 编号、CVSS 评分、受影响版本范围、修复版本。

### 严重级别映射

| CVSS 范围 | 严重级别 | 默认操作 |
|-----------|---------|---------|
| 9.0-10.0 | CRITICAL | 阻止，要求立即修复 |
| 7.0-8.9 | HIGH | 警告，建议本周内修复 |
| 4.0-6.9 | MEDIUM | 提示，建议本月修复 |
| 0.1-3.9 | LOW | 告知 |

**门控 2**：无 CRITICAL 漏洞。如有 → 阻止后续阶段，要求先修复。

---

## 阶段 3：拼写欺诈检测 (Typosquatting Check)

### 流程

拼写欺诈（typosquatting）是攻击者注册与流行包名相似的恶意包，利用开发者拼写错误进行供应链攻击。

1. 对每个直接依赖，计算与 Top 1000 流行包名的 Levenshtein 距离
2. 标记距离 1-2 的依赖为"可疑"
3. 检查包名是否包含以下模式：
   - 常见拼写错误：`requets` vs `requests`、`electorn` vs `electron`
   - 字符替换：`0` 替换 `o`、`1` 替换 `l`
   - 多余连字符：`react-native` vs `reactnative`
   - 范围混淆：`@angular/core` vs `angular-core`
4. 使用 `scripts/typosquat-check.sh` 自动检测

### 额外检查

- 包的发布时间 < 30 天 → 标记为"新包，需人工审查"
- 包的周下载量 < 1000 → 标记为"低流行度"
- 包的维护者数量 = 1 → 标记为"单人维护风险"
- GitHub 仓库 ⭐ < 10 → 标记为"低社区认可度"

**门控 3**：无可疑依赖（距离 ≤ 2 且下载量 < 1000）。如有 → 展示对比表，要求用户确认。

---

## 阶段 4：许可证审计 (License Audit)

### 流程

1. 查询每个依赖的许可证类型
2. 与项目的 `allowed-licenses` 配置对比（默认：MIT, Apache-2.0, BSD-2/3-Clause, ISC, Unlicense）
3. 标记以下情况：
   - **Copyleft 强传染**：GPL-3.0, AGPL-3.0 → 如果项目是商业闭源，标记为 CRITICAL
   - **Copyleft 弱传染**：LGPL, MPL-2.0 → MEDIUM
   - **未知许可证**：无法查到的 → HIGH（需要人工审查）
   - **禁止商用**：CC-BY-NC, 自定义"非商业"许可证 → 商业项目中标记为 CRITICAL

4. 检查许可证兼容性：两个 GPL 变体可能不兼容，导致法律风险。

**门控 4**：无商业项目 + GPL/AGPL 冲突。如有 → 展示冲突表。

---

## 阶段 5：风险报告 (Risk Report)

### 输出格式

生成结构化报告 `dependency-audit-report.json`（格式见 `references/report-format.md`），包含：

```markdown
## 依赖安全审计报告

**项目**：{project_name}
**审计时间**：{timestamp}
**依赖总数**：{total}（直接 {direct} + 间接 {transitive}）

### 🔴 需要立即处理
- {CRITICAL 漏洞和许可证冲突}

### 🟠 本周处理
- {HIGH 漏洞和可疑包}

### 🟡 建议处理
- {MEDIUM 问题}

### 📊 风险评分
- 综合评分：{score}/100
- 漏洞风险：{vuln_score}/40
- 供应链风险：{supply_chain_score}/30
- 许可证风险：{license_score}/30
```

---

## 参考文件

- `scripts/extract-deps.sh` — 依赖清单解析脚本
- `scripts/typosquat-check.sh` — 拼写欺诈检测脚本
- `references/osv-api-guide.md` — OSV API 使用指南
- `references/license-compatibility.md` — 开源许可证兼容性矩阵
- `references/report-format.md` — 审计报告 JSON Schema
- `examples/audit-cases.md` — 6 个真实供应链攻击案例
