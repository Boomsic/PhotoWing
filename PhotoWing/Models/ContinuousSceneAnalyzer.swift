import Foundation
import Accelerate

// MARK: - 连续场景特征向量（替代离散 SceneType）

/// 18 维连续特征向量，每帧实时提取
/// 不是"这是什么场景"的分类问题，而是"当前画面处于连续空间中的哪个点"
struct SceneFeatureVector {
    // === 光照（5维） ===
    var avgBrightness: Double = 0.5        // 0-1 平均亮度
    var dynamicRange: Double = 0.4         // 0-1 动态范围 (p95-p5)
    var backlightRatio: Double = 1.0       // 人脸亮度/背景亮度，<0.5=逆光
    var highlightRatio: Double = 0.3       // 0-1 高光占比
    var shadowRatio: Double = 0.2          // 0-1 阴影占比

    // === 色彩（5维） ===
    var colorTemperature: Double = 5500    // 2500-7500K
    var saturation: Double = 0.5           // 0-1
    var skinTonePresence: Double = 0.0     // 0-1 肤色像素占比
    var greenDominance: Double = 1.0       // G/(R+B)/2
    var blueDominance: Double = 1.0        // B/(R+G)/2

    // === 主体（5维） ===
    var faceSize: Double = 0.0             // 人脸占画面比例 0-1
    var bodyRatio: Double = 0.0            // 人体占画面比例 0-1
    var poseOpenness: Double = 0.5         // 0-1 姿态开放度（肢体展开程度）
    var motionLevel: Double = 0.0          // 0-1 运动幅度（帧间骨骼位移）
    var numPeople: Double = 1.0            // 人数

    // === 深度（3维，iPhone 16 Pro LiDAR） ===
    var subjectDistance: Double = 2.0      // 米
    var backgroundDistance: Double = 5.0   // 米
    var depthSeparation: Double = 1.0      // 主体与背景的深度分离度

    // === 质量（3维） ===
    var sharpness: Double = 0.7            // 0-1
    var noiseLevel: Double = 0.2           // 0-1
    var flickerDetected: Double = 0.0      // 0-1 50/60Hz 频闪

    // === 总维数 ===
    static let dimensionCount = 18

    /// 转为归一化数组（用于距离计算）
    func normalizedArray() -> [Double] {
        [
            avgBrightness,
            dynamicRange,
            backlightRatio.clamped(0, 3),
            highlightRatio,
            shadowRatio,
            (colorTemperature - 2500) / 5000,  // → 0-1
            saturation,
            skinTonePresence,
            greenDominance.clamped(0, 3) / 3,
            blueDominance.clamped(0, 3) / 3,
            faceSize,
            bodyRatio,
            poseOpenness,
            motionLevel,
            numPeople.clamped(1, 10) / 10,
            subjectDistance / 10,
            backgroundDistance / 20,
            depthSeparation / 5,
            sharpness,
            noiseLevel,
            flickerDetected
        ]
    }

    /// 两个特征向量的欧氏距离
    func distance(to other: SceneFeatureVector) -> Double {
        let a = self.normalizedArray()
        let b = other.normalizedArray()
        var sum: Double = 0
        for i in 0..<min(a.count, b.count) {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sqrt(sum)
    }
}

// MARK: - 连续场景分析器

struct ContinuousSceneAnalyzer {

    /// 从像素缓冲区提取 18 维连续特征向量
    func extract(from buffer: CVPixelBuffer,
                 faceRect: CGRect?,
                 skeleton: BodySkeleton?) -> SceneFeatureVector {

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return SceneFeatureVector()
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        let step = 8
        var features = SceneFeatureVector()

        // === 全图统计 ===
        var luminances: [Double] = []
        var totalR: Double = 0, totalG: Double = 0, totalB: Double = 0
        var skinPixels: Int = 0
        var sampleCount: Int = 0

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let idx = y * bytesPerRow + x * 4
                guard idx + 3 < bytesPerRow * height else { continue }

                let b = Double(ptr[idx])
                let g = Double(ptr[idx + 1])
                let r = Double(ptr[idx + 2])
                let lum = 0.299 * r + 0.587 * g + 0.114 * b

                luminances.append(lum)
                totalR += r; totalG += g; totalB += b

                // 肤色检测（简化：RGB 空间肤色范围）
                if r > 95 && g > 40 && b > 20 &&
                    max(r, g, b) - min(r, g, b) > 15 &&
                    abs(r - g) > 15 && r > g && r > b {
                    skinPixels += 1
                }

                sampleCount += 1
            }
        }

