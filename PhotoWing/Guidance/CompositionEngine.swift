import Foundation

/// 构图指导引擎：三分法 + 人物位置评估
struct CompositionEngine {

    // MARK: - 三分法网格配置

    /// 理想重心 X 位置（左或右 1/3 线）
    static let idealXPositions: [CGFloat] = [0.333, 0.666]
    /// 理想重心 Y 范围（画面中部偏上）
    static let idealYRange: ClosedRange<CGFloat> = 0.45...0.60
    /// 头部应该在上 1/3 线附近
    static let headIdealY: CGFloat = 0.30
    /// 人物占画面比例（场景自适应）
    var idealBodyRatio: ClosedRange<CGFloat> = 0.45...0.75
    /// 头顶留白比例（场景自适应）
    var headroomRatio: ClosedRange<CGFloat> = 0.05...0.12

    // MARK: - 评估

    /// 返回构图指导和评分
    func evaluate(skeleton: BodySkeleton, viewSize: CGSize) -> CompositionGuidance {
        var guidance = CompositionGuidance()
        var score: Double = 100

        guard let head = skeleton.headPosition,
              let centerMass = skeleton.centerOfMass,
              let boundingBox = skeleton.boundingBox else {
            guidance.score = 0
            guidance.hint = "👤 未检测到人物，请对准人物"
            return guidance
        }

        // 1. 重心水平位置（左或右 1/3 线为美）
        let nearestIdealX = Self.idealXPositions.min(by: {
            abs($0 - centerMass.x) < abs($1 - centerMass.x)
        })!
        guidance.currentPosition = centerMass
        guidance.targetPosition = CGPoint(x: nearestIdealX, y: 0.52)

        let xError = abs(centerMass.x - nearestIdealX)
        if xError > 0.15 {
            score -= xError * 80
            guidance.directionArrow = centerMass.x < nearestIdealX ? .right : .left
        } else if xError > 0.08 {
            score -= xError * 40
            guidance.directionArrow = centerMass.x < nearestIdealX ? .right : .left
        } else {
            guidance.directionArrow = .none
        }

        // 2. 重心垂直位置
        if centerMass.y < Self.idealYRange.lowerBound {
            score -= 20
            guidance.directionArrow = guidance.directionArrow == .none ? .down : guidance.directionArrow
        } else if centerMass.y > Self.idealYRange.upperBound {
            score -= 20
            guidance.directionArrow = guidance.directionArrow == .none ? .up : guidance.directionArrow
        }

        // 3. 头部空间检测（切头 / 留白过多）
        let headroom = head.y / boundingBox.height
        if headroom < headroomRatio.lowerBound {
            score -= 25
            guidance.directionArrow = .up
        } else if headroom > headroomRatio.upperBound {
            score -= 15
            guidance.directionArrow = .down
        }

        // 4. 人物占比
        let bodyRatio = boundingBox.height
        if bodyRatio < idealBodyRatio.lowerBound {
            score -= (idealBodyRatio.lowerBound - bodyRatio) * 200
            guidance.directionArrow = .up  // 靠近点
        } else if bodyRatio > idealBodyRatio.upperBound {
            score -= (bodyRatio - idealBodyRatio.upperBound) * 150
            guidance.directionArrow = .down  // 退后点
        }

        // 5. 生成提示文字
        guidance.score = Int(max(0, min(100, score)))
        guidance.hint = generateHint(guidance: guidance, bodyRatio: bodyRatio, headroom: headroom)

        return guidance
    }

    private func generateHint(guidance: CompositionGuidance,
                               bodyRatio: CGFloat,
                               headroom: CGFloat) -> String {
        if guidance.score >= 85 { return "✅ 构图完美" }
        if guidance.score >= 70 { return "👍 构图不错，微调一下更好" }

        switch guidance.directionArrow {
        case .left:   return "⬅️ 往左站一点，人物偏右了"
        case .right:  return "➡️ 往右站一点，人物偏左了"
        case .up:     return headroom < headroomRatio.lowerBound
            ? "⬆️ 往上挪一点，头顶要被切了"
            : "⬆️ 靠近一点，人物太小了"
        case .down:   return headroom > headroomRatio.upperBound
            ? "⬇️ 往下压一点，头顶留白太多"
            : "⬇️ 退后一点，人物太大了"
        case .upLeft:  return "↖️ 往左上方站"
        case .upRight: return "↗️ 往右上方站"
        case .none:    return "调整拍摄位置"
        }
    }
}
