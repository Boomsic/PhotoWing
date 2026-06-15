import Foundation

// MARK: - 自然语言意图解析器

/// 核心创新：不做关键词→预设 的一对一映射
/// 而是做 任意话 → 10维语义向量 → 参数融合
///
/// "腿长一点电影感逆光侧脸不看镜头" →
///   bodyProportion+0.8, textureQuality+0.6, lightDrama+0.8,
///   compositionDynamism+0.5, dynamismLevel+0.5
struct AestheticIntentParser {

    private let fuzzyMatcher = FuzzyIntentMatcher()

    // MARK: - 语义词典（200+ 词条）

    /// 每个词条 = (匹配词, 维度, 强度)
    typealias LexiconEntry = (tokens: [String], dimension: KeyPath<AestheticIntent, Double>, value: Double)

    /// 强度修饰符
    private static let intensityModifiers: [(String, Double)] = [
        ("非常", 1.5), ("特别", 1.5), ("很", 1.3), ("好", 1.2),
        ("超级", 1.8), ("极其", 1.8), ("太", 1.5), ("巨", 1.5),
        ("贼", 1.4), ("老", 1.3), ("挺", 1.1),
        ("稍微", 0.5), ("一点", 0.6), ("一点点", 0.4), ("略微", 0.4),
        ("有点", 0.6), ("不那么", -0.5), ("别太", -0.7), ("不要太", -0.7),
    ]

    /// 否定词（翻转后续维度符号）
    private static let negators: [String] = ["不", "别", "不要", "别太", "没那么"]

    // MARK: - 主解析入口

    /// 输入任意中文 → 输出 10 维语义向量（使用模糊匹配器）
    func parse(_ text: String) -> AestheticIntent {
        var intent = AestheticIntent(rawText: text)
        let lower = text.lowercased()

        // === 1. 特殊覆盖检测（无条件模式，仍然用精确匹配） ===

        // 黑白
        if lower.contains("黑白") || lower.contains("单色") {
            intent.isMonochrome = true
            intent.saturationOverride = 0
            intent.matchedTokens.append("黑白·单色")
        }

        // 剪影
        if lower.contains("剪影") || lower.contains("轮廓光") {
            intent.isSilhouette = true
            intent.lightDrama = 1.0
            intent.matchedTokens.append("剪影")
        }

        // 逆光
        if lower.contains("逆光") || lower.contains("背光") {
            intent.lightDrama = max(intent.lightDrama, 0.9)
            intent.matchedTokens.append("逆光")
        }

        // === 2. 部位特写（精确匹配，高频词不易错） ===
        if lower.contains("全身") { intent.bodyPartFocus = .fullBody; intent.matchedTokens.append("全身") }
        else if lower.contains("半身") { intent.bodyPartFocus = .halfBody; intent.matchedTokens.append("半身") }
        else if lower.contains("胸像") || lower.contains("上半身") { intent.bodyPartFocus = .bustPortrait; intent.matchedTokens.append("胸像") }
        else if lower.contains("特写") || lower.contains("大头") { intent.bodyPartFocus = .faceCloseup; intent.matchedTokens.append("特写") }
        else if lower.contains("背影") || lower.contains("背后") { intent.bodyPartFocus = .back; intent.matchedTokens.append("背影") }

        // === 3. 镜头选择 ===
        if lower.contains("广角") || lower.contains("0.5") || lower.contains("超广") { intent.preferredLens = "0.5x" }
        else if lower.contains("长焦") || lower.contains("3倍") || lower.contains("3x") { intent.preferredLens = "3x" }
        else if lower.contains("2倍") || lower.contains("2x") { intent.preferredLens = "2x" }

        // === 4. 模糊匹配：10 维语义（核心） ===
        let matches = fuzzyMatcher.matchAll(in: text)

        for match in matches {
            let oldValue = intent[keyPath: match.dimension]
            intent[keyPath: match.dimension] = (oldValue + match.value).clamped(-1, 1)
            intent.matchedTokens.append(match.canonicalToken)
        }

        // === 5. 饱和度特殊处理 ===
        if lower.contains("低饱和") || lower.contains("褪色") || lower.contains("莫兰迪") || lower.contains("高级灰") {
            intent.saturationOverride = 0.4
        }
        if lower.contains("高饱和") || lower.contains("鲜艳") || lower.contains("浓郁") {
            intent.saturationOverride = 1.4
        }

        // === 6. 计算置信度 ===
        intent.confidence = min(1.0, Double(intent.matchedTokens.count) / 5.0)

        return intent
    }

    // MARK: - 多短语拆分

    /// "腿长一点，然后要有电影感，最好逆光"
    /// → ["腿长一点", "要有电影感", "最好逆光"]
    func splitPhrases(_ text: String) -> [String] {
        let separators = ["，", ",", "。", ".", "然后", "还有", "并且", "而且", "最好", "另外", "加上", "以及", "同时"]

        var parts = [text]
        for sep in separators {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 1 }
    }

    /// 解析整个句子 → 融合多个子意图
    func parseFull(_ text: String) -> AestheticIntent {
        let phrases = splitPhrases(text)
        if phrases.isEmpty {
            return parse(text)
        }

        // 每个短语独立解析 → 向量相加
        let intents = phrases.map { parse($0) }
        return intents.reduce(AestheticIntent()) { $0 + $1 }
    }
}
