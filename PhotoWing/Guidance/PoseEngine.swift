import Foundation

/// 姿势匹配引擎：当前骨骼 vs 参考姿势
struct PoseEngine {

    /// 匹配达标阈值
    static let matchThreshold: Double = 0.75

    /// 对当前骨骼和参考姿势做匹配评分
    func evaluate(skeleton: BodySkeleton,
                  reference: ReferencePose) -> PoseGuidance {
        var guidance = PoseGuidance()
        guidance.activePose = reference

        guard skeleton.confidence > 0.3 else {
            guidance.score = 0
            guidance.hint = "未检测到清晰的人体姿态"
            return guidance
        }

        // 将当前骨骼归一化到参考姿势的坐标系
        // 以髋部中点为原点，肩宽为单位
        guard let leftHip = skeleton.leftHipPos,
              let rightHip = skeleton.rightHipPos,
              let leftShoulder = skeleton.leftShoulderPos,
              let rightShoulder = skeleton.rightShoulderPos else {
            guidance.score = 0
            guidance.hint = "请确保全身在画面中"
            return guidance
        }

        let hipCenter = CGPoint(x: (leftHip.x + rightHip.x) / 2,
                                y: (leftHip.y + rightHip.y) / 2)
        let shoulderWidth = hypot(leftShoulder.x - rightShoulder.x,
                                   leftShoulder.y - rightShoulder.y)

        // 计算身高（鼻尖到脚踝中点）
        let ankleMidY: CGFloat
        if let la = skeleton.joint(.leftAnkle), let ra = skeleton.joint(.rightAnkle) {
            ankleMidY = (la.y + ra.y) / 2
        } else {
            ankleMidY = hipCenter.y + shoulderWidth * 0.8  // 估算
        }
        let bodyHeight = max(0.1, ankleMidY - (skeleton.headPosition?.y ?? hipCenter.y - shoulderWidth * 0.8))

        var totalScore: Double = 0
        var matchedJoints = 0

        // 对参考姿势中的每个关键点做比较
        for ref in reference.keypoints {
            guard let currentPos = skeleton.joint(ref.joint) else { continue }

            // 将当前关节归一化到参考坐标系
            let normalizedX = (currentPos.x - hipCenter.x) / max(0.01, shoulderWidth)
            let normalizedY = (currentPos.y - hipCenter.y) / max(0.01, bodyHeight)

            let dx = normalizedX - ref.relativeX
            let dy = normalizedY - ref.relativeY
            let distance = hypot(dx, dy)

            // 距离越小越匹配，阈值 0.25 为满分
            let jointScore = max(0, 1.0 - distance / 0.30)
            totalScore += jointScore
            matchedJoints += 1

            guidance.jointScores[ref.joint] = jointScore

            // 偏差较大的关节做提示
            if distance > 0.20 {
                // 在 orchestrator 中汇总提示
            }
        }

        guidance.score = matchedJoints > 0
            ? Int((totalScore / Double(matchedJoints)) * 100)
            : 0

        // 生成提示
        guidance.hint = generateHint(score: guidance.score,
                                      matchedJoints: matchedJoints,
                                      totalJoints: reference.keypoints.count)

        return guidance
    }

    private func generateHint(score: Int, matchedJoints: Int, totalJoints: Int) -> String {
        if score >= 85 { return "✨ 姿势完美！保持住" }
        if score >= 70 { return "👍 姿势不错，微调手臂角度" }
        if score >= 50 { return "🤔 差一点点，跟着参考线调整" }
        if matchedJoints < totalJoints / 2 { return "👤 请退后确保全身入镜" }
        return "跟着半透明参考姿势调整吧"
    }
}
