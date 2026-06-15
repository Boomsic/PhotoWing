import Foundation

// MARK: - 连续姿态质量评分器

/// 不匹配 15 个预设姿势，而是从骨骼本身提取连续质量指标
struct PoseQualityAnalyzer {

    struct PoseQuality {
        var overall: Double = 0        // 0-1 综合分
        var symmetry: Double = 0.5     // 左右对称性
        var openness: Double = 0.5     // 肢体展开度
        var tension: Double = 0.5      // 舒适度（关节角度是否自然）
        var dynamism: Double = 0.3     // 动态感
        var headTilt: Double = 0       // 头部倾斜度 -1~+1
        var shoulderLevel: Double = 0  // 肩部水平度
        var hipAlignment: Double = 0   // 髋部对齐度
        var spineCurve: Double = 0     // 脊柱弯曲度
        var armAsymmetry: Double = 0   // 手臂不对称度
        var suggestions: [String] = [] // 改进建议
    }

    func evaluate(_ skeleton: BodySkeleton, previousSkeleton: BodySkeleton? = nil) -> PoseQuality {
        var quality = PoseQuality()

        // === 1. 对称性（左右镜像） ===
        quality.symmetry = computeSymmetry(skeleton)

        // === 2. 开放度（肢体展开） ===
        quality.openness = computeOpenness(skeleton)

        // === 3. 舒适度（关节角度） ===
        quality.tension = computeTension(skeleton)

        // === 4. 动态感 ===
        if let prev = previousSkeleton {
            quality.dynamism = computeDynamism(current: skeleton, previous: prev)
        }

        // === 5. 头部倾斜 ===
        quality.headTilt = computeHeadTilt(skeleton)

        // === 6. 肩部水平 ===
        quality.shoulderLevel = computeShoulderLevel(skeleton)

        // === 7. 髋部对齐 ===
        quality.hipAlignment = computeHipAlignment(skeleton)

        // === 8. 脊柱弯曲 ===
        quality.spineCurve = computeSpineCurve(skeleton)

        // === 9. 手臂不对称 ===
        quality.armAsymmetry = computeArmAsymmetry(skeleton)

        // === 综合评分（加权） ===
        quality.overall = (
            quality.symmetry * 0.20 +
            quality.openness * 0.15 +
            quality.tension * 0.25 +
            quality.dynamism * 0.10 +
            (1 - abs(quality.headTilt)) * 0.10 +
            quality.shoulderLevel * 0.10 +
            (1 - quality.armAsymmetry) * 0.10
        ).clamped(0, 1)

        // === 建议生成 ===
        quality.suggestions = generateSuggestions(quality)

        return quality
    }

    // MARK: - 各维度

    private func computeSymmetry(_ s: BodySkeleton) -> Double {
        let pairs: [(BodySkeleton.JointName, BodySkeleton.JointName)] = [
            (.leftShoulder, .rightShoulder),
            (.leftElbow, .rightElbow),
            (.leftWrist, .rightWrist),
            (.leftHip, .rightHip),
            (.leftKnee, .rightKnee),
            (.leftAnkle, .rightAnkle),
        ]

        var totalSymmetry: Double = 0
        var count = 0

        for (l, r) in pairs {
            guard let lp = s.joint(l), let rp = s.joint(r) else { continue }
            // 相对于身体中线的镜像距离
            let midline = (lp.x + rp.x) / 2
            let lDist = abs(lp.x - midline)
            let rDist = abs(rp.x - midline)
            let symmetry = 1.0 - min(1.0, abs(lDist - rDist) / max(0.01, lDist + rDist))
            totalSymmetry += symmetry
            count += 1
        }
        return count > 0 ? totalSymmetry / Double(count) : 0.5
    }

    private func computeOpenness(_ s: BodySkeleton) -> Double {
        guard let lw = s.joint(.leftWrist), let rw = s.joint(.rightWrist),
              let ls = s.joint(.leftShoulder), let rs = s.joint(.rightShoulder),
              let la = s.joint(.leftAnkle), let ra = s.joint(.rightAnkle),
              let head = s.headPosition else { return 0.5 }

        let shoulderCenter = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        let armSpread = hypot(lw.x - rw.x, lw.y - rw.y)
        let legSpread = hypot(la.x - ra.x, la.y - ra.y)
        let bodyHeight = max(0.1, (la.y + ra.y) / 2 - head.y)

        // 开放度 = 展开/身高，太高（夸张）或太低（拘谨）都不好
        let openness = (armSpread + legSpread) / (bodyHeight * 2.5)
        // 高斯型：0.4-0.8 最佳
        return gaussianScore(openness, center: 0.55, width: 0.25)
    }

