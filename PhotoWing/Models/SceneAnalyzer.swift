import Foundation
import CoreGraphics

/// 场景分析器：从像素缓冲区实时识别拍摄场景
/// 不依赖 CoreML，纯图像统计算法，iOS 13+ 全兼容
struct SceneAnalyzer {

    // MARK: - 场景类型

    enum SceneType: String, CaseIterable {
        case brightDaylight = "☀️ 明亮日光"
        case backlight      = "🔆 逆光"
        case lowLight       = "🌙 暗光/夜景"
        case indoorWarm     = "🏠 室内暖光"
        case beachSnow      = "🏖️ 沙滩/雪地"
        case goldenHour     = "🌇 黄金时刻"
        case greenOutdoor   = "🌳 户外绿植"
        case urbanDefault   = "🏙️ 城市/默认"

        /// 该场景的推荐策略
        var strategy: SceneStrategy {
            switch self {
            case .brightDaylight:
                return SceneStrategy(
                    faceBrightnessTarget: 0.50...0.70,
                    evAdjustSpeed: 0.04,
                    maxEV: 0.5,
                    minEV: -0.5,
                    focusSensitivity: 0.06,
                    idealBodyRatio: 0.45...0.70,
                    headroomRatio: 0.06...0.14,
                    hint: "自然光充足，正常拍摄即可"
                )
            case .backlight:
                return SceneStrategy(
                    faceBrightnessTarget: 0.32...0.52,
                    evAdjustSpeed: 0.08,
                    maxEV: 1.0,
                    minEV: 0.0,
                    focusSensitivity: 0.04,
                    idealBodyRatio: 0.50...0.75,
                    headroomRatio: 0.05...0.12,
                    hint: "逆光场景：尝试打开闪光灯补光"
                )
            case .lowLight:
                return SceneStrategy(
                    faceBrightnessTarget: 0.28...0.48,
                    evAdjustSpeed: 0.10,
                    maxEV: 1.0,
                    minEV: 0.2,
                    focusSensitivity: 0.03,
                    idealBodyRatio: 0.55...0.80,
                    headroomRatio: 0.05...0.12,
                    hint: "光线较暗：保持稳定，必要时用闪光灯"
                )
            case .indoorWarm:
                return SceneStrategy(
                    faceBrightnessTarget: 0.45...0.62,
                    evAdjustSpeed: 0.05,
                    maxEV: 0.6,
                    minEV: -0.2,
                    focusSensitivity: 0.05,
                    idealBodyRatio: 0.45...0.70,
                    headroomRatio: 0.06...0.14,
                    hint: "室内暖光：注意背景不要太杂乱"
                )
            case .beachSnow:
                return SceneStrategy(
                    faceBrightnessTarget: 0.55...0.75,
                    evAdjustSpeed: 0.05,
                    maxEV: 0.3,
                    minEV: -0.8,
                    focusSensitivity: 0.06,
                    idealBodyRatio: 0.40...0.65,
                    headroomRatio: 0.06...0.14,
                    hint: "高亮环境：注意人脸不要欠曝"
                )
            case .goldenHour:
                return SceneStrategy(
                    faceBrightnessTarget: 0.48...0.68,
                    evAdjustSpeed: 0.04,
                    maxEV: 0.5,
                    minEV: -0.3,
                    focusSensitivity: 0.05,
                    idealBodyRatio: 0.45...0.70,
                    headroomRatio: 0.6...0.14,
                    hint: "黄金光线！让她的脸朝向光源"
                )
            case .greenOutdoor:
                return SceneStrategy(
                    faceBrightnessTarget: 0.40...0.58,
                    evAdjustSpeed: 0.05,
                    maxEV: 0.6,
                    minEV: -0.4,
                    focusSensitivity: 0.06,
                    idealBodyRatio: 0.45...0.70,
                    headroomRatio: 0.05...0.12,
                    hint: "户外绿植：注意树枝不要穿头"
                )
            case .urbanDefault:
                return SceneStrategy(
                    faceBrightnessTarget: 0.48...0.65,
                    evAdjustSpeed: 0.05,
                    maxEV: 0.7,
                    minEV: -0.5,
                    focusSensitivity: 0.05,
                    idealBodyRatio: 0.45...0.72,
                    headroomRatio: 0.05...0.12,
                    hint: ""
                )
            }
        }
    }

    // MARK: - 场景策略

    struct SceneStrategy {
        let faceBrightnessTarget: ClosedRange<Double>
        let evAdjustSpeed: Double          // EV 步长
        let maxEV: Double                  // 最大曝光补偿
        let minEV: Double                  // 最小曝光补偿
        let focusSensitivity: Double       // 对焦敏感度（越小越频繁对焦）
        let idealBodyRatio: ClosedRange<CGFloat>
        let headroomRatio: ClosedRange<CGFloat>
        let hint: String                   // 场景提示
    }

    // MARK: - 分析

