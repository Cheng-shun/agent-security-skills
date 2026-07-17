# Agent Security Skills — 项目上下文

## 项目定位

中文市场首个 AI Agent 安全技能包。解决的核心问题：**AI 编码助手在执行操作时缺乏安全护栏。**

## 目标用户

- 使用 Claude Code / Cursor / Codex 的开发者
- 希望为团队 Agent 建立安全规范的技术负责人
- 关注 AI Agent 安全的独立开发者

## 设计理念

1. **护栏而非审查** — Leading word: `guardrail`，正向保护而非负向拦截
2. **可脱离 Agent** — 所有脚本独立可运行，不绑定特定 AI 工具
3. **四级严重性** — CRITICAL / HIGH / MEDIUM / LOW，精准分级响应
4. **审计不可少** — 所有操作写入结构化日志

## 技术栈

- 技能格式：Markdown (SKILL.md) + YAML 前言
- 脚本语言：Bash（兼容 Git Bash / Linux / macOS）
- 标准：agentskills.io 开放标准
- 安全参考：OWASP Agentic AI Security、EU AI Act

## 技能命名规范

- 文件名：`kebab-case`
- SKILL.md 前言 `name`：与目录名一致
- `description`：英文 + 丰富触发词（model-invoked）
- `tags`：至少包含 `security` + `chinese`

## 质量门

每个技能发布前必须通过：
1. 格式验证：SKILL.md 符合 agentskills.io 规范
2. 脚本测试：正确拦截危险输入，正确放行安全输入
3. 凭证安全：技能自身不包含任何真实凭证
