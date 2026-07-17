# Agent Security Skills — AI Agent 安全技能包

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Agent Skills Standard](https://img.shields.io/badge/Standard-Agent%20Skills%20Spec-blue)](https://agentskills.io/specification)

> 🛡️ "围栏优于马力"（Fences over Horsepower）— 安全不是 Agent 的附属功能，而是基础设施。

**中文市场首个 Agent 安全技能集合**，为 AI 编码助手（Claude Code、Cursor、Codex、Gemini CLI）提供生产级安全护栏。每个技能遵循 [Agent Skills 开放标准](https://agentskills.io/specification)，可脱离特定 AI 工具独立运行。

---

## 已发布的 Skills

| # | 技能 | 设计模式 | 触发时机 | 检测能力 |
|---|------|---------|---------|---------|
| 1 | `dangerous-command-guard` | Reviewer | Bash 执行前 | 19 种危险命令 + 四级严重性 + OWASP 合规 |
| 2 | `secret-leak-prevention` | Reviewer | Write/Edit 写入前 | 27 种密钥格式 + 熵值检测 + 中国平台特供 |
| 3 | `prompt-injection-detector` | Reviewer | WebFetch/外部输入时 | 8 类注入向量 + 60+ 中英文模式 + 五层信任边界 |
| 4 | `dependency-audit` | Pipeline | 依赖变更时 | npm/pip/cargo/go + CVE + typosquatting + 许可证审计 |
| 5 | `agent-behavior-logger` | Tool Wrapper | 全程运行时 | 统一 JSON Schema + 跨 Skill 关联查询 + 每日报告 |

> ✅ 5/5 技能已发布 · 8 个独立脚本 · 41 个真实案例 · 完整审计链路

---

## 防护链路

```
外部输入          命令执行          文件写入          依赖引入          全程
    │                │                │                │              │
    ▼                ▼                ▼                ▼              ▼
注入检测 ──────→ 命令护栏 ──────→ 密钥扫描 ──────→ 依赖审计 ──→ 行为日志
INJ-xxx         CRIT-xxx         SEC-xxx          DEP-xxx      统一 JSONL
```

---

## 快速安装

### Claude Code

```bash
git clone https://github.com/Cheng-shun/agent-security-skills.git ~/.claude/skills/agent-security-skills
```

### 作为独立脚本使用

```bash
# 命令安全检查
echo "rm -rf /" | bash skills/security/dangerous-command-guard/scripts/guard.sh

# 密钥泄露扫描
bash skills/security/secret-leak-prevention/scripts/scan.sh --all
```

---

## 技能结构

```
skill-name/
├── SKILL.md           # YAML 前言 + Markdown 工作流指令
├── scripts/           # 独立可执行脚本
├── references/        # 参考文档（OWASP、分类标准等）
└── examples/          # 使用案例
```

---

## 设计原则

- **中文优先** — 面向中文开发者，覆盖中国市场平台（微信、阿里云、腾讯云）
- **最小权限** — 每个技能仅使用必要的 `allowed-tools`
- **可脱离 Agent** — 所有脚本均可独立运行，不绑定特定 AI 工具
- **审计优先** — 所有拦截事件写入结构化 JSONL 日志
- **遵循标准** — 严格遵循 [agentskills.io](https://agentskills.io/specification) 规范

---

## 许可证

MIT © 2026 Cheng-shun
