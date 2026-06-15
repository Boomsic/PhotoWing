# PhotoWing — 拍照助手 iOS App

> 全动态实时摄影指导 + 自动调参 + 新手教学
> 解决男生给女生拍照的所有痛点，全程 AI 自动

## 🤖 三种操作模式

| 模式 | 曝光 | 对焦 | 构图 | 适合 |
|------|------|------|------|------|
| 🤖 **全自动** | ✅ 自动 | ✅ 自动 | 箭头引导 | 完全不会拍照的人 |
| 🎯 **半自动** | ✅ 自动 | ✅ 自动 | 自己控制 | 有点基础 |
| 👋 **手动** | ❌ 手动 | ❌ 手动 | 自己控制 | 专业用户 |

**默认：全自动** — 打开 App 对准人就行了，参数全帮你调好。

## 📖 新手教学（首次打开自动弹出）

```
📸 第一步：对准人物
   把手机对准她，让整个人出现在画面中
   ✅ 检测到人物 → 自动进入下一步

🎯 第二步：跟随指引
   看到屏幕上的箭头了吗？跟着箭头调整手机位置
   ✅ 构图 65 分以上 → 自动进入下一步

⚡ 第三步：按下快门
   顶部评分变绿 → 放心拍！
```

教学过程中每一步都有**实时状态指示**：检测到人没有、构图几分、是否就绪——不用猜。

## 🔧 自动调参（全自动/半自动模式）

| 自动调节 | 工作原理 |
|----------|---------|
| ☀️ 曝光 | 检测人脸亮度→理想值 48%-65%→自动微调 EV，小步防抖 |
| 🔍 对焦 | 追踪人脸位置→移动超过 5% 重新对焦→避免呼吸效应 |
| 📐 构图 | 箭头实时指引→重心偏左→显示 ⬅️→到达绿色区域→触觉反馈 |

## 📱 部署到 iPhone（无需 Mac）

见 `DEPLOY.md`：GitHub → Codemagic → 扫码安装，5 分钟搞定。

## 🏗 项目结构

```
PhotoWing/
├── codemagic.yaml                ← 云构建配置
├── exportOptions.plist           ← 签名配置
├── project.yml                   ← XcodeGen 项目
├── PhotoWing/
│   ├── App/PhotoWingApp.swift
│   ├── Camera/
│   │   ├── CameraManager.swift       ← AVCaptureSession
│   │   ├── CameraPreview.swift       ← SwiftUI 桥接
│   │   └── AutoCameraController.swift ← 🆕 自动曝光+对焦+模式
│   ├── AR/BodyTracker.swift          ← ARKit+Vision 人体追踪
│   ├── Guidance/
│   │   ├── CompositionEngine.swift   ← 三分法构图
│   │   ├── ExposureEngine.swift      ← 人脸测光
│   │   ├── PoseEngine.swift          ← 姿势匹配
│   │   ├── FocusEngine.swift         ← 聚焦+背景
│   │   └── GuidanceOrchestrator.swift ← 总调度
│   ├── Models/
│   │   ├── BodySkeleton.swift        ← 17关节骨骼
│   │   ├── ReferencePose.swift       ← 15个预设姿势
│   │   └── GuidanceResult.swift      ← 五维评分
│   ├── Views/
│   │   ├── ContentView.swift         ← 🆕 集成自动+教学+模式
│   │   ├── TutorialView.swift        ← 🆕 三步新手教学
│   │   ├── GuidanceOverlay.swift     ← 实时叠加层
│   │   ├── PoseGhostView.swift       ← 姿势参考
│   │   ├── ScorePanel.swift          ← 评分面板
│   │   └── PoseLibraryView.swift     ← 姿势库
│   └── Resources/Info.plist
└── README.md
```

**19 个 Swift 文件 · ~3000 行代码**
