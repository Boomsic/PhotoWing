import Foundation

// MARK: - 自适应参数引擎（连续插值，非离散分类）

/// 从 18 维连续特征向量 → 所有拍摄参数的平滑映射
/// 使用逆距离加权插值（IDW），真正的连续空间，不是查表
struct AdaptiveParameterEngine {

    // MARK: - 输出参数集

    struct PhotoParameters {
        // 曝光
        var faceBrightnessTarget: ClosedRange<Double> = 0.48...0.65
        var evAdjustSpeed: Double = 0.05
        var maxEV: Double = 0.7
        var minEV: Double = -0.5

        // 对焦
        var focusSensitivity: Double = 0.05

        // 构图
        var idealBodyRatio: ClosedRange<CGFloat> = 0.45...0.72
        var headroomRatio: ClosedRange<CGFloat> = 0.05...0.12
        var targetXPosition: CGFloat = 0.333

        // 白平衡
        var wbShift: Double = 0          // -1(冷) ~ +1(暖)
        var saturationBoost: Double = 0  // -1 ~ +1

        // 降噪/锐化
        var sharpnessEnhance: Double = 0
        var noiseReduction: Double = 0

        // 场景提示
        var sceneHint: String = ""
    }

    // MARK: - 参考点（IDW 插值锚点）

