import Foundation
import AVFoundation

// MARK: - LiDAR 深度分析器（iPhone 16 Pro）

/// 利用 LiDAR 扫描仪获取精确深度信息
/// 用于：构图优化、背景虚化评估、距离提醒
struct DepthAnalyzer {

    struct DepthInfo {
        var subjectDistance: Double = 2.0      // 主体距离（米）
        var backgroundDistance: Double = 5.0    // 背景距离（米）
        var depthSeparation: Double = 1.0       // 主体与背景分离度
        var isSubjectIsolated: Bool = false     // 主体是否从背景分离
        var foregroundObjects: Bool = false     // 前景是否有遮挡物
        var suggestedDistance: String = ""      // 距离建议
    }

    /// 从 AVDepthData 提取深度信息（需要 iPhone 16 Pro LiDAR）
    func analyze(depthData: AVDepthData?,
                 skeleton: BodySkeleton?,
                 imageSize: CGSize) -> DepthInfo {
        var info = DepthInfo()

        guard let depthData, let skeleton,
              let head = skeleton.headPosition else {
            return info
        }

        let depthMap = depthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard let ptr = CVPixelBufferGetBaseAddress(depthMap)?
            .assumingMemoryBound(to: Float32.self) else { return info }

        // 主体深度（人脸区域中值）
        let headX = Int(head.x * CGFloat(width))
        let headY = Int(head.y * CGFloat(height))
        let roi = 15
        var subjectDepths: [Float] = []
        for dy in -roi...roi {
            for dx in -roi...roi {
                let x = headX + dx, y = headY + dy
                if x >= 0 && x < width && y >= 0 && y < height {
                    let d = ptr[y * width + x]
                    if d > 0 { subjectDepths.append(d) }
                }
            }
        }
        subjectDepths.sort()
        let subjectDepth = Double(subjectDepths.count > 0
            ? subjectDepths[subjectDepths.count / 2]
            : 2000) / 1000.0  // mm → m

        // 背景深度（画面边缘中值）
        let margin = 20
        var bgDepths: [Float] = []
        for y in 0..<min(40, height) {
            for x in 0..<min(40, width) {
                let d = ptr[y * width + x]
                if d > 0 { bgDepths.append(d) }
            }
        }
        bgDepths.sort()
        let bgDepth = Double(bgDepths.count > 0
            ? bgDepths[bgDepths.count / 2]
            : 5000) / 1000.0

        info.subjectDistance = subjectDepth
        info.backgroundDistance = bgDepth
        info.depthSeparation = bgDepth - subjectDepth
        info.isSubjectIsolated = info.depthSeparation > 1.5  // 1.5m 以上分离
        info.foregroundObjects = subjectDepths.first.map { Double($0) / 1000.0 } ?? 0 < subjectDepth - 0.3

        // 建议
        if info.isSubjectIsolated {
            info.suggestedDistance = "背景虚化效果完美"
        } else if info.depthSeparation < 0.5 {
            info.suggestedDistance = "让拍摄对象离背景远一点"
        } else {
            info.suggestedDistance = ""
        }

        return info
    }

    /// 无 LiDAR 时的降级方案：用骨骼估算距离
    func estimateFromSkeleton(_ skeleton: BodySkeleton) -> DepthInfo {
        var info = DepthInfo()
        // 用头部在画面中的占比估算距离
        // 成人头部约 0.22m 宽，画面宽度对应传感器视角
        guard let head = skeleton.headPosition,
              let le = skeleton.joint(.leftEar),
              let re = skeleton.joint(.rightEar) else { return info }

        let headWidthInFrame = abs(le.x - re.x)  // 归一化
        // iPhone 广角 FOV ≈ 70°(水平)，约 0.5m 对应画面宽 1.0
        let estimatedDistance = 0.22 / (headWidthInFrame * 2.0)
        info.subjectDistance = estimatedDistance.clamped(0.3, 10)

        if let box = skeleton.boundingBox {
            let bgEstimate = estimatedDistance + Double(box.height) * 3
            info.backgroundDistance = bgEstimate.clamped(1, 30)
            info.depthSeparation = info.backgroundDistance - info.subjectDistance
        }

        return info
    }
}

// MARK: - 用户偏好学习器

