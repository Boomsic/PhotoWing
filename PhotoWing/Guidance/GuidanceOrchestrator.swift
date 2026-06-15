import Foundation
import Combine

// MARK: - v2 总调度器（连续自适应）

/// 抛弃离散场景分类，使用：
/// - 18维连续特征向量 → IDW 插值 → 所有参数平滑解算
/// - 连续姿态质量评分（非预设匹配）
/// - LiDAR 深度感知
/// - 用户偏好学习
/// - 多目标联合优化
@MainActor
final class GuidanceOrchestrator: ObservableObject {

    @Published var result = GuidanceResult()
    @Published var selectedPose: ReferencePose? = ReferencePose.library.first
    @Published var isPoseModeActive = false

    // 连续系统状态
    @Published var featureVector = SceneFeatureVector()
    @Published var currentParameters = AdaptiveParameterEngine.PhotoParameters()
    @Published var poseQuality = PoseQualityAnalyzer.PoseQuality()
    @Published var depthInfo = DepthAnalyzer.DepthInfo()
    @Published var sceneDescription: String = "分析中..."
    @Published var sceneJustChanged: String = ""

    // 引擎
    private let sceneAnalyzer = ContinuousSceneAnalyzer()
    private let paramEngine = AdaptiveParameterEngine()
    private let poseAnalyzer = PoseQualityAnalyzer()
    private let depthAnalyzer = DepthAnalyzer()
    private let optimizer = MultiObjectiveOptimizer()

    private let compositionEngine = CompositionEngine()
    private let exposureEngine = ExposureEngine()
    private let focusEngine = FocusEngine()
    private let backgroundEngine = BackgroundEngine()

    // 偏好学习
    private var preferenceLearner = UserPreferenceLearner()
    private var previousSkeleton: BodySkeleton?

    // 节流
    private var lastSceneAnalysis: Date = .distantPast
    private let analysisInterval: TimeInterval = 0.3

    /// 每帧调用
    func update(skeleton: BodySkeleton?,
                faceBrightness: Double,
                backgroundBrightness: Double,
                isFocusLocked: Bool,
                pixelBuffer: CVPBuffer?,
                viewSize: CGSize,
                depthData: AVDepthData? = nil) {

        // === 1. 提取 18 维连续特征向量 ===
        if let buffer = pixelBuffer {
            let now = Date()
            if now.timeIntervalSince(lastSceneAnalysis) >= analysisInterval {
                var faceRect: CGRect? = nil
                if let head = skeleton?.headPosition {
                    let size: CGFloat = 0.1
                    faceRect = CGRect(x: head.x - size/2, y: head.y - size/2,
                                      width: size, height: size)
                }
                featureVector = sceneAnalyzer.extract(
                    from: buffer,
                    faceRect: faceRect,
                    skeleton: skeleton
                )
                lastSceneAnalysis = now
            }
        }

        // === 2. IDW 插值 → 连续参数 ===
        currentParameters = paramEngine.computeParameters(for: featureVector)

        // 用户偏好修正
        let userEVBias = preferenceLearner.predictEVBias(for: featureVector)
        var adjustedParams = currentParameters
        adjustedParams.faceBrightnessTarget =
            (currentParameters.faceBrightnessTarget.lowerBound + userEVBias * 0.3)...
            (currentParameters.faceBrightnessTarget.upperBound + userEVBias * 0.3)

        // === 3. 连续姿态质量 ===
        if let skeleton {
            poseQuality = poseAnalyzer.evaluate(skeleton, previousSkeleton: previousSkeleton)
            previousSkeleton = skeleton
        }

        // === 4. 深度分析 ===
        if let depthData, let skeleton {
            depthInfo = depthAnalyzer.analyze(
                depthData: depthData,
                skeleton: skeleton,
                imageSize: viewSize
            )
        } else if let skeleton {
            depthInfo = depthAnalyzer.estimateFromSkeleton(skeleton)
        }

        // === 5. 构图指导（场景自适应参数） ===
        var guidance = GuidanceResult()

        if let skeleton {
            var compEngine = compositionEngine
            compEngine.idealBodyRatio = adjustedParams.idealBodyRatio
            compEngine.headroomRatio = adjustedParams.headroomRatio
            guidance.composition = compEngine.evaluate(
                skeleton: skeleton,
                viewSize: viewSize
            )
        } else {
            guidance.composition = CompositionGuidance(score: 0, hint: "正在检测人物...")
        }

        // === 6. 曝光指导（场景自适应） ===
        var expEngine = exposureEngine
        expEngine.idealFaceBrightness = adjustedParams.faceBrightnessTarget
        guidance.exposure = expEngine.evaluate(
            faceBrightness: faceBrightness,
            backgroundBrightness: backgroundBrightness,
            skeleton: skeleton
        )

        // === 7. 姿势指导（连续评分 + 可选预设匹配） ===
        if isPoseModeActive, let reference = selectedPose, let skeleton {
            let poseEngine = PoseEngine()
            guidance.pose = poseEngine.evaluate(skeleton: skeleton, reference: reference)
            guidance.composition.showPoseGhost = true
        } else {
            // 连续评分模式
            guidance.pose = PoseGuidance(
                score: Int(poseQuality.overall * 100),
                hint: poseQuality.suggestions.first ?? "",
                activePose: nil,
                jointScores: [:]
            )
        }

        // === 8. 聚焦 ===
        guidance.focus = focusEngine.evaluate(
            skeleton: skeleton,
            isFocusLocked: isFocusLocked,
            pixelBuffer: pixelBuffer
        )

        // === 9. 背景 ===
        guidance.background = backgroundEngine.evaluate(skeleton: skeleton)

        // === 10. 联合优化 ===
        let jointAction = optimizer.optimize(
            faceBrightness: faceBrightness,
            targetBrightness: adjustedParams.faceBrightnessTarget,
            facePosition: skeleton?.headPosition,
            focusScore: guidance.focus.score,
            compositionScore: guidance.composition.score,
            depthInfo: depthInfo
        )

        // 如果有联合构图建议
        if !jointAction.compositionHint.isEmpty && guidance.composition.hint.isEmpty {
            guidance.composition.hint = jointAction.compositionHint
        }

        // === 11. 场景描述 ===
        sceneDescription = generateSceneDescription(
            features: featureVector,
            depth: depthInfo,
            pose: poseQuality
        )

        result = guidance
    }

