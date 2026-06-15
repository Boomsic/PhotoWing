import Foundation

// MARK: - 10 维美学语义空间

/// 不是 8 个预设，而是 10 个连续维度
/// 任何自然语言请求 → 10 维向量 → 参数融合
struct AestheticIntent {
    // === 10 个核心维度（每个 -1.0 ~ +1.0） ===

    var bodyProportion: Double = 0     // -1=娇小紧凑  +1=修长高挑
    var faceRendering: Double = 0      // -1=圆润饱满  +1=立体显瘦
    var colorWarmth: Double = 0        // -1=冷调/蓝青  +1=暖调/金黄
    var lightDrama: Double = 0         //  0=平光柔和  1=戏剧光影
    var depthPreference: Double = 0    // -1=大景深全清  +1=浅景深虚化
    var compositionDynamism: Double = 0 // 0=居中对称  1=动态偏构
    var textureQuality: Double = 0     // -1=干净数码  +1=胶片颗粒
    var dynamismLevel: Double = 0      //  0=静态摆拍  1=动态抓拍
    var eraStyle: Double = 0           // -1=现代/当代  +1=复古/年代
    var emotionalTone: Double = 0      // -1=冷峻/严肃  +1=柔美/梦幻

    // === 特殊覆盖（非连续维度，无条件覆盖） ===
    var saturationOverride: Double?    // nil=不覆盖, 0=黑白, 0.5=低饱和, 1.5=高饱和
    var isMonochrome: Bool = false
    var isSilhouette: Bool = false
    var preferredLens: String?         // "0.5x" "1x" "2x" "3x"
    var cameraHeightHint: String?      // "蹲下" "腰部" "平视" "举高"
    var bodyPartFocus: BodyPartFocus?  // 特写部位

    enum BodyPartFocus: String {
        case fullBody = "全身"
        case halfBody = "半身"
        case bustPortrait = "胸像"
        case faceCloseup = "面部特写"
        case hands = "手部"
        case legs = "腿部"
        case back = "背影"
    }

    // === 原始输入 ===
    var rawText: String = ""
    var matchedTokens: [String] = []   // 匹配到的语义 token
    var confidence: Double = 0

    /// 是否有效（至少有一个维度非零）
    var isValid: Bool {
        abs(bodyProportion) > 0.01 || abs(faceRendering) > 0.01 ||
        abs(colorWarmth) > 0.01 || lightDrama > 0.01 ||
        abs(depthPreference) > 0.01 || compositionDynamism > 0.01 ||
        abs(textureQuality) > 0.01 || dynamismLevel > 0.01 ||
        abs(eraStyle) > 0.01 || abs(emotionalTone) > 0.01 ||
        saturationOverride != nil || isMonochrome || isSilhouette ||
        preferredLens != nil || bodyPartFocus != nil
    }

    /// 两个意图融合（简单相加后 clamp）
    static func +(lhs: AestheticIntent, rhs: AestheticIntent) -> AestheticIntent {
        AestheticIntent(
            bodyProportion: (lhs.bodyProportion + rhs.bodyProportion).clamped(-1, 1),
            faceRendering: (lhs.faceRendering + rhs.faceRendering).clamped(-1, 1),
            colorWarmth: (lhs.colorWarmth + rhs.colorWarmth).clamped(-1, 1),
            lightDrama: (lhs.lightDrama + rhs.lightDrama).clamped(0, 1),
            depthPreference: (lhs.depthPreference + rhs.depthPreference).clamped(-1, 1),
            compositionDynamism: (lhs.compositionDynamism + rhs.compositionDynamism).clamped(0, 1),
            textureQuality: (lhs.textureQuality + rhs.textureQuality).clamped(-1, 1),
            dynamismLevel: (lhs.dynamismLevel + rhs.dynamismLevel).clamped(0, 1),
            eraStyle: (lhs.eraStyle + rhs.eraStyle).clamped(-1, 1),
            emotionalTone: (lhs.emotionalTone + rhs.emotionalTone).clamped(-1, 1),
            saturationOverride: rhs.saturationOverride ?? lhs.saturationOverride,
            isMonochrome: lhs.isMonochrome || rhs.isMonochrome,
            isSilhouette: lhs.isSilhouette || rhs.isSilhouette,
            preferredLens: rhs.preferredLens ?? lhs.preferredLens,
            cameraHeightHint: rhs.cameraHeightHint ?? lhs.cameraHeightHint,
            bodyPartFocus: rhs.bodyPartFocus ?? lhs.bodyPartFocus,
            rawText: [lhs.rawText, rhs.rawText].filter { !$0.isEmpty }.joined(separator: " + "),
            matchedTokens: lhs.matchedTokens + rhs.matchedTokens,
            confidence: max(lhs.confidence, rhs.confidence)
        )
    }
}