/// 记住用户手动修正，个性化参数
struct UserPreferenceLearner {

    struct PreferenceRecord: Codable {
        var featureSnapshot: [Double]   // 修正时的特征向量
        var userEVCorrection: Double     // 用户手动调的 EV 偏移
        var timestamp: Date
    }

    private let maxRecords = 50
    private var records: [PreferenceRecord] = []

    /// 记录用户的一次手动 EV 修正
    mutating func recordCorrection(features: SceneFeatureVector,
                                    evOffset: Double) {
        records.append(PreferenceRecord(
            featureSnapshot: features.normalizedArray(),
            userEVCorrection: evOffset,
            timestamp: Date()
        ))
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
    }

    /// 给定当前场景，预测用户的 EV 偏好
    func predictEVBias(for features: SceneFeatureVector) -> Double {
        guard !records.isEmpty else { return 0 }

        // 找最相似的 3 条历史记录
        var scored: [(Double, Double)] = []  // (距离, EV修正)
        for r in records {
            let refFeatures = featuresFromSnapshot(r.featureSnapshot)
            let d = features.distance(to: refFeatures)
            scored.append((d, r.userEVCorrection))
        }

        scored.sort { $0.0 < $1.0 }
        let top = scored.prefix(3)

        // IDW
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        for (d, ev) in top {
            let w = 1.0 / max(0.001, d * d)
            weightedSum += ev * w
            totalWeight += w
        }

        return totalWeight > 0 ? weightedSum / totalWeight : 0
    }

    private func featuresFromSnapshot(_ snapshot: [Double]) -> SceneFeatureVector {
        // 简化反序列化
        SceneFeatureVector(
            avgBrightness: snapshot[safe: 0] ?? 0.5,
            backlightRatio: snapshot[safe: 2] ?? 1.0,
            faceSize: snapshot[safe: 10] ?? 0.05,
            bodyRatio: snapshot[safe: 11] ?? 0.5,
            subjectDistance: snapshot[safe: 15] ?? 2.0
        )
    }
}

// MARK: - 多目标联合优化器

/// 曝光、对焦、构图不是独立问题，联合优化
struct MultiObjectiveOptimizer {

    /// 统一评估当前拍摄状态，返回联合优化后的动作
    struct JointAction {
        var evBias: Double = 0          // 建议曝光补偿
        var focusPoint: CGPoint?        // 建议对焦点
        var compositionHint: String = "" // 构图建议
        var overallQuality: Double = 0   // 联合质量分 0-1
    }

    /// 同时考虑曝光+对焦+构图，避免各自为政
    func optimize(faceBrightness: Double,
                  targetBrightness: ClosedRange<Double>,
                  facePosition: CGPoint?,
                  focusScore: Int,
                  compositionScore: Int,
                  depthInfo: DepthAnalyzer.DepthInfo) -> JointAction {

        var action = JointAction()

        // === 联合质量分 ===
        let expQuality = gaussianScore(faceBrightness,
                                        center: (targetBrightness.lowerBound + targetBrightness.upperBound) / 2,
                                        width: (targetBrightness.upperBound - targetBrightness.lowerBound) / 2)
        let focusQuality = Double(focusScore) / 100.0
        let compQuality = Double(compositionScore) / 100.0
        let depthQuality = depthInfo.isSubjectIsolated ? 1.0 : 0.5

        action.overallQuality = (
            expQuality * 0.3 +
            focusQuality * 0.25 +
            compQuality * 0.30 +
            depthQuality * 0.15
        )

        // === 曝光建议 ===
        if !targetBrightness.contains(faceBrightness) {
            let mid = (targetBrightness.lowerBound + targetBrightness.upperBound) / 2
            action.evBias = (mid - faceBrightness) * 2.0
        }

        // === 对焦点 ===
        action.focusPoint = facePosition

        // === 构图建议（根据深度信息调整） ===
        if compositionScore < 60 {
            if depthInfo.depthSeparation < 0.5 && compositionScore < 40 {
                action.compositionHint = "让拍摄对象离背景远一点，虚化更好看"
            }
        }

        return action
    }

    private func gaussianScore(_ x: Double, center: Double, width: Double) -> Double {
        exp(-pow(x - center, 2) / max(0.001, 2 * width * width))
    }
}

// MARK: - 工具

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