    // MARK: - 场景描述生成

    private func generateSceneDescription(features: SceneFeatureVector,
                                           depth: DepthAnalyzer.DepthInfo,
                                           pose: PoseQualityAnalyzer.PoseQuality) -> String {
        var parts: [String] = []

        // 亮度
        if features.avgBrightness < 0.18 { parts.append("极暗") }
        else if features.avgBrightness < 0.35 { parts.append("暗光") }
        else if features.avgBrightness > 0.75 { parts.append("高亮") }
        else { parts.append("适中") }

        // 色温
        if features.colorTemperature < 3800 { parts.append("·暖调") }
        else if features.colorTemperature > 6000 { parts.append("·冷调") }

        // 逆光
        if features.backlightRatio < 0.4 { parts.append("·逆光") }

        // 距离
        if depth.subjectDistance < 1.0 { parts.append("·近距") }
        else if depth.subjectDistance > 4 { parts.append("·远距") }

        // 人数
        if features.numPeople > 2 { parts.append("·\(Int(features.numPeople))人") }

        // 动态
        if features.motionLevel > 0.5 { parts.append("·运动") }

        // 姿态
        if pose.overall > 0.75 { parts.append("·姿态佳") }

        return parts.joined()
    }

    // MARK: - 偏好学习接口

    func recordUserEVAdjustment(_ evOffset: Double) {
        preferenceLearner.recordCorrection(
            features: featureVector,
            evOffset: evOffset
        )
    }

    // MARK: - 场景策略（兼容旧接口）

    var sceneStrategy: SceneAnalyzer.SceneStrategy {
        // 兼容旧 SceneType 接口：取最近场景的 strategy
        let params = paramEngine.computeParameters(for: featureVector)
        return SceneAnalyzer.SceneStrategy(
            faceBrightnessTarget: params.faceBrightnessTarget,
            evAdjustSpeed: params.evAdjustSpeed,
            maxEV: params.maxEV,
            minEV: params.minEV,
            focusSensitivity: params.focusSensitivity,
            idealBodyRatio: params.idealBodyRatio,
            headroomRatio: params.headroomRatio,
            hint: params.sceneHint
        )
    }

    var currentScene: SceneAnalyzer.SceneType {
        // 兼容旧 UI 层，返回最近似的离散场景类型
        let fv = featureVector
        if fv.avgBrightness < 0.18 { return .lowLight }
        if fv.backlightRatio < 0.35 { return .backlight }
        if fv.avgBrightness > 0.75 { return .beachSnow }
        if fv.colorTemperature < 4000 && fv.avgBrightness < 0.5 { return .indoorWarm }
        if fv.colorTemperature < 4500 && fv.avgBrightness > 0.35 { return .goldenHour }
        if fv.greenDominance > 1.3 { return .greenOutdoor }
        if fv.avgBrightness > 0.55 { return .brightDaylight }
        return .urbanDefault
    }

    func togglePoseMode() { isPoseModeActive.toggle() }
    func selectPose(_ pose: ReferencePose) { selectedPose = pose; isPoseModeActive = true }
}

typealias CVPBuffer = CVPixelBuffer