    /// 从像素缓冲区分析场景
    func analyze(buffer: CVPixelBuffer) -> SceneAnalysis {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return SceneAnalysis(type: .urbanDefault, confidence: 0)
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        // === 统计采样（降采样 8x 加速） ===
        let step = 8
        var totalLuminance: Double = 0
        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        var luminanceValues: [Double] = []
        var sampleCount: Int = 0

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let idx = y * bytesPerRow + x * 4
                guard idx + 3 < bytesPerRow * height else { continue }

                let b = Double(ptr[idx])
                let g = Double(ptr[idx + 1])
                let r = Double(ptr[idx + 2])

                let luminance = 0.299 * r + 0.587 * g + 0.114 * b

                totalLuminance += luminance
                totalR += r
                totalG += g
                totalB += b
                luminanceValues.append(luminance)
                sampleCount += 1
            }
        }

        guard sampleCount > 100 else {
            return SceneAnalysis(type: .urbanDefault, confidence: 0)
        }

        let avgLuminance = totalLuminance / Double(sampleCount)
        let avgR = totalR / Double(sampleCount)
        let avgG = totalG / Double(sampleCount)
        let avgB = totalB / Double(sampleCount)

        // 排序用于百分位
        luminanceValues.sort()
        let p10 = luminanceValues[Int(Double(sampleCount) * 0.1)]
        let p50 = luminanceValues[Int(Double(sampleCount) * 0.5)]
        let p90 = luminanceValues[Int(Double(sampleCount) * 0.9)]
        let dynamicRange = (p90 - p10) / 255.0

        // 颜色指标
        let avgBrightness = avgLuminance / 255.0
        let colorTemp = estimateColorTemperature(r: avgR, g: avgG, b: avgB)
        let greenDominance = avgG / max(1, (avgR + avgB) / 2)

        // === 场景分类 ===

        var scores: [(SceneType, Double)] = []

        // 1. 暗光检测
        if avgBrightness < 0.20 {
            scores.append((.lowLight, 0.9))
        } else if avgBrightness < 0.28 {
            scores.append((.lowLight, 0.6))
        } else {
            scores.append((.lowLight, 0.05))
        }

        // 2. 高亮检测（沙滩/雪地）
        if avgBrightness > 0.78 && dynamicRange > 0.6 {
            scores.append((.beachSnow, 0.85))
        } else if avgBrightness > 0.70 {
            scores.append((.beachSnow, 0.4))
        } else {
            scores.append((.beachSnow, 0.05))
        }

        // 3. 黄金时刻（暖色调 + 中等亮度）
        if colorTemp < 4500 && avgBrightness > 0.35 && avgBrightness < 0.65 {
            let warmScore = min(1.0, (5000 - colorTemp) / 1500)
            scores.append((.goldenHour, warmScore * 0.9))
        } else {
            scores.append((.goldenHour, 0.1))
        }

        // 4. 室内暖光（暖色 + 较低动态范围）
        if colorTemp < 4800 && dynamicRange < 0.45 && avgBrightness < 0.55 {
            scores.append((.indoorWarm, 0.75))
        } else if colorTemp < 4500 && avgBrightness < 0.45 {
            scores.append((.indoorWarm, 0.5))
        } else {
            scores.append((.indoorWarm, 0.1))
        }

        // 5. 绿植户外
        if greenDominance > 1.25 && avgBrightness > 0.30 {
            scores.append((.greenOutdoor, min(0.9, greenDominance / 2.0)))
        } else if greenDominance > 1.1 {
            scores.append((.greenOutdoor, 0.4))
        } else {
            scores.append((.greenOutdoor, 0.1))
        }

        // 6. 逆光检测（需要配合人脸亮度，此处预判整体高亮+高反差）
        if avgBrightness > 0.65 && dynamicRange > 0.55 {
            scores.append((.backlight, 0.6))
        } else {
            scores.append((.backlight, 0.1))
        }

        // 7. 明亮日光
        if avgBrightness > 0.55 && colorTemp > 5000 && dynamicRange > 0.4 {
            scores.append((.brightDaylight, 0.8))
        } else if avgBrightness > 0.45 && colorTemp > 4800 {
            scores.append((.brightDaylight, 0.4))
        } else {
            scores.append((.brightDaylight, 0.1))
        }

        // 8. 默认城市（兜底）
        scores.append((.urbanDefault, 0.3))

        // 选最高分
        let best = scores.max(by: { $0.1 < $1.1 })!

        return SceneAnalysis(
            type: best.0,
            confidence: best.1,
            avgBrightness: avgBrightness,
            colorTemperature: colorTemp,
            dynamicRange: dynamicRange,
            greenDominance: greenDominance,
            sceneHint: best.0.strategy.hint
        )
    }

    // MARK: - 色温估算

    /// 简化色温估算（基于 R/B 比值），单位开尔文
    private func estimateColorTemperature(r: Double, g: Double, b: Double) -> Double {
        let rbRatio = (r / max(1, b))
        // 经验公式：R/B 越高越暖（低色温），越低越冷（高色温）
        if rbRatio > 1.5 {
            return 3000 + (2.5 - rbRatio) * 1000  // 暖色 ~3000-4500K
        } else if rbRatio > 1.0 {
            return 4500 + (1.5 - rbRatio) * 2000  // 中性 ~4500-5500K
        } else {
            return 5500 + (1.0 - rbRatio) * 2000  // 冷色 ~5500-7500K
        }
    }
}

// MARK: - 分析结果

struct SceneAnalysis {
    let type: SceneAnalyzer.SceneType
    let confidence: Double          // 0-1
    let avgBrightness: Double
    let colorTemperature: Double    // 开尔文
    let dynamicRange: Double        // 0-1
    let greenDominance: Double
    let sceneHint: String
}

// MARK: - 自适应参数提供者

extension SceneAnalyzer.SceneType {

    /// 获取当前场景的曝光目标
    var faceBrightnessTarget: ClosedRange<Double> {
        strategy.faceBrightnessTarget
    }

    /// EV 调整速度
    var evAdjustSpeed: Double {
        strategy.evAdjustSpeed
    }

    /// 构图人物占比范围
    var idealBodyRatio: ClosedRange<CGFloat> {
        strategy.idealBodyRatio
    }

    /// 头顶留白范围
    var headroomRatio: ClosedRange<CGFloat> {
        strategy.headroomRatio
    }
}
