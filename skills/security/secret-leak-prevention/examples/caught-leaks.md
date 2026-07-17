# 8 个真实密钥泄露拦截案例

> 以下案例来自开源项目和实际使用场景（脱敏处理后）

---

## 案例 1：AWS Key 误入前端代码

**文件**：`src/config.js`

```javascript
// 被拦截的内容
const AWS_CONFIG = {
  accessKeyId: "AKIAIOSFODNN7EXAMPLE",     // ← SEC-010 触发
  secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  region: "us-east-1"
}
```

**拦截级别**：CRITICAL (SEC-010)

**用户反应**："这是我从 AWS 文档复制的示例 key，但 Scanner 不知道这是假的——拦截是对的。"

**修正**：替换为 `process.env.AWS_ACCESS_KEY_ID` 环境变量引用。

---

## 案例 2：GitHub Token 在 commit message 中

**场景**：用户在 `git commit -m` 中粘贴了包含 token 的 curl 命令

```
git commit -m "curl -H 'Authorization: token ghp_1A2b3C4d5E6f7G8h9I0j' https://api.github.com/user"
```

**拦截级别**：CRITICAL (SEC-020)

**后果**：如果真的 commit 了，token 将出现在 git log 中。需要 `git filter-branch` 才能清除。

**提醒**：GitHub 会自动检测公开仓库中的 token 并作废，但私有仓库不会。

---

## 案例 3：.env 文件被 Agent 意外写入

**文件**：`.env.local`

```
DATABASE_URL=postgresql://admin:MyRealPassword123@db.example.com/production
```

**拦截级别**：HIGH (SEC-031)

**场景**：Agent 在帮助用户配置数据库时，"贴心"地写入了真实密码。

**修正**：引导用户使用 `DATABASE_URL=${DATABASE_URL}` 环境变量。

---

## 案例 4：Python 代码中的硬编码 API Key

**文件**：`app/services/ai.py`

```python
import openai
openai.api_key = "sk-proj-abc123def456ghi789jkl012mno345pqr"  # ← SEC-002 触发
```

**拦截级别**：CRITICAL (SEC-002)

**用户反馈**："我知道不应该硬编码，但觉得反正是私有仓库……结果 Scanner 拦了，让我意识到了风险。"

**修正**：
```python
import os
import openai
openai.api_key = os.getenv("OPENAI_API_KEY")
```

---

## 案例 5：SSH 私钥被 Agent 写入文档

**文件**：`docs/deployment.md`

```
## SSH 配置
将以下私钥保存到 ~/.ssh/id_rsa:

-----BEGIN RSA PRIVATE KEY-----          ← SEC-040 触发
MIIEpAIBAAKCAQEA...
```

**拦截级别**：CRITICAL (SEC-040)

**Agent 的意图**：Agent 想帮助用户写一份"完整的部署文档"。

**修正**：文档中只写 `ssh-keygen` 命令，不包含实际私钥内容。

---

## 案例 6：日志文件中的 JWT Secret

**文件**：`logs/debug.log`（Agent 生成的调试日志）

```
2026-07-17 10:23:45 DEBUG JWT_SECRET=my-super-secret-jwt-signing-key  # ← SEC-042 触发
```

**拦截级别**：HIGH (SEC-042)

**场景**：Agent 在调试时把环境变量 dump 到了日志文件。

**修正**：日志脱敏——`JWT_SECRET=***REDACTED***`

---

## 案例 7：MongoDB 连接字符串

**文件**：`docker-compose.yml`

```yaml
environment:
  MONGO_URI: mongodb+srv://admin:P@ssw0rd!23@cluster.mongodb.net/mydb  # ← SEC-032 触发
```

**拦截级别**：HIGH (SEC-032)

**修正**：使用 Docker secrets 或 `.env` 文件（不提交到 Git）

```yaml
environment:
  MONGO_URI: ${MONGO_URI}
```

---

## 案例 8：微信小程序 AppSecret 泄露

**文件**：`miniprogram/utils/api.js`

```javascript
const APP_SECRET = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"  // ← SEC-062 触发，32位 hex
```

**拦截级别**：CRITICAL (SEC-062)

**场景**：微信小程序开发者把 AppSecret 直接写在了前端代码中——这是特别危险的，因为小程序前端代码可以被反编译。

**用户反应**："以前不知道前端代码会被反编译，Scanner 救了我。"

**修正**：AppSecret 只能在后端使用，前端通过后端 API 间接调用微信服务。

---

## 统计

| 案例 | 密钥类型 | 严重级别 | 如果未被拦截的后果 |
|------|---------|---------|------------------|
| 1 | AWS Key | CRITICAL | 前端代码泄露 → AWS 资源被劫持 |
| 2 | GitHub Token | CRITICAL | git 历史泄露 → Token 作废 |
| 3 | DB Password | HIGH | 数据库被未授权访问 |
| 4 | OpenAI Key | CRITICAL | API 费用被盗刷 |
| 5 | SSH 私钥 | CRITICAL | 服务器被控制 |
| 6 | JWT Secret | HIGH | JWT 可被伪造 |
| 7 | MongoDB URI | HIGH | 数据库被远程连接 |
| 8 | 微信 AppSecret | CRITICAL | 用户数据泄露 |

> 8 个案例中，5 个是 Agent 在"帮助"用户时意外产生的。这验证了本 Skill 的核心假设：**AI Agent 需要安全护栏，因为它的"好心"足以制造安全事故。**
