# PhotoWing 拍照助手 — iPhone 部署完整教程

> 你没有 Mac，只有 Linux + iPhone 16。
> 这条路：GitHub → Codemagic 云构建 → 扫码安装，**完全不需要 Mac**。

---

## 总览

```
你的 Linux  →  git push  →  GitHub  →  Codemagic  →  iPhone 扫码安装
  现在          1步          免费          自动构建        2分钟内
```

## 前置准备清单

- [ ] GitHub 账号（免费）
- [ ] Apple ID（免费，不需要开发者账号）
- [ ] iPhone 16（iOS 18+）
- [ ] iPhone 上已装 TestFlight（App Store 下载，用于后续版本更新）

---

## 第一步：推送代码到 GitHub

```bash
cd /home/sha/ai/PhotoWing

# 初始化 Git（如果还没做）
git init
git add -A
git commit -m "PhotoWing v1.0: AI 实时拍照指导"

# 创建 GitHub 仓库
# 1. 打开 https://github.com/new
# 2. 仓库名填 PhotoWing
# 3. 不要勾选 Initialize this repository（我们是已有项目）
# 4. 点 Create repository

# 关联并推送
git remote add origin https://github.com/你的用户名/PhotoWing.git
git branch -M main
git push -u origin main
```

---

## 第二步：配置 Codemagic

### 2.1 登录 Codemagic

1. 打开 https://codemagic.io
2. 点 **Sign up** → 用 **GitHub** 账号授权登录
3. 首次登录免费套餐：**500 分钟/月**（够你构建 50+ 次）

### 2.2 连接仓库

1. 点 **Add application**
2. 选择 **PhotoWing** 仓库
3. Codemagic 自动检测到 `codemagic.yaml`，点 **Check configuration**

### 2.3 配置 Apple 签名

1. 在项目设置页 → **iOS code signing**
2. 选择 **Automatic code signing**
3. 输入你的：
   - Apple ID 邮箱
   - App 专用密码（去 https://appleid.apple.com → 安全 → App 专用密码 → 生成一个，名字填 "Codemagic"）

> ⚠️ App 专用密码不是你登录 iCloud 的密码！是 16 位字符，格式如 `xxxx-xxxx-xxxx-xxxx`

### 2.4 启动构建

1. 点 **Start your first build**
2. 选择 workflow: **PhotoWing iOS Build**
3. 点 **Start build**

构建过程约 **5-8 分钟**。你可以在 Codemagic 页面实时看构建日志。

---

## 第三步：安装到 iPhone

### 3.1 获取安装链接

构建完成后，Codemagic 页面会出现：
- 一个 **二维码**
- 一个 **安装链接**

### 3.2 iPhone 扫码安装

1. 用 iPhone 相机扫二维码
2. 弹出 "在'拍照助手'中安装？" → 点 **安装**
3. App 图标出现在桌面

### 3.3 信任开发者证书（第一次安装必须做）

1. iPhone 打开 **设置**
2. **通用** → **VPN 与设备管理**
3. 找到你的 Apple ID 邮箱
4. 点 **信任 "你的邮箱"**
5. 确认信任

搞定。打开桌面上的 "拍照助手" 图标。

### 3.4 授予权限

首次打开会依次弹出权限请求，全部点 **允许**：
- 相机 — 必须允许（核心功能）
- 麦克风 — 允许（语音指令）
- 语音识别 — 允许（听懂她说的话）
- 相册 — 允许（保存照片）

---

## 日常使用流程

### 更新 App（新版本）

你在 Linux 上改代码 → `git push` → Codemagic 可以设置自动触发构建，也可以在 Codemagic 页面手动点 **Start new build**。构建完在 iPhone 上重新扫码安装（覆盖旧版本）。

### 7 天重签

免费 Apple ID 的 App 证书 7 天过期。解决方法：
- 在 Codemagic 上点 **Rebuild**（1 分钟）
- iPhone 上重新扫码安装
- 或者花 $99/年注册 Apple Developer → 证书 1 年有效

---

## 故障排除

### 构建失败

| 错误 | 解决 |
|------|------|
| Code signing failed | 检查 App 专用密码是否正确，Apple ID 是否开启了双重认证 |
| Provisioning profile expired | 在 Codemagic 项目设置里点 Refresh signing |
| Build timeout (>30min) | Codemagic 免费版限制 30 分钟，项目应该 5-8 分钟完成 |
| Xcode version mismatch | 检查 `codemagic.yaml` 中 `xcode: 16.0` 是否可用 |

### 安装失败

| 错误 | 解决 |
|------|------|
| 无法验证 App | 设置 → 通用 → VPN与设备管理 → 信任证书 |
| 安装后闪退 | iOS 版本太低？需要 iOS 16+ |
| 无法下载 | 检查 iPhone 网络连接 |

### App 内问题

| 问题 | 原因 |
|------|------|
| 人体追踪不工作 | iPhone 16 完全支持 ARKit 3，确认相机权限已授予 |
| 语音指令没反应 | 点顶部麦克风图标，确认语音识别权限已授予 |
| 画面卡顿 | 后台 App 太多？重启 App 试试 |

---

## 项目结构速查

```
PhotoWing/
├── codemagic.yaml             ← Codemagic 自动构建
├── exportOptions.plist        ← 签名配置
├── project.yml                ← XcodeGen 项目定义
├── PhotoWing/
│   ├── App/PhotoWingApp.swift
│   ├── Camera/                 ← 相机·自动对焦·电影滤镜
│   ├── AR/BodyTracker.swift   ← ARKit 人体骨骼追踪
│   ├── Guidance/               ← 8 个指导引擎 + 意图解析
│   ├── Models/                 ← 数据模型 + 场景分析
│   ├── Views/                  ← UI 界面
│   └── Resources/
│       ├── Info.plist
│       └── Shaders/CinematicFilter.metal  ← GPU 调色着色器
├── DEPLOY.md                  ← 本文件
└── README.md
```

**30 个 Swift 文件 · ~5000 行代码**

---

## 技术规格

| 项目 | 值 |
|------|-----|
| 最低 iOS | 16.0 |
| 推荐设备 | iPhone 12 Pro 及以上 |
| 人体追踪 | A12 Bionic+（iPhone XS/XR+）|
| LiDAR 深度 | iPhone 16 Pro（Pro 机型专属） |
| 语音识别 | 设备端本地，不上传 |
| 电影调色 | Metal GPU 实时 (~60fps) |
| 包体积 | ~15MB |
