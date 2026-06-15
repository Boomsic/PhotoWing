import Foundation

// MARK: - 意图→参数映射器

/// 10 维语义向量 → 可执行的拍摄参数
/// 连续映射，不是查表。任何向量都能得到唯一参数组合
struct IntentToParameterMapper {

    /// 融合策略：连续自适应参数 + 美学意图覆盖
    /// 基础参数来自场景分析（ContinuousSceneAnalyzer + IDW）
    /// 美学意图在此基础上叠加偏移
    struct MergedStrategy {
        // 曝光
        var faceBrightnessTarget: ClosedRange<Double>
        var evBias: Double
        var evAdjustSpeed: Double

        // 镜头
        var preferredLens: String              // "0.5x" / "1x" / "2x" / "3x"

        // 机位
        var cameraHeightHint: String           // 空=自动
        var cameraAngleHint: String

        // 构图
        var targetXPosition: CGFloat
        var idealBodyRatio: ClosedRange<CGFloat>
        var headroomRatio: ClosedRange<CGFloat>
        var footAnchorBottom: CGFloat          // 脚离底部的距离 0-0.15

        // 色彩
        var kelvinShift: Double
        var saturationScale: Double
        var contrastGamma: Double
        var shadowLift: Double
        var highlightRolloff: Double

        // 电影
        var cinematicAspectActive: Bool
        var cinematicAspectRatio: CinematicEngine.CinematicConfig.AspectRatio
        var colorGrade: CinematicEngine.CinematicConfig.ColorGrade
        var filmGrain: Double

        // 景深
        var targetDepthOfField: AestheticPresetEngine.AestheticStrategy.DepthOfField
        var focusSensitivity: Double = 0.05    // 对焦敏感度

        // 动态
        var motionTolerance: Double             // 0=锐利优先, 1=容忍模糊

        // 引导
        var photographerGuide: [String]
        var modelGuide: [String]
        var quickTip: String
    }

    // MARK: - 核心映射函数

