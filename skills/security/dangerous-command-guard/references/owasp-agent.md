# OWASP Agentic AI Security — 关键标准摘要

> 基于 [OWASP Agentic AI Security](https://owasp.org/www-project-agentic-ai-security/) 标准
> 摘要日期：2026-07-17

---

## 本 Skill 涉及的 OWASP 标准条目

### AAS-01: 工具调用授权 (Tool Invocation Authorization)

**要求**：所有 Agent 工具调用必须经过授权检查。Agent 不应在不验证上下文的情况下执行破坏性操作。

**本 Skill 实现方式**：
- 步骤 1-2: 解析命令 + 匹配模式库 = 结构化授权检查
- 步骤 3: 四级决策矩阵 = 基于风险的授权

### AAS-02: 命令注入防护 (Command Injection Prevention)

**要求**：Agent 生成的命令必须被视为不可信输入，需经过验证后再执行。

**本 Skill 实现方式**：
- patterns.json 中的正则模式覆盖命令注入常见特征
- 管道执行（curl|sh）提升至 HIGH 级别
- 参数化命令（数组参数）优先于字符串拼接

### AAS-03: 权限边界执行 (Privilege Boundary Enforcement)

**要求**：Agent 应在最小权限环境下运行，禁止越权操作。

**本 Skill 实现方式**：
- sudo 命令自动标记为 HIGH
- chmod 777 系统目录标记为 HIGH
- 提供更安全的替代方案建议

### AAS-04: 审计追踪 (Audit Trail)

**要求**：Agent 所有操作应有完整审计日志。

**本 Skill 实现方式**：
- 所有拦截事件写入 JSONL 审计日志
- 包含时间戳、命令、匹配模式、决策结果

---

## 相关标准

| 标准 | 适用范围 | 链接 |
|------|---------|------|
| OWASP Top 10:2025 | Web 应用安全 | https://owasp.org/www-project-top-ten/ |
| OWASP LLM Top 10 | LLM 应用安全 | https://genai.owasp.org/llm-top-10/ |
| NIST AI RMF | AI 风险管理框架 | https://www.nist.gov/itl/ai-risk-management-framework |
| EU AI Act | AI 法律监管 | https://artificialintelligenceact.eu/ |

---

## 为中国开发者补充

- **中国《生成式人工智能服务管理暂行办法》** 要求生成式 AI 服务提供者承担信息内容安全责任
- Agent 执行危险操作导致的损失，在法律上可能被认定为开发者/运营方的过失
- 建议企业内部建立 Agent 操作审批流程，本 Skill 可作为技术层面的第一道防线