        guard sampleCount > 100 else { return features }

        // 排序
        luminances.sort()
        let avgLum = luminances.reduce(0, +) / Double(sampleCount)
        let p5 = luminances[Int(Double(sampleCount) * 0.05)]
        let p50 = luminances[Int(Double(sampleCount) * 0.50)]
        let p95 = luminances[Int(Double(sampleCount) * 0.95)]

        features.avgBrightness = avgLum / 255.0
        features.dynamicRange = (p95 - p5) / 255.0
        features.skinTonePresence = Double(skinPixels) / Double(sampleCount)

        let avgR = totalR / Double(sampleCount)
        let avgG = totalG / Double(sampleCount)
        let avgB = totalB / Double(sampleCount)

        features.colorTemperature = estimateCT(r: avgR, g: avgG, b: avgB)
        features.saturation = (max(avgR, avgG, avgB) - min(avgR, avgG, avgB)) / max(1, max(avgR, avgG, avgB))
        features.greenDominance = avgG / max(1, (avgR + avgB) / 2)
        features.blueDominance = avgB / max(1, (avgR + avgG) / 2)

        features.highlightRatio = Double(luminances.filter { $0 > 200 }.count) / Double(sampleCount)
        features.shadowRatio = Double(luminances.filter { $0 < 30 }.count) / Double(sampleCount)

        // === 主体特征 ===
        if let skeleton {
            features.bodyRatio = skeleton.boundingBox?.height ?? 0
            features.poseOpenness = computePoseOpenness(skeleton)
            features.faceSize = estimateFaceSize(skeleton, imageWidth: width, imageHeight: height)
            features.numPeople = 1  // 当前只追踪单人
        }

        // === 逆光比 ===
        if let faceRect {
            let faceLum = sampleRegionLuminance(ptr: ptr, bytesPerRow: bytesPerRow,
                                                 width: width, height: height,
                                                 rect: faceRect)
            features.backlightRatio = faceLum / max(0.01, avgLum / 255.0)
        }

        // === 运动检测（需要前后帧对比，简化为当前帧内边缘密度） ===
        features.motionLevel = estimateMotion(ptr: ptr, width: width, height: height, bytesPerRow: bytesPerRow)

        // === 清晰度 ===
        features.sharpness = estimateSharpness(ptr: ptr, width: width, height: height, bytesPerRow: bytesPerRow)

        // === 频闪检测 ===
        features.flickerDetected = detectFlicker(luminances: luminances, sampleCount: sampleCount)