    /// 输入：场景特征 + 美学意图 → 输出：融合参数
    func merge(
        sceneParams: AdaptiveParameterEngine.PhotoParameters,
        intent: AestheticIntent
    ) -> MergedStrategy {

        var s = MergedStrategy(
            faceBrightnessTarget: sceneParams.faceBrightnessTarget,
            evBias: 0,
            evAdjustSpeed: sceneParams.evAdjustSpeed,
            preferredLens: intent.preferredLens ?? "1x",
            cameraHeightHint: intent.cameraHeightHint ?? "",
            cameraAngleHint: "",
            targetXPosition: sceneParams.targetXPosition,
            idealBodyRatio: sceneParams.idealBodyRatio,
            headroomRatio: sceneParams.headroomRatio,
            footAnchorBottom: 0.08,
            kelvinShift: sceneParams.wbShift * 500,
            saturationScale: intent.saturationOverride ?? 1.0,
            contrastGamma: 1.0,
            shadowLift: 0.05,
            highlightRolloff: 0.02,
            cinematicAspectActive: false,
            cinematicAspectRatio: .widescreen185,
            colorGrade: .none,
            filmGrain: 0,
            targetDepthOfField: .medium,
            motionTolerance: 0.2,
            photographerGuide: [],
            modelGuide: [],
            quickTip: ""
        )

        // === 身体比例 → 镜头 + 机位 + 构图 ===
        if intent.bodyProportion > 0.3 {
            s.preferredLens = "0.5x"
            s.cameraHeightHint = s.cameraHeightHint.isEmpty ? "腰部高度" : s.cameraHeightHint
            s.footAnchorBottom = 0.02 + (1 - intent.bodyProportion) * 0.03  // 脚更贴底
            s.idealBodyRatio = (
                (0.55 + intent.bodyProportion * 0.25)...
                (0.80 + intent.bodyProportion * 0.10)
            )
            s.photographerGuide.append("蹲下，手机放到腰部高度，稍微仰拍")
            s.modelGuide.append("一只脚往前伸，脚尖点地")
            s.quickTip += "蹲下·仰拍·脚贴底"
        } else if intent.bodyProportion < -0.3 {
            s.preferredLens = "1x"
            s.idealBodyRatio = 0.35...0.55
            s.footAnchorBottom = 0.12
            s.photographerGuide.append("正常站立拍，不用刻意蹲下")
        }

        // === 面部渲染 → 镜头 + 距离 + 角度 ===
        if intent.faceRendering > 0.3 {
            s.preferredLens = intent.preferredLens ?? "2x"
            s.targetXPosition = 0.4
            s.idealBodyRatio = (
                max(s.idealBodyRatio.lowerBound, 0.35)...
                min(s.idealBodyRatio.upperBound, 0.55)
            )
            s.cameraAngleHint = "略俯"
            s.photographerGuide.append("退后两步，切换到长焦镜头，手机举到比眼睛略高")
            s.modelGuide.append("下巴微收，脸稍微侧一点")
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "长焦·微俯·收下巴"
        } else if intent.faceRendering < -0.3 {
            s.preferredLens = "1x"
            s.cameraAngleHint = "平视"
            s.modelGuide.append("面向镜头，自然微笑")
        }

        // === 色温 → 白平衡 + 调色 ===
        s.kelvinShift = sceneParams.wbShift * 500 + intent.colorWarmth * 800
        s.saturationScale = intent.saturationOverride ?? (1.0 - abs(intent.colorWarmth) * 0.15)
        if intent.colorWarmth > 0.5 {
            s.colorGrade = .vintageWarm
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "暖调"
        } else if intent.colorWarmth < -0.5 {
            s.colorGrade = .bleachBypass
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "冷调"
        }

        // === 光影戏剧性 → 曝光 + 对比度 ===
        s.shadowLift = 0.05 - intent.lightDrama * 0.15
        s.contrastGamma = 1.0 + intent.lightDrama * 0.3
        s.highlightRolloff = 0.02 + intent.lightDrama * 0.08
        if intent.lightDrama > 0.7 {
            s.faceBrightnessTarget = (0.35...0.55)
            s.photographerGuide.append("找有方向性的光源，让光从侧面打过来")
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "戏剧光影"
        } else if intent.lightDrama < 0.3 {
            s.faceBrightnessTarget = (0.50...0.70)
            s.photographerGuide.append("在柔和均匀的光线下拍摄")
        }

        // 剪影特殊处理
        if intent.isSilhouette {
            s.faceBrightnessTarget = 0.03...0.15
            s.evBias = -2.0
            s.photographerGuide = ["让她站在你和光源之间，对焦在天空而不是人"]
            s.modelGuide = ["侧身站，做出清晰的轮廓动作"]
            s.quickTip = "逆光·对焦天空·轮廓"
        }

        // === 景深 → 对焦策略 ===
        if intent.depthPreference > 0.5 {
            s.targetDepthOfField = .shallow
            s.focusSensitivity = 0.03
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "虚化"
        } else if intent.depthPreference < -0.4 {
            s.targetDepthOfField = .deep
            s.focusSensitivity = 0.07
        }

        // === 构图动态 → 画面位置 + 留白 ===
        s.targetXPosition = 0.333 + intent.compositionDynamism * 0.25
        if intent.compositionDynamism > 0.5 {
            s.photographerGuide.append("人物偏一侧，另一侧留出空间")
            s.modelGuide.append("不要看镜头，看画面外的方向")
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "不看镜头"
        }

        // === 质感 → 胶片颗粒 + 锐化 ===
        s.filmGrain = max(0, intent.textureQuality * 0.06)
        if intent.textureQuality > 0.5 {
            s.cinematicAspectActive = true
            s.colorGrade = s.colorGrade == .none ? .tealOrange : s.colorGrade
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "胶片质感"
        }

        // === 动态程度 → 快门策略 ===
        s.motionTolerance = intent.dynamismLevel * 0.8
        if intent.dynamismLevel > 0.5 {
            s.photographerGuide.append("用连拍模式，抓取自然瞬间")
            s.modelGuide.append("自然走动，不用刻意停住")
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "抓拍"
        }

        // === 年代风格 → 调色 + 遮幅 ===
        if intent.eraStyle > 0.5 {
            s.cinematicAspectActive = true
            s.cinematicAspectRatio = .widescreen185
            if intent.eraStyle > 0.7 {
                s.colorGrade = .crossProcess
                s.filmGrain = max(s.filmGrain, 0.05)
            } else {
                s.colorGrade = .vintageWarm
            }
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "复古"
        }

        // === 情绪基调 → 综合调性 ===
        if intent.emotionalTone > 0.6 {
            s.shadowLift += 0.10
            s.contrastGamma -= 0.10
            s.faceBrightnessTarget = (s.faceBrightnessTarget.lowerBound + 0.03)...(s.faceBrightnessTarget.upperBound + 0.05)
            s.modelGuide.append("放松微笑，自然就好")
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "柔美"
        } else if intent.emotionalTone < -0.5 {
            s.shadowLift -= 0.05
            s.contrastGamma += 0.10
            s.modelGuide.append("表情冷淡一些，不用笑")
            s.quickTip += (s.quickTip.isEmpty ? "" : "·") + "冷峻"
        }

        // === 电影感综合 ===
        if intent.textureQuality > 0.4 || intent.eraStyle > 0.4 || intent.lightDrama > 0.5 {
            s.cinematicAspectActive = true
            s.cinematicAspectRatio = .widescreen235
            if s.colorGrade == .none { s.colorGrade = .tealOrange }
            s.filmGrain = max(s.filmGrain, 0.03)
        }

        // === 黑白覆盖 ===
        if intent.isMonochrome {
            s.colorGrade = .monochrome
            s.saturationScale = 0
            s.quickTip = "黑白·质感"
        }

        // === 清理 quickTip ===
        if s.quickTip.hasPrefix("·") { s.quickTip.removeFirst() }

        return s
    }

    // 兼容旧接口的 Strategy 生成
    func toSceneStrategy(_ merged: MergedStrategy) -> SceneAnalyzer.SceneStrategy {
        SceneAnalyzer.SceneStrategy(
            faceBrightnessTarget: merged.faceBrightnessTarget,
            evAdjustSpeed: merged.evAdjustSpeed,
            maxEV: merged.evBias > 0 ? 1.0 : 0.5,
            minEV: merged.evBias < 0 ? -1.0 : -0.5,
            focusSensitivity: merged.targetDepthOfField == .shallow ? 0.03 : 0.06,
            idealBodyRatio: merged.idealBodyRatio,
            headroomRatio: merged.headroomRatio,
            hint: merged.quickTip
        )
    }
}
