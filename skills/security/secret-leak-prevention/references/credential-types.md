# 各平台密钥类型完整对照表

> 本文档是所有已知 API 密钥/凭证格式的完整参考，供密钥扫描引擎使用。
> 最后更新：2026-07-17

---

## 🤖 AI/LLM 平台

| 平台 | 密钥前缀 | 格式 | 示例 | 权限范围 |
|------|---------|------|------|---------|
| Anthropic | `sk-ant-api-` | `sk-ant-api-` + 32+ chars | `sk-ant-api03-abc...` | 调用 Claude API |
| Anthropic Admin | `sk-ant-admin-` | `sk-ant-admin-` + 32+ chars | — | 组织管理 |
| OpenAI | `sk-proj-` / `sk-` | `sk-` + 32+ chars | `sk-proj-abc...` | 模型调用 |
| DeepSeek | `sk-` | `sk-` + 32 chars | `sk-a1b2c3...` | 模型调用 |
| Google AI | `AIza` | `AIza` + 35 chars | `AIzaSyD...` | Gemini API |
| Cohere | — | 32+ chars | — | 模型调用 |
| Groq | `gsk_` | `gsk_` + 32+ chars | — | 模型调用 |
| Together AI | — | 32+ chars | — | 模型调用 |

---

## ☁️ 云服务

| 平台 | 密钥类型 | 格式 | 前缀 |
|------|---------|------|------|
| AWS | Access Key ID | 20 chars | `AKIA` |
| AWS | Secret Access Key | 40 chars | — |
| Azure | Storage Connection String | URI 格式 | `DefaultEndpointsProtocol=` |
| GCP | Service Account JSON | JSON 文件 | `"type": "service_account"` |
| 阿里云 | RAM AccessKey | 16-20 chars | `LTAI` |
| 腾讯云 | SecretId | 32-48 chars | `AKID` |
| 华为云 | AK/SK | — | — |

---

## 📝 版本控制

| 平台 | Token 类型 | 格式 | 示例 |
|------|-----------|------|------|
| GitHub | Classic PAT | `ghp_` + 36 chars | `ghp_abc...` |
| GitHub | Fine-grained PAT | `github_pat_` + 36+ chars | `github_pat_11A...` |
| GitHub | OAuth App Secret | `ghs_` + 36 chars | `ghs_abc...` |
| GitLab | PAT | `glpat-` + 20+ chars | `glpat-abc...` |
| GitLab | Deploy Token | `gldt-` + 20+ chars | — |
| Bitbucket | App Password | — | — |

---

## 🗄️ 数据库

| 数据库 | 连接字符串格式 |
|--------|--------------|
| MySQL | `mysql://user:password@host:port/db` |
| PostgreSQL | `postgresql://user:password@host:port/db` |
| MongoDB | `mongodb+srv://user:password@host/db` |
| Redis | `redis://user:password@host:port` |
| SQL Server | `Server=host;Database=db;User Id=user;Password=pass;` |

---

## 🔑 加密密钥

| 类型 | 头部标识 |
|------|---------|
| RSA Private Key | `-----BEGIN RSA PRIVATE KEY-----` |
| DSA Private Key | `-----BEGIN DSA PRIVATE KEY-----` |
| EC Private Key | `-----BEGIN EC PRIVATE KEY-----` |
| OpenSSH Private Key | `-----BEGIN OPENSSH PRIVATE KEY-----` |
| PGP Private Key | `-----BEGIN PGP PRIVATE KEY-----` |
| Generic PEM | `-----BEGIN PRIVATE KEY-----` |

---

## 🇨🇳 中国市场特供

| 平台 | 密钥格式 | 备注 |
|------|---------|------|
| 微信 AppSecret | 32 位 hex | 公众号/小程序 |
| 支付宝 AppPrivateKey | RSA 私钥 | 开放平台 |
| 百度 AI | 24+ chars | 自然语言/图像识别 |
| 讯飞开放平台 | — | 语音识别 |
| 七牛云 AK/SK | — | 对象存储 |
| 又拍云 | — | CDN/存储 |

---

## 🔍 通用模式

| 模式 | 正则（简化） | 误报风险 |
|------|-------------|---------|
| `password = "..."` | 高 | 高 — 需要上下文过滤 |
| `secret: "..."` | 高 | 中 |
| `api_key = "..."` | 高 | 中 |
| 高熵值 base64 (40+ chars) | 中 | 低 |
| Bearer token | 中 | 低 |

> ⚠️ 通用模式必须配合上下文分析和熵值检查，独立使用会大量误报。
