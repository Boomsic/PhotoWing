import Foundation

/// 统一的指导结果，由 GuidanceOrchestrator 汇总输出
struct GuidanceResult {
    /// 总评 0-100
    var overallScore: Int {
        let scores = [composition.score, exposure.score, pose.score, focus.score]
        let valid = scores.filter { $0 > 0 }
        return valid.isEmpty ? 0 : Int(Double(valid.reduce(0, +)) / Double(valid.count))
    }

    var composition: CompositionGuidance
    var exposure: ExposureGuidance
    var pose: PoseGuidance
    var focus: FocusGuidance
    var background: BackgroundGuidance

    /// 按优先级排序的提示列表（最重要的排前面）
    var prioritizedHints: [String] {
        var hints: [(priority: Int, text: String)] = []

        if composition.score < 60 { hints.append((1, composition.hint)) }
        if exposure.score < 50    { hints.append((2, exposure.hint)) }
        if focus.score < 50       { hints.append((3, focus.hint)) }
        if pose.score < 50        { hints.append((4, pose.hint)) }
        if !background.hint.isEmpty && background.score < 50 { hints.append((5, background.hint)) }

        // 如果都还行，给正向反馈
        if hints.isEmpty && overallScore >= 70 {
            hints.append((0, "✨ 完美！按快门吧"))
        }

        return hints.sorted { $0.priority < $1.priority }.map(\.text)
    }

    /// 是否所有维度都达标
    var isReadyToShoot: Bool {
        composition.score >= 65 &&
        exposure.score >= 55 &&
        focus.score >= 55
    }
}

// MARK: - 各维度指导

struct CompositionGuidance {
    /// 构图得分 0-100
    var score: Int = 0
    /// 文字提示
    var hint: String = "正在分析构图..."
    /// 人物重心应在的归一化目标位置
    var targetPosition: CGPoint = CGPoint(x: 0.333, y: 0.55)
    /// 当前人物重心位置
    var currentPosition: CGPoint?
    /// 方向提示箭头（用于 UI 箭头动画）
    var directionArrow: DirectionArrow?
    /// 是否启用姿势叠加
    var showPoseGhost: Bool = false

    enum DirectionArrow: String {
        case left = "⬅️"
        case right = "➡️"
        case up = "⬆️"
        case down = "⬇️"
        case upLeft = "↖️"
        case upRight = "↗️"
        case none = ""
    }
}

struct ExposureGuidance {
    var score: Int = 0
    var hint: String = ""
    /// 人脸区域平均亮度 0-1
    var faceBrightness: Double = 0.5
    /// 背景平均亮度 0-1
    var backgroundBrightness: Double = 0.5
    /// 推荐曝光补偿 (-1 到 +1)
    var recommendedEV: Double = 0.0
}

struct PoseGuidance {
    var score: Int = 0
    var hint: String = ""
    /// 当前激活的参考姿势
    var activePose: ReferencePose?
    /// 各关节匹配度
    var jointScores: [BodySkeleton.JointName: Double] = [:]
}

struct FocusGuidance {
    var score: Int = 0
    var hint: String = ""
    /// 是否已锁焦到人脸
    var isFaceLocked: Bool = false
}

struct BackgroundGuidance {
    var score: Int = 70
    var hint: String = ""
    /// 是否有穿头物体
    var hasHeadIntersection: Bool = false
    /// 背景杂乱度 0-1
    var clutterLevel: Double = 0.3
}
