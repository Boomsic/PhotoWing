import Foundation

/// 曝光指导引擎：人脸区域测光 vs 背景测光
struct ExposureEngine {

    /// 理想人脸亮度范围（场景自适应）
    var idealFaceBrightness: ClosedRange<Double> = 0.45...0.70
    /// 人脸 vs 背景反差容忍度
    static let maxContrastRatio: Double = 3.5

    // MARK: - 评估

    func evaluate(faceBrightness: Double,
                  backgroundBrightness: Double,
                  skeleton: BodySkeleton?) -> ExposureGuidance {
        var guidance = ExposureGuidance()
        guidance.faceBrightness = faceBrightness
        guidance.backgroundBrightness = backgroundBrightness

        // 无人物时不做精细评估
        guard skeleton != nil else {
            guidance.score = 50
            guidance.hint = "对准人物后可评估曝光"
            return guidance
        }

        var score: Double = 100

        // 1. 人脸亮度偏离
        let faceDeviation: Double
        if faceBrightness < idealFaceBrightness.lowerBound {
            faceDeviation = idealFaceBrightness.lowerBound - faceBrightness
            score -= faceDeviation * 200

            if faceBrightness < 0.25 {
                guidance.hint = "🌑 脸太暗了！往亮处站或打开闪光灯"
            } else if faceBrightness < 0.40 {
                guidance.hint = "🌥️ 脸有点暗，往亮处转一转"
                guidance.recommendedEV = min(1.0, faceDeviation * 2)
            } else {
                guidance.hint = "微调曝光即可"
                guidance.recommendedEV = faceDeviation
            }

        } else if faceBrightness > idealFaceBrightness.upperBound {
            faceDeviation = faceBrightness - idealFaceBrightness.upperBound
            score -= faceDeviation * 180

            if faceBrightness > 0.90 {
                guidance.hint = "☀️ 脸过曝了！降低曝光或换个方向"
                guidance.recommendedEV = -1.0
            } else {
                guidance.hint = "☀️ 脸有点亮，降低一点曝光"
                guidance.recommendedEV = -faceDeviation
            }

        } else {
            faceDeviation = 0
        }

        // 2. 逆光检测（人脸暗 + 背景亮）
        if faceBrightness < 0.35 && backgroundBrightness > 0.7 {
            score -= 30
            guidance.hint = "🔆 逆光了！换个方向或打开闪光灯"
            guidance.recommendedEV = 0.5
        }

        // 3. 背景过亮（人物变剪影）
        if backgroundBrightness > 0.85 && faceBrightness < 0.5 {
            score -= 25
            guidance.hint = "背景太亮，人物会变剪影哦"
        }

        guidance.score = Int(max(0, min(100, score)))

        if guidance.hint.isEmpty {
            guidance.hint = "✅ 曝光合适"
        }

        return guidance
    }
}
