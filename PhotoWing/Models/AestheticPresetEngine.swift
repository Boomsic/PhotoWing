import Foundation
import CoreGraphics

// MARK: - 美学指令系统

/// 她的一句话 → 全参数映射
/// "腿长一点" "脸小一点" "电影感" "港风" "日系清新" ...

enum AestheticCommand: String, CaseIterable {
    case longerLegs    = "🦵 腿长一点"
    case smallerFace   = "👤 脸小一点"
    case cinematic     = "🎬 电影感"
    case hongKongVibe  = "🇭🇰 港风"
    case japaneseFresh = "🌸 日系清新"
    case silhouette    = "🌅 剪影"
    case warmPortrait  = "☀️ 暖调人像"
    case coolFashion   = "❄️ 冷调时尚"

    var triggerWords: [String] {
        switch self {
        case .longerLegs:    return ["腿长", "腿", "拉长", "高", "显瘦"]
        case .smallerFace:   return ["脸小", "脸", "瘦脸", "显脸小"]
        case .cinematic:     return ["电影", "大片", "电影感", "cinematic", "质感"]
        case .hongKongVibe:  return ["港风", "港片", "王家卫"]
        case .japaneseFresh: return ["日系", "清新", "小清新", "日式"]
        case .silhouette:    return ["剪影", "逆光人像", "轮廓"]
        case .warmPortrait:  return ["暖调", "温暖", "金色"]
        case .coolFashion:   return ["冷调", "时尚", "高级感"]
        }
    }
}

// MARK: - 美学预设引擎

struct AestheticPresetEngine {

    /// 美学指令 → 拍摄策略的完整映射
    struct AestheticStrategy {
        let command: AestheticCommand

        // 镜头
        var preferredLens: LensType
        enum LensType: String { case ultraWide = "0.5x", wide = "1x", telephoto = "2x", tele3x = "3x" }

        // 机位
        var cameraHeight: CameraHeight
        enum CameraHeight { case ground, waist, chest, eye, above, high }
        var cameraAngle: CameraAngle
        enum CameraAngle { case lowUp, level, slightDown, topDown }

        // 构图
        var subjectPosition: CGPoint          // 归一化重心位置
        var bodyRatioTarget: ClosedRange<CGFloat>
        var footAnchor: FootAnchor
        enum FootAnchor { case bottom5pct, bottom10pct, midBottom, noAnchor }

        // 曝光
        var evBias: Double
        var faceBrightnessTarget: ClosedRange<Double>

        // 色彩
        var colorPreset: ColorPreset
        struct ColorPreset {
            var kelvinShift: Double     // -1000 ~ +1000
            var saturation: Double      // 0.5 ~ 2.0
            var contrast: Double        // 0.7 ~ 1.3
            var shadowLift: Double      // 0 ~ 0.3  （提升暗部）
            var highlightRolloff: Double // 0 ~ 0.2
        }

        // 景深
        var depthOfField: DepthOfField
        enum DepthOfField { case shallow, medium, deep }

        // 给摄影师的引导语
        var photographerGuide: String
        var modelGuide: String              // 给被拍者的引导
        var quickTip: String                // 一行提示
    }

    // MARK: - 8 个美学预设

