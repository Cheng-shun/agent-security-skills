# 误报处理指南

## 误报是现实

任何自动密钥检测工具都会产生误报。本 Skill 的设计哲学是"宁可误报，不可漏报"——但是误报需要优雅处理，否则用户会关闭检测。

---

## 自动降级规则（已内置在 scan.sh 中）

当检测到以下上下文信号时，严重级别自动降级：

| 上下文信号 | 原始级别 | 降级后 | 原因 |
|-----------|---------|--------|------|
| `EXAMPLE_KEY`、`example`、`placeholder` | CRITICAL | FALSE_POSITIVE | 显然是示例代码 |
| `your-key-here`、`TODO`、`REPLACE_ME` | CRITICAL | FALSE_POSITIVE | 占位符 |
| 值以 `xxx` 或 `test` 开头 | CRITICAL | FALSE_POSITIVE | 测试数据 |
| `process.env.VAR` | HIGH | MEDIUM | 环境变量引用是安全的 |
| `${VARIABLE}` | HIGH | MEDIUM | Shell/Terraform 变量引用 |
| 在注释行中（`#`、`//`、`/*`） | HIGH | MEDIUM | 注释不太可能是真实密钥 |
| 字符串长度 < 20 | HIGH | MEDIUM | 太短的字符串不可能是有效密钥 |

---

## 白名单机制

在项目根目录创建 `.secret-allowlist` 文件（gitignore 它！），每行一个允许的哈希值：

```
# .secret-allowlist
# 格式: SHA256_of_matched_string  # 备注
abc123def456...  # CI 测试用的假 AWS key
789ghi012jkl...  # 文档中的示例 token
```

scan.sh 读取此文件（如果存在），跳过匹配的哈希。

---

## 常见误报场景及处理

### 场景 1：测试文件中的假密钥

```python
# test_config.py
API_KEY = "sk-test-1234567890abcdef"  # ← 会触发检测
```

**处理**：
- 已在代码中添加 `test` 和 `fake` 信号 → 自动降级为 FALSE_POSITIVE
- 如果仍未过滤（边缘情况），在 `.secret-allowlist` 中添加白名单

### 场景 2：文档中的代码示例

```markdown
## 配置示例
export ANTHROPIC_AUTH_TOKEN="sk-ant-api03-xxx"  # ← 会触发检测
```

**处理**：
- `xxx` 信号 → 自动降级为 FALSE_POSITIVE
- 建议在文档中使用 `$ANTHROPIC_AUTH_TOKEN` 环境变量引用

### 场景 3：Base64 编码的非密钥内容

```
s9f8H2kLm4Qp7Rt3Yw6XzA1Bc5De0FgHiJkLmNoPqRsTuVwXyZ=  # ← 高熵值触发
```

**处理**：
- 熵值检查默认标记为 MEDIUM（不阻止写入）
- 如果确实是误报，白名单处理

### 场景 4：私钥文件但确实需要提交（如用于测试的假密钥）

```
tests/fixtures/fake-ssh-key  # ← BEGIN RSA PRIVATE KEY 触发
```

**处理**：
- 文件名包含 `fake`/`test` → 保留 CRITICAL 但允许用户跳过
- 更安全做法：用 `ssh-keygen` 的测试模式生成标记为 `TEST KEY - NOT A REAL KEY` 的密钥

---

## 企业级误报管理

对于团队使用，建议：

1. **集中白名单**：在团队 shared repo 中维护 `.secret-allowlist`（仍然 gitignore）
2. **CI 报告**：每周自动运行 `scan.sh --all`，生成误报趋势报告
3. **分类标签**：对每个白名单条目标注原因（测试 / 文档 / 已撤销 / 假密钥）