    /// 每个参考点 = (特征向量, 已知最优参数)
    /// 新特征向量通过加权平均附近参考点得到参数
    private let referencePoints: [(SceneFeatureVector, PhotoParameters)] = [
        // ── 基准点（覆盖特征空间的关键位置） ──

        // 0: 中性日光（最常用锚点）
        (SceneFeatureVector(
            avgBrightness: 0.55, dynamicRange: 0.45, backlightRatio: 1.2,
            highlightRatio: 0.25, shadowRatio: 0.15,
            colorTemperature: 5500, saturation: 0.5, skinTonePresence: 0.15,
            greenDominance: 1.0, blueDominance: 1.0,
            faceSize: 0.08, bodyRatio: 0.55, poseOpenness: 0.5,
            motionLevel: 0.1, numPeople: 1,
            subjectDistance: 2.5, backgroundDistance: 8, depthSeparation: 2,
            sharpness: 0.75, noiseLevel: 0.15, flickerDetected: 0
        ), PhotoParameters(
            faceBrightnessTarget: 0.50...0.70,
            evAdjustSpeed: 0.04, maxEV: 0.5, minEV: -0.5,
            focusSensitivity: 0.06,
            idealBodyRatio: 0.45...0.70,
            headroomRatio: 0.06...0.14,
            targetXPosition: 0.333,
            wbShift: 0, saturationBoost: 0,
            sharpnessEnhance: 0, noiseReduction: 0,
            sceneHint: "自然光充足"
        )),

        // 1: 强烈逆光
        (SceneFeatureVector(
            avgBrightness: 0.65, dynamicRange: 0.70, backlightRatio: 0.25,
            highlightRatio: 0.40, shadowRatio: 0.20,
            colorTemperature: 5200, saturation: 0.4, skinTonePresence: 0.05,
            greenDominance: 0.9, blueDominance: 1.1,
            faceSize: 0.05, bodyRatio: 0.50, poseOpenness: 0.4,
            motionLevel: 0.2, numPeople: 1,
            subjectDistance: 3.0, backgroundDistance: 15, depthSeparation: 5,
            sharpness: 0.65, noiseLevel: 0.20, flickerDetected: 0
        ), PhotoParameters(
            faceBrightnessTarget: 0.30...0.50,
            evAdjustSpeed: 0.10, maxEV: 1.0, minEV: 0.0,
            focusSensitivity: 0.03,
            idealBodyRatio: 0.50...0.78,
            headroomRatio: 0.04...0.10,
            targetXPosition: 0.4,  // 留出光源方向
            wbShift: 0.3, saturationBoost: -0.1,
            sharpnessEnhance: 0.2, noiseReduction: 0.1,
            sceneHint: "逆光·打开闪光灯或换个方向"
        )),

        // 2: 极暗夜景
        (SceneFeatureVector(
            avgBrightness: 0.12, dynamicRange: 0.15, backlightRatio: 1.5,
            highlightRatio: 0.02, shadowRatio: 0.60,
            colorTemperature: 3800, saturation: 0.2, skinTonePresence: 0.02,
            greenDominance: 0.7, blueDominance: 0.8,
            faceSize: 0.03, bodyRatio: 0.40, poseOpenness: 0.3,
            motionLevel: 0.5, numPeople: 1,
            subjectDistance: 1.5, backgroundDistance: 3, depthSeparation: 1,
            sharpness: 0.30, noiseLevel: 0.70, flickerDetected: 0.4
        ), PhotoParameters(
            faceBrightnessTarget: 0.25...0.45,
            evAdjustSpeed: 0.12, maxEV: 1.0, minEV: 0.2,
            focusSensitivity: 0.02,  // 极频繁对焦
            idealBodyRatio: 0.55...0.85,  // 靠近拍
            headroomRatio: 0.04...0.10,
            targetXPosition: 0.5,  // 居中
            wbShift: 0.5, saturationBoost: 0.1,
            sharpnessEnhance: 0.5, noiseReduction: 0.8,
            sceneHint: "暗光·保持稳定，用闪光灯"
        )),

        // 3: 沙滩/雪地高亮
        (SceneFeatureVector(
            avgBrightness: 0.82, dynamicRange: 0.65, backlightRatio: 0.9,
            highlightRatio: 0.50, shadowRatio: 0.05,
            colorTemperature: 6500, saturation: 0.3, skinTonePresence: 0.08,
            greenDominance: 0.8, blueDominance: 1.4,
            faceSize: 0.04, bodyRatio: 0.45, poseOpenness: 0.5,
            motionLevel: 0.2, numPeople: 1,
            subjectDistance: 3.0, backgroundDistance: 20, depthSeparation: 8,
            sharpness: 0.80, noiseLevel: 0.05, flickerDetected: 0
        ), PhotoParameters(
            faceBrightnessTarget: 0.55...0.78,  // 提高目标防欠曝
            evAdjustSpeed: 0.04, maxEV: 0.2, minEV: -0.8,
            focusSensitivity: 0.07,
            idealBodyRatio: 0.38...0.62,  // 多留环境
            headroomRatio: 0.06...0.14,
            targetXPosition: 0.333,
            wbShift: -0.4, saturationBoost: 0.2,
            sharpnessEnhance: 0, noiseReduction: 0,
            sceneHint: "高亮环境·适当降低曝光"
        )),

        // 4: 黄金时刻暖光
        (SceneFeatureVector(
            avgBrightness: 0.45, dynamicRange: 0.40, backlightRatio: 1.5,
            highlightRatio: 0.20, shadowRatio: 0.20,
            colorTemperature: 3500, saturation: 0.65, skinTonePresence: 0.18,
            greenDominance: 0.85, blueDominance: 0.6,
            faceSize: 0.07, bodyRatio: 0.55, poseOpenness: 0.6,
            motionLevel: 0.1, numPeople: 1,
            subjectDistance: 2.0, backgroundDistance: 6, depthSeparation: 3,
            sharpness: 0.70, noiseLevel: 0.10, flickerDetected: 0
        ), PhotoParameters(
            faceBrightnessTarget: 0.48...0.68,
            evAdjustSpeed: 0.03, maxEV: 0.4, minEV: -0.3,
            focusSensitivity: 0.05,
            idealBodyRatio: 0.45...0.70,
            headroomRatio: 0.06...0.14,
            targetXPosition: 0.333,  // 面向光源
            wbShift: 0.2, saturationBoost: 0.3,
            sharpnessEnhance: 0, noiseReduction: 0,
            sceneHint: "黄金光线·让她面向光源"
        )),

        // 5: 室内暖光
        (SceneFeatureVector(
            avgBrightness: 0.30, dynamicRange: 0.25, backlightRatio: 1.1,
            highlightRatio: 0.10, shadowRatio: 0.30,
            colorTemperature: 3200, saturation: 0.40, skinTonePresence: 0.12,
            greenDominance: 0.75, blueDominance: 0.5,
            faceSize: 0.06, bodyRatio: 0.50, poseOpenness: 0.4,
            motionLevel: 0.15, numPeople: 1,
            subjectDistance: 1.8, backgroundDistance: 4, depthSeparation: 1.5,
            sharpness: 0.55, noiseLevel: 0.35, flickerDetected: 0.6
        ), PhotoParameters(
            faceBrightnessTarget: 0.42...0.60,
            evAdjustSpeed: 0.06, maxEV: 0.7, minEV: -0.2,
            focusSensitivity: 0.04,
            idealBodyRatio: 0.45...0.68,
            headroomRatio: 0.06...0.14,
            targetXPosition: 0.4,
            wbShift: 0.4, saturationBoost: 0,
            sharpnessEnhance: 0.15, noiseReduction: 0.3,
            sceneHint: "室内暖光·注意背景整洁"
        )),

        // 6: 绿植户外
        (SceneFeatureVector(
            avgBrightness: 0.40, dynamicRange: 0.50, backlightRatio: 1.0,
            highlightRatio: 0.15, shadowRatio: 0.25,
            colorTemperature: 5000, saturation: 0.55, skinTonePresence: 0.10,
            greenDominance: 1.6, blueDominance: 0.8,
            faceSize: 0.06, bodyRatio: 0.50, poseOpenness: 0.5,
            motionLevel: 0.15, numPeople: 1,
            subjectDistance: 2.5, backgroundDistance: 6, depthSeparation: 2,
            sharpness: 0.70, noiseLevel: 0.15, flickerDetected: 0
        ), PhotoParameters(
            faceBrightnessTarget: 0.40...0.58,
            evAdjustSpeed: 0.05, maxEV: 0.6, minEV: -0.4,
            focusSensitivity: 0.05,
            idealBodyRatio: 0.45...0.70,
            headroomRatio: 0.05...0.12,
            targetXPosition: 0.333,
            wbShift: 0.1, saturationBoost: 0.15,
            sharpnessEnhance: 0, noiseReduction: 0,
            sceneHint: "户外绿植·注意树枝不要穿头"
        )),

        // 7: 近距离半身像
        (SceneFeatureVector(
            avgBrightness: 0.50, dynamicRange: 0.40, backlightRatio: 1.1,
            highlightRatio: 0.20, shadowRatio: 0.15,
            colorTemperature: 5200, saturation: 0.50, skinTonePresence: 0.25,
            greenDominance: 1.0, blueDominance: 1.0,
            faceSize: 0.18, bodyRatio: 0.70, poseOpenness: 0.3,
            motionLevel: 0.05, numPeople: 1,
            subjectDistance: 1.0, backgroundDistance: 2, depthSeparation: 3,
            sharpness: 0.75, noiseLevel: 0.15, flickerDetected: 0
        ), PhotoParameters(
            faceBrightnessTarget: 0.50...0.68,
            evAdjustSpeed: 0.03, maxEV: 0.5, minEV: -0.3,
            focusSensitivity: 0.03,  // 近距对焦更精确
            idealBodyRatio: 0.55...0.80,  // 人物占更大比例
            headroomRatio: 0.04...0.08,   // 头顶留白更少
            targetXPosition: 0.4,
            wbShift: 0, saturationBoost: 0,
            sharpnessEnhance: 0.2, noiseReduction: 0,
            sceneHint: "近距肖像·保持眼神光"
        )),

        // 8: 动态/运动场景
        (SceneFeatureVector(
            avgBrightness: 0.50, dynamicRange: 0.45, backlightRatio: 1.0,
            highlightRatio: 0.20, shadowRatio: 0.20,
            colorTemperature: 5300, saturation: 0.5, skinTonePresence: 0.10,
            greenDominance: 1.0, blueDominance: 1.0,
            faceSize: 0.05, bodyRatio: 0.45, poseOpenness: 0.8,
            motionLevel: 0.8, numPeople: 1,
            subjectDistance: 3.0, backgroundDistance: 10, depthSeparation: 4,
            sharpness: 0.45, noiseLevel: 0.25, flickerDetected: 0
        ), PhotoParameters(
            faceBrightnessTarget: 0.45...0.65,
            evAdjustSpeed: 0.02, maxEV: 0.5, minEV: -0.3,  // 慢，避免过调
            focusSensitivity: 0.08,  // 降低对焦频率，容忍运动
            idealBodyRatio: 0.40...0.65,  // 留运动空间
            headroomRatio: 0.06...0.16,
            targetXPosition: 0.333,
            wbShift: 0, saturationBoost: 0,
            sharpnessEnhance: 0.3, noiseReduction: 0.1,
            sceneHint: "运动抓拍·保持快门速度"
        )),

        // 9: 多人合照
        (SceneFeatureVector(
            avgBrightness: 0.50, dynamicRange: 0.45, backlightRatio: 1.0,
            highlightRatio: 0.20, shadowRatio: 0.15,
            colorTemperature: 5200, saturation: 0.50, skinTonePresence: 0.20,
            greenDominance: 1.0, blueDominance: 1.0,
            faceSize: 0.03, bodyRatio: 0.60, poseOpenness: 0.4,
            motionLevel: 0.2, numPeople: 3,
            subjectDistance: 4.0, backgroundDistance: 10, depthSeparation: 2,
            sharpness: 0.65, noiseLevel: 0.15, flickerDetected: 0
        ), PhotoParameters(
            faceBrightnessTarget: 0.48...0.65,
            evAdjustSpeed: 0.04, maxEV: 0.5, minEV: -0.4,
            focusSensitivity: 0.06,
            idealBodyRatio: 0.55...0.80,  // 合照人物更大
            headroomRatio: 0.06...0.14,
            targetXPosition: 0.5,  // 居中
            wbShift: 0, saturationBoost: 0,
            sharpnessEnhance: 0.1, noiseReduction: 0,
            sceneHint: "多人合照·确保所有人入镜"
        )),
    ]

