# Git 配置指南

## 当前状态

✅ Git 仓库已初始化  
✅ 远程仓库已配置: `git@github.com:OLRainM/DOOS.git`  
✅ 代码已提交到本地  
✅ 标签已创建: `v0.1.0`  
⏳ 需要配置 SSH 密钥才能推送

## SSH 密钥配置步骤

### 1. 检查是否已有 SSH 密钥

```bash
ls -la ~/.ssh
```

如果看到 `id_rsa.pub` 或 `id_ed25519.pub`，说明已有密钥，跳到步骤 3。

### 2. 生成新的 SSH 密钥

```bash
# 使用 ED25519 算法（推荐）
ssh-keygen -t ed25519 -C "your_email@example.com"

# 或使用 RSA 算法
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

按提示操作：
- 按 Enter 使用默认文件位置
- 输入密码（可选，建议设置）
- 再次输入密码确认

### 3. 复制 SSH 公钥

**Linux/Mac:**
```bash
cat ~/.ssh/id_ed25519.pub
# 或
cat ~/.ssh/id_rsa.pub
```

**Windows (PowerShell):**
```powershell
Get-Content ~/.ssh/id_ed25519.pub
# 或
Get-Content ~/.ssh/id_rsa.pub
```

复制输出的整个内容（以 `ssh-ed25519` 或 `ssh-rsa` 开头）。

### 4. 添加 SSH 密钥到 GitHub

1. 登录 GitHub
2. 点击右上角头像 → Settings
3. 左侧菜单选择 "SSH and GPG keys"
4. 点击 "New SSH key"
5. 填写：
   - Title: `DOOS-Dev` (或任意名称)
   - Key: 粘贴刚才复制的公钥
6. 点击 "Add SSH key"

### 5. 测试 SSH 连接

```bash
ssh -T git@github.com
```

如果看到类似以下消息，说明配置成功：
```
Hi OLRainM! You've successfully authenticated, but GitHub does not provide shell access.
```

### 6. 推送代码到 GitHub

```bash
# 推送主分支
git push -u origin main

# 推送标签
git push origin --tags
```

## 常见问题

### Q1: Permission denied (publickey)

**原因**: SSH 密钥未配置或未添加到 GitHub

**解决方案**: 按照上述步骤 1-5 配置 SSH 密钥

### Q2: Could not resolve hostname github.com

**原因**: 网络连接问题

**解决方案**: 
- 检查网络连接
- 尝试使用 HTTPS 方式（见下方）

### Q3: 使用 HTTPS 代替 SSH

如果 SSH 配置有问题，可以临时使用 HTTPS：

```bash
# 修改远程仓库地址为 HTTPS
git remote set-url origin https://github.com/OLRainM/DOOS.git

# 推送代码
git push -u origin main
git push origin --tags
```

**注意**: HTTPS 方式每次推送都需要输入用户名和密码（或 Personal Access Token）。

## 推送后验证

推送成功后，访问以下地址验证：

- 仓库主页: https://github.com/OLRainM/DOOS
- 标签页面: https://github.com/OLRainM/DOOS/tags
- 提交历史: https://github.com/OLRainM/DOOS/commits/main

## 后续操作

推送成功后，建议：

1. ✅ 在 GitHub 上添加项目描述
2. ✅ 添加 Topics 标签（如 `golang`, `microservices`, `distributed-system`）
3. ✅ 创建 GitHub Actions 工作流（CI/CD）
4. ✅ 设置分支保护规则

## Git 常用命令

```bash
# 查看状态
git status

# 查看提交历史
git log --oneline

# 查看远程仓库
git remote -v

# 拉取最新代码
git pull origin main

# 创建新分支
git checkout -b feature/xxx

# 切换分支
git checkout main

# 查看所有分支
git branch -a

# 查看标签
git tag -l
```

## 团队协作规范

### 分支策略

- `main`: 主分支，保护分支，只接受 PR
- `develop`: 开发分支
- `feature/*`: 功能分支
- `bugfix/*`: 修复分支
- `release/*`: 发布分支

### 提交信息规范

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type 类型**:
- `feat`: 新功能
- `fix`: 修复 bug
- `docs`: 文档更新
- `style`: 代码格式调整
- `refactor`: 重构
- `test`: 测试相关
- `chore`: 构建/工具相关

**示例**:
```
feat(order): 实现订单创建接口

- 添加 CreateOrder gRPC 方法
- 实现分库路由逻辑
- 添加本地消息表插入

Closes #123
```

## 需要帮助？

如果遇到问题：
1. 查看 GitHub 官方文档: https://docs.github.com/
2. 查看 Git 官方文档: https://git-scm.com/doc
3. 提交 Issue

---

**最后更新**: 2025-12-24  
**维护者**: DOOS 项目组
