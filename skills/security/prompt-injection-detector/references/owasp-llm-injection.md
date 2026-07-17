# OWASP LLM01: Prompt Injection — 指南摘要

> 基于 [OWASP Top 10 for LLM Applications](https://genai.owasp.org/llm-top-10/)
> 摘要日期：2026-07-17

---

## LLM01: Prompt Injection 概述

**严重级别**：🔴 Critical

**描述**：提示注入攻击通过精心构造的输入覆盖或操纵 LLM 的系统提示，使攻击者能够绕过安全限制、执行未授权操作或窃取数据。

### 两种类型

| 类型 | 描述 | 示例 |
|------|------|------|
| **直接注入** | 直接覆盖系统提示 | "Ignore all previous instructions and..." |
| **间接注入** | 通过外部内容传递恶意指令 | 网页/MCP输出/文件中嵌入指令 |

---

## 防御措施（OWASP 推荐）

### 1. 输入隔离与清理
- 区分系统提示与用户数据
- 使用分隔符明确标记不可信内容
- 对用户输入进行清理（移除控制字符、特殊标签）

**本 Skill 实现**：信任层级模型 (L0-L5) + injection-scanner.sh

### 2. 最小权限原则
- Agent 只拥有完成当前任务所必需的最小权限
- 危险操作需要额外授权

**本 Skill 实现**：结合 `dangerous-command-guard` 和 `secret-leak-prevention`

### 3. 输出验证
- 验证 Agent 的输出不包含未授权的操作
- 对工具调用参数进行二次验证

**本 Skill 实现**：风险评分三维模型（意图明确性 × 危害程度 × 隐蔽程度）

### 4. 人类参与循环 (Human-in-the-Loop)
- 高风险操作需要人类确认
- 定期审计 Agent 的操作日志

**本 Skill 实现**：CRITICAL/HIGH 级别要求用户确认

---

## 中国《生成式人工智能服务管理暂行办法》相关条款

| 条款 | 要求 | 本 Skill 对应 |
|------|------|-------------|
| 第四条 | 提供者应承担信息内容安全主体责任 | L3+ 内容强制扫描 |
| 第十条 | 应采取有效措施防范违法违规信息的生成和传播 | 8类注入向量检测 |
| 第十四条 | 应建立投诉举报机制 | 审计日志（agent-behavior-logger） |

---

## 参考资源

- [OWASP LLM Top 10](https://genai.owasp.org/llm-top-10/)
- [NIST AI 600-1: Adversarial Machine Learning](https://csrc.nist.gov/pubs/ai/600/1/final)
- [MITRE ATLAS: Prompt Injection](https://atlas.mitre.org/techniques/AML.T0051/)