    static let presets: [AestheticStrategy] = [
        // ═══════════════════════════════
        // 🦵 腿长一点
        // ═══════════════════════════════
        AestheticStrategy(
            command: .longerLegs,
            preferredLens: .ultraWide,   // 广角畸变拉长
            cameraHeight: .waist,         // 低机位
            cameraAngle: .lowUp,          // 仰拍
            subjectPosition: CGPoint(x: 0.4, y: 0.55),
            bodyRatioTarget: 0.55...0.85, // 人物占大面积
            footAnchor: .bottom5pct,      // 脚贴底边→视觉延伸
            evBias: 0.1,
            faceBrightnessTarget: 0.48...0.65,
            colorPreset: ColorPreset(
                kelvinShift: 0, saturation: 1.05, contrast: 1.0,
                shadowLift: 0.05, highlightRolloff: 0
            ),
            depthOfField: .medium,
            photographerGuide: "蹲下来，手机放到她腰部高度，稍微仰拍。让她的脚踩在画面最底部",
            modelGuide: "一只脚往前伸，脚尖轻轻点地，身体微微后仰",
            quickTip: "蹲下·仰拍·脚贴底"
        ),

        // ═══════════════════════════════
        // 👤 脸小一点
        // ═══════════════════════════════
        AestheticStrategy(
            command: .smallerFace,
            preferredLens: .telephoto,    // 长焦压缩→脸显小
            cameraHeight: .eye,           // 平视或略高
            cameraAngle: .slightDown,     // 微俯拍
            subjectPosition: CGPoint(x: 0.4, y: 0.45),
            bodyRatioTarget: 0.40...0.60,
            footAnchor: .midBottom,
            evBias: 0.0,
            faceBrightnessTarget: 0.50...0.68, // 脸稍亮显小
            colorPreset: ColorPreset(
                kelvinShift: 0, saturation: 0.95, contrast: 0.9,
                shadowLift: 0.08, highlightRolloff: 0.05
            ),
            depthOfField: .shallow,       // 背景虚化突出脸
            photographerGuide: "退后两步，切换到2x镜头，手机举到眼睛高度微微向下",
            modelGuide: "下巴微收，脸稍微侧一点，别正对镜头",
            quickTip: "退后·长焦·微俯"
        ),

        // ═══════════════════════════════
        // 🎬 电影感
        // ═══════════════════════════════
        AestheticStrategy(
            command: .cinematic,
            preferredLens: .telephoto,    // 电影常用长焦
            cameraHeight: .chest,
            cameraAngle: .level,
            subjectPosition: CGPoint(x: 0.333, y: 0.50),
            bodyRatioTarget: 0.35...0.55, // 留环境叙事
            footAnchor: .bottom10pct,
            evBias: -0.2,                 // 略微欠曝，保留高光
            faceBrightnessTarget: 0.42...0.58,
            colorPreset: ColorPreset(
                kelvinShift: -200,          // 稍偏冷
                saturation: 0.85,           // 低饱和
                contrast: 1.15,             // 中高对比
                shadowLift: 0.15,           // 提升暗部（电影感关键）
                highlightRolloff: 0.10      // 高光柔滚
            ),
            depthOfField: .shallow,       // 浅景深
            photographerGuide: "横过来拍（横构图），画面保持水平。切换到2x镜头",
            modelGuide: "不要看镜头，看画面外某个方向，自然一点",
            quickTip: "横拍·浅景深·低饱和·不看镜头"
        ),

        // ═══════════════════════════════
        // 🇭🇰 港风
        // ═══════════════════════════════
        AestheticStrategy(
            command: .hongKongVibe,
            preferredLens: .wide,
            cameraHeight: .chest,
            cameraAngle: .level,
            subjectPosition: CGPoint(x: 0.5, y: 0.50),
            bodyRatioTarget: 0.40...0.60,
            footAnchor: .bottom10pct,
            evBias: -0.3,
            faceBrightnessTarget: 0.40...0.58,
            colorPreset: ColorPreset(
                kelvinShift: 500,           // 偏暖黄
                saturation: 0.75,           // 褪色感
                contrast: 1.20,             // 高对比
                shadowLift: 0.20,           // 明显暗部提升
                highlightRolloff: 0.08
            ),
            depthOfField: .medium,
            photographerGuide: "找霓虹灯或有光影的地方，让光线从侧面打过来",
            modelGuide: "靠在墙上或栏杆上，表情自然不用笑",
            quickTip: "霓虹光·侧光·褪色·不笑"
        ),

        // ═══════════════════════════════
        // 🌸 日系清新
        // ═══════════════════════════════
        AestheticStrategy(
            command: .japaneseFresh,
            preferredLens: .wide,
            cameraHeight: .eye,
            cameraAngle: .level,
            subjectPosition: CGPoint(x: 0.4, y: 0.48),
            bodyRatioTarget: 0.35...0.55,
            footAnchor: .midBottom,
            evBias: 0.5,                  // 过曝一点
            faceBrightnessTarget: 0.55...0.75,
            colorPreset: ColorPreset(
                kelvinShift: 300,           // 微暖
                saturation: 0.90,           // 低饱和
                contrast: 0.80,             // 低对比
                shadowLift: 0.25,           // 暗部大幅提亮
                highlightRolloff: 0.15      // 高光柔和
            ),
            depthOfField: .deep,          // 大景深
            photographerGuide: "找自然光充足的地方，最好有绿植或天空做背景",
            modelGuide: "闭眼微笑，或者低头看花，自然就好",
            quickTip: "过曝·低对比·自然光·微笑"
        ),

        // ═══════════════════════════════
        // 🌅 剪影
        // ═══════════════════════════════
        AestheticStrategy(
            command: .silhouette,
            preferredLens: .wide,
            cameraHeight: .waist,
            cameraAngle: .lowUp,
            subjectPosition: CGPoint(x: 0.5, y: 0.45),
            bodyRatioTarget: 0.40...0.60,
            footAnchor: .bottom10pct,
            evBias: -2.0,                 // 极大欠曝
            faceBrightnessTarget: 0.05...0.20, // 脸暗=剪影
            colorPreset: ColorPreset(
                kelvinShift: 800,           // 极暖（日落色）
                saturation: 0.60,
                contrast: 1.3,
                shadowLift: 0.0,
                highlightRolloff: 0.0
            ),
            depthOfField: .deep,
            photographerGuide: "让她站在你和太阳之间，对焦在天空而不是人",
            modelGuide: "侧身站，做出清晰的轮廓动作（抬手/转头/跳跃）",
            quickTip: "逆光·对焦天空·侧身轮廓"
        ),

        // ═══════════════════════════════
        // ☀️ 暖调人像
        // ═══════════════════════════════
        AestheticStrategy(
            command: .warmPortrait,
            preferredLens: .telephoto,
            cameraHeight: .eye,
            cameraAngle: .level,
            subjectPosition: CGPoint(x: 0.4, y: 0.48),
            bodyRatioTarget: 0.45...0.65,
            footAnchor: .bottom10pct,
            evBias: 0.1,
            faceBrightnessTarget: 0.50...0.68,
            colorPreset: ColorPreset(
                kelvinShift: 800,           // 明显偏暖
                saturation: 1.10,
                contrast: 0.95,
                shadowLift: 0.10,
                highlightRolloff: 0.05
            ),
            depthOfField: .shallow,
            photographerGuide: "利用黄金时刻的自然光，让她面向光源",
            modelGuide: "自然微笑，眼睛要有光",
            quickTip: "暖光·虚化·眼神光"
        ),

        // ═══════════════════════════════
        // ❄️ 冷调时尚
        // ═══════════════════════════════
        AestheticStrategy(
            command: .coolFashion,
            preferredLens: .telephoto,
            cameraHeight: .chest,
            cameraAngle: .slightDown,
            subjectPosition: CGPoint(x: 0.5, y: 0.48),
            bodyRatioTarget: 0.50...0.70,
            footAnchor: .bottom10pct,
            evBias: 0.0,
            faceBrightnessTarget: 0.48...0.62,
            colorPreset: ColorPreset(
                kelvinShift: -600,          // 偏冷
                saturation: 0.80,           // 低饱和
                contrast: 1.10,
                shadowLift: 0.05,
                highlightRolloff: 0.05
            ),
            depthOfField: .shallow,
            photographerGuide: "找干净的背景（白墙/灰墙），光线均匀",
            modelGuide: "表情冷淡，不要笑，眼神有力",
            quickTip: "冷调·低饱和·冷淡表情"
        ),
    ]

    // MARK: - 查询

    static func preset(for command: AestheticCommand) -> AestheticStrategy {
        presets.first { $0.command == command } ?? presets[2] // 默认电影感
    }

    /// 从自然语言匹配（"腿拍长一点" "脸能不能显小"）
    static func match(from text: String) -> AestheticStrategy? {
        let lower = text.lowercased()
        for preset in presets {
            for word in preset.command.triggerWords {
                if lower.contains(word) {
                    return preset
                }
            }
        }
        return nil
    }
}