        return features
    }

    // MARK: - 辅助

    private func estimateCT(r: Double, g: Double, b: Double) -> Double {
        let ratio = (r / max(1, b))
        return 3000 + (3.0 - ratio.clamped(0.5, 2.5)) * 1500
    }

    private func computePoseOpenness(_ skeleton: BodySkeleton) -> Double {
        // 肢体展开程度 = 手腕间距离 + 脚踝间距离，归一化到身高
        guard let lw = skeleton.joint(.leftWrist), let rw = skeleton.joint(.rightWrist),
              let la = skeleton.joint(.leftAnkle), let ra = skeleton.joint(.rightAnkle),
              let head = skeleton.headPosition else { return 0.5 }

        let armSpread = hypot(lw.x - rw.x, lw.y - rw.y)
        let legSpread = hypot(la.x - ra.x, la.y - ra.y)
        let bodyHeight = max(0.1, la.y - head.y)  // 脚到头的垂直距离

        let openness = (armSpread + legSpread) / (bodyHeight * 2)
        return openness.clamped(0, 1) * 1.5  // 放大范围
    }

    private func estimateFaceSize(_ skeleton: BodySkeleton, imageWidth: Int, imageHeight: Int) -> Double {
        guard let head = skeleton.headPosition,
              let leftShoulder = skeleton.joint(.leftShoulder),
              let rightShoulder = skeleton.joint(.rightShoulder) else { return 0 }

        let shoulderWidth = hypot(leftShoulder.x - rightShoulder.x,
                                   leftShoulder.y - rightShoulder.y)
        // 脸宽 ≈ 肩宽 * 0.4（人体比例）
        let faceWidth = shoulderWidth * 0.4
        return faceWidth  // 已经是归一化的
    }

    private func sampleRegionLuminance(ptr: UnsafePointer<UInt8>, bytesPerRow: Int,
                                        width: Int, height: Int,
                                        rect: CGRect) -> Double {
        let x0 = max(0, Int(rect.minX * Double(width)))
        let y0 = max(0, Int(rect.minY * Double(height)))
        let x1 = min(width, Int(rect.maxX * Double(width)))
        let y1 = min(height, Int(rect.maxY * Double(height)))
        var total: Double = 0
        var count: Int = 0
        let step = 4
        for y in stride(from: y0, to: y1, by: step) {
            for x in stride(from: x0, to: x1, by: step) {
                let idx = y * bytesPerRow + x * 4
                if idx + 2 < bytesPerRow * height {
                    total += 0.299 * Double(ptr[idx + 2]) + 0.587 * Double(ptr[idx + 1]) + 0.114 * Double(ptr[idx])
                    count += 1
                }
            }
        }
        return count > 0 ? total / Double(count) / 255.0 : 0.5
    }

    private func estimateMotion(ptr: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> Double {
        // 用梯度幅值近似运动模糊程度（高梯度=清晰，低梯度=可能运动模糊）
        var totalGrad: Double = 0
        var count: Int = 0
        let step = 16
        for y in stride(from: step, to: height - step, by: step) {
            for x in stride(from: step, to: width - step, by: step) {
                let idx = y * bytesPerRow + x * 4
                let idxRight = y * bytesPerRow + (x + step) * 4
                let idxDown = (y + step) * bytesPerRow + x * 4
                if idxRight + 2 < bytesPerRow * height && idxDown + 2 < bytesPerRow * height {
                    let g1 = Double(ptr[idx + 1])
                    let g2 = Double(ptr[idxRight + 1])
                    let g3 = Double(ptr[idxDown + 1])
                    totalGrad += abs(g1 - g2) + abs(g1 - g3)
                    count += 1
                }
            }
        }
        let avgGradient = count > 0 ? totalGrad / Double(count) : 50
        // 低梯度 → 高运动模糊
        return (1.0 - min(1.0, avgGradient / 100.0)).clamped(0, 1)
    }

    private func estimateSharpness(ptr: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> Double {
        var lapSum: Double = 0
        var count: Int = 0
        let cx = width / 2, cy = height / 2, roi = 100
        let step = 4
        for y in stride(from: max(step, cy - roi), to: min(height - step, cy + roi), by: step) {
            for x in stride(from: max(step, cx - roi), to: min(width - step, cx + roi), by: step) {
                let idx = y * bytesPerRow + x * 4
                let g = Double(ptr[idx + 1])
                let gr = Double(ptr[idx + 1 + 4 * step])
                let gd = Double(ptr[idx + 1 + bytesPerRow * step])
                let gl = Double(ptr[idx + 1 - 4 * step])
                let gu = Double(ptr[idx + 1 - bytesPerRow * step])
                lapSum += abs(g * 4 - gr - gd - gl - gu)
                count += 1
            }
        }
        let lap = count > 0 ? lapSum / Double(count) : 30
        return min(1.0, lap / 60.0)
    }

    private func detectFlicker(luminances: [Double], sampleCount: Int) -> Double {
        // 简化：检查亮度是否有明显周期性（人工光源 50/60Hz）
        guard sampleCount > 100 else { return 0 }
        // 按行采样亮度，检查行间波动
        // 简化实现：高动态范围+低平均亮度 → 可能存在频闪
        let avg = luminances.reduce(0, +) / Double(sampleCount)
        let variance = luminances.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Double(sampleCount)
        let cv = sqrt(variance) / max(0.01, avg)
        return cv > 0.5 ? min(1.0, (cv - 0.5) * 2) : 0
    }
}

// MARK: - Extension

extension Double {
    func clamped(_ low: Double, _ high: Double) -> Double {
        max(low, min(high, self))
    }
}