    // MARK: - IDW 插值

    /// k-最近邻数量
    private let kNeighbors = 5

    /// 从特征向量计算最优参数（IDW 插值）
    func computeParameters(for features: SceneFeatureVector) -> PhotoParameters {

        // 1. 计算到所有参考点的距离
        var distances: [(index: Int, distance: Double)] = []
        for (i, ref) in referencePoints.enumerated() {
            let d = features.distance(to: ref.0)
            distances.append((i, d))
        }

        // 2. 排序取 k 最近
        distances.sort { $0.distance < $1.distance }
        let neighbors = Array(distances.prefix(kNeighbors))

        // 如果最近邻距离极近（<0.1），直接返回该点参数
        if let first = neighbors.first, first.distance < 0.1 {
            return referencePoints[first.index].1
        }

        // 3. 逆距离加权
        var weights: [Double] = []
        var totalWeight: Double = 0

        for n in neighbors {
            let w = 1.0 / max(0.001, n.distance * n.distance)  // 距离平方倒数
            weights.append(w)
            totalWeight += w
        }

        // 4. 加权平均所有连续参数
        var result = PhotoParameters()

        // 曝光目标下界
        var faceTargetLower: Double = 0
        var faceTargetUpper: Double = 0
        var evSpeed: Double = 0
        var maxEV: Double = 0, minEV: Double = 0
        var focusSens: Double = 0
        var bodyLower: CGFloat = 0, bodyUpper: CGFloat = 0
        var headLower: CGFloat = 0, headUpper: CGFloat = 0
        var targetX: CGFloat = 0
        var wb: Double = 0, sat: Double = 0
        var sharp: Double = 0, noise: Double = 0

        // 场景提示：取最近邻的提示
        if let first = neighbors.first {
            result.sceneHint = referencePoints[first.index].1.sceneHint
        }

        for (i, n) in neighbors.enumerated() {
            let w = weights[i] / totalWeight
            let p = referencePoints[n.index].1

            faceTargetLower += p.faceBrightnessTarget.lowerBound * w
            faceTargetUpper += p.faceBrightnessTarget.upperBound * w
            evSpeed += p.evAdjustSpeed * w
            maxEV += p.maxEV * w
            minEV += p.minEV * w
            focusSens += p.focusSensitivity * w
            bodyLower += p.idealBodyRatio.lowerBound * w
            bodyUpper += p.idealBodyRatio.upperBound * w
            headLower += p.headroomRatio.lowerBound * w
            headUpper += p.headroomRatio.upperBound * w
            targetX += p.targetXPosition * w
            wb += p.wbShift * w
            sat += p.saturationBoost * w
            sharp += p.sharpnessEnhance * w
            noise += p.noiseReduction * w
        }

        result.faceBrightnessTarget = faceTargetLower...faceTargetUpper
        result.evAdjustSpeed = evSpeed
        result.maxEV = maxEV
        result.minEV = minEV
        result.focusSensitivity = focusSens
        result.idealBodyRatio = bodyLower...bodyUpper
        result.headroomRatio = headLower...headUpper
        result.targetXPosition = targetX
        result.wbShift = wb.clamped(-1, 1)
        result.saturationBoost = sat.clamped(-1, 1)
        result.sharpnessEnhance = sharp.clamped(0, 1)
        result.noiseReduction = noise.clamped(0, 1)

        return result
    }
}