    private func computeTension(_ s: BodySkeleton) -> Double {
        // 检查关节角度是否在自然范围内
        let angles: [(BodySkeleton.JointName, BodySkeleton.JointName, BodySkeleton.JointName, ClosedRange<Double>)] = [
            // 肘部（上臂-前臂）自然角度 90-160°
            (.leftShoulder, .leftElbow, .leftWrist, 90...160),
            (.rightShoulder, .rightElbow, .rightWrist, 90...160),
            // 膝盖 自然角度 160-180°
            (.leftHip, .leftKnee, .leftAnkle, 160...180),
            (.rightHip, .rightKnee, .rightAnkle, 160...180),
        ]

        var totalComfort: Double = 0
        var count = 0

        for (a, b, c, range) in angles {
            guard let pa = s.joint(a), let pb = s.joint(b), let pc = s.joint(c) else { continue }
            let angle = jointAngle(pa, pb, pc)
            let comfort: Double
            if range.contains(angle) {
                comfort = 1.0
            } else {
                let dist = min(abs(angle - range.lowerBound), abs(angle - range.upperBound))
                comfort = max(0, 1.0 - dist / 60.0)
            }
            totalComfort += comfort
            count += 1
        }
        return count > 0 ? totalComfort / Double(count) : 0.5
    }

    private func computeDynamism(current: BodySkeleton, previous: BodySkeleton) -> Double {
        let keyJoints: [BodySkeleton.JointName] = [.leftWrist, .rightWrist, .leftAnkle, .rightAnkle, .nose]
        var totalMotion: Double = 0
        var count = 0
        for joint in keyJoints {
            guard let cp = current.joint(joint), let pp = previous.joint(joint) else { continue }
            totalMotion += hypot(cp.x - pp.x, cp.y - pp.y)
            count += 1
        }
        let avgMotion = count > 0 ? totalMotion / Double(count) : 0
        return min(1.0, avgMotion * 8)
    }

    private func computeHeadTilt(_ s: BodySkeleton) -> Double {
        guard let le = s.joint(.leftEye), let re = s.joint(.rightEye) else { return 0 }
        // 眼线斜率 → 头部倾斜角
        let dx = re.x - le.x
        let dy = re.y - le.y
        return (atan2(dy, dx) / .pi).clamped(-1, 1)
    }

    private func computeShoulderLevel(_ s: BodySkeleton) -> Double {
        guard let ls = s.joint(.leftShoulder), let rs = s.joint(.rightShoulder) else { return 0.5 }
        let dy = abs(ls.y - rs.y)
        let shoulderWidth = abs(ls.x - rs.x)
        return 1.0 - min(1.0, dy / max(0.01, shoulderWidth * 3))
    }

    private func computeHipAlignment(_ s: BodySkeleton) -> Double {
        guard let lh = s.joint(.leftHip), let rh = s.joint(.rightHip) else { return 0.5 }
        let dy = abs(lh.y - rh.y)
        let hipWidth = abs(lh.x - rh.x)
        return 1.0 - min(1.0, dy / max(0.01, hipWidth * 3))
    }

    private func computeSpineCurve(_ s: BodySkeleton) -> Double {
        guard let head = s.headPosition,
              let ls = s.joint(.leftShoulder), let rs = s.joint(.rightShoulder),
              let lh = s.joint(.leftHip), let rh = s.joint(.rightHip) else { return 0 }
        let shoulderMid = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        let hipMid = CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
        // 头-肩-髋不共线
        let spineLen = hypot(hipMid.x - shoulderMid.x, hipMid.y - shoulderMid.y)
        let headOffset = abs(head.x - shoulderMid.x)
        return min(1.0, headOffset / max(0.01, spineLen * 2))
    }

    private func computeArmAsymmetry(_ s: BodySkeleton) -> Double {
        guard let lw = s.joint(.leftWrist), let rw = s.joint(.rightWrist),
              let ls = s.joint(.leftShoulder), let rs = s.joint(.rightShoulder) else { return 0.5 }
        let leftArmLen = hypot(lw.x - ls.x, lw.y - ls.y)
        let rightArmLen = hypot(rw.x - rs.x, rw.y - rs.y)
        return min(1.0, abs(leftArmLen - rightArmLen) / max(0.01, leftArmLen + rightArmLen) * 3)
    }

    // MARK: - 工具

    private func jointAngle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        let v1 = (x: a.x - b.x, y: a.y - b.y)
        let v2 = (x: c.x - b.x, y: c.y - b.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let mag1 = hypot(v1.x, v1.y)
        let mag2 = hypot(v2.x, v2.y)
        let cosAngle = (dot / max(0.001, mag1 * mag2)).clamped(-1, 1)
        return acos(cosAngle) * 180 / .pi
    }

    private func gaussianScore(_ x: Double, center: Double, width: Double) -> Double {
        exp(-pow(x - center, 2) / (2 * width * width))
    }

    private func generateSuggestions(_ q: PoseQuality) -> [String] {
        var tips: [String] = []
        if q.symmetry < 0.4 { tips.append("身体稍微转正一点") }
        if q.openness < 0.3 { tips.append("手臂可以展开一些，不要太拘谨") }
        if q.openness > 0.85 { tips.append("放松一点，不用摆太开的姿势") }
        if q.tension < 0.4 { tips.append("手臂放松，自然下垂") }
        if abs(q.headTilt) > 0.3 { tips.append(q.headTilt > 0 ? "头稍微正一点" : "头稍微正一点") }
        if q.shoulderLevel < 0.6 { tips.append("肩膀放平") }
        if q.armAsymmetry > 0.4 { tips.append("两只手臂动作对称一些") }
        if tips.isEmpty && q.overall > 0.7 { tips.append("✨ 姿态很好！") }
        return tips
    }
}
