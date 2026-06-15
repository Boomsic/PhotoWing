import Foundation

/// 聚焦确认引擎：检测人脸区域清晰度
struct FocusEngine {

    /// 粗略评估人脸区域是否清晰
    func evaluate(skeleton: BodySkeleton?,
                  isFocusLocked: Bool,
                  pixelBuffer: CVPixelBuffer?) -> FocusGuidance {
        var guidance = FocusGuidance()
        guidance.isFaceLocked = isFocusLocked

        guard skeleton != nil else {
            guidance.score = 0
            guidance.hint = "未检测到人物"
            return guidance
        }

        var score: Double = 70

        // 焦点锁定状态
        if isFocusLocked {
            score += 20
        } else {
            score -= 15
            guidance.hint = "🔍 轻点屏幕对焦到脸上"
        }

        // 如果有 pixelBuffer，计算人脸区域的高频分量（拉普拉斯方差）
        if let buffer = pixelBuffer, let head = skeleton?.headPosition {
            let sharpness = estimateSharpness(buffer: buffer, around: head)
            if sharpness < 0.3 {
                score -= 30
                guidance.hint = "🔍 人脸有点糊，轻点人脸重新对焦"
            } else if sharpness > 0.6 {
                score += 15
            }
        }

        guidance.score = Int(max(0, min(100, score)))

        if guidance.hint.isEmpty && guidance.score >= 80 {
            guidance.hint = "✅ 对焦清晰"
        }

        return guidance
    }

    /// 在人脸区域做拉普拉斯清晰度检测
    private func estimateSharpness(buffer: CVPixelBuffer, around center: CGPoint) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return 0.5 }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        // 人脸区域（归一化转像素坐标）
        let cx = Int(center.x * CGFloat(width))
        let cy = Int(center.y * CGFloat(height))
        let roi = 60  // 人脸区域半径
        let x0 = max(2, cx - roi)
        let y0 = max(2, cy - roi)
        let x1 = min(width - 2, cx + roi)
        let y1 = min(height - 2, cy + roi)

        var laplacianSum: Double = 0
        var count: Int = 0

        for y in stride(from: y0, to: y1, by: 2) {
            for x in stride(from: x0, to: x1, by: 2) {
                let idx = y * bytesPerRow + x * 4
                // 只用绿色通道算梯度（人眼最敏感）
                let g00 = Double(ptr[idx + 1])
                let g10 = Double(ptr[idx + 1 + 4])
                let g01 = Double(ptr[idx + 1 + bytesPerRow])
                let lap = abs(g00 * 4 - g10 - g01 -
                               Double(ptr[idx + 1 - 4]) -
                               Double(ptr[idx + 1 - bytesPerRow]))
                laplacianSum += lap
                count += 1
            }
        }

        guard count > 0 else { return 0.5 }
        let variance = laplacianSum / Double(count)
        return min(1.0, variance / 80.0)
    }
}

// MARK: - 背景评估引擎

struct BackgroundEngine {

    func evaluate(skeleton: BodySkeleton?) -> BackgroundGuidance {
        var guidance = BackgroundGuidance()

        guard let skeleton, let head = skeleton.headPosition,
              let _ = skeleton.boundingBox else {
            guidance.score = 70
            return guidance
        }

        // 注意：真正的语义分割需要 iOS 14+ Vision VNGeneratePersonSegmentationRequest
        // 此处提供评分框架，实际集成时替换
        var score: Double = 80

        // 提示检查：头上方是否有干扰物（纹理或边缘集中）
        // 简化版：由外部语义分割模块填充
        if head.y < 0.15 {
            score -= 15
            guidance.hint = "⚠️ 头顶空间太少"
        }

        // 检测人物是否太靠近画面边缘（可能被裁切）
        if let box = skeleton.boundingBox {
            if box.minX < 0.02 || box.maxX > 0.98 {
                score -= 10
                guidance.hint = guidance.hint.isEmpty
                    ? "⚠️ 人物太靠边"
                    : guidance.hint
            }
        }

        guidance.score = Int(max(0, min(100, score)))
        guidance.hasHeadIntersection = false  // 需语义分割模块填充
        guidance.clutterLevel = 0.3           // 需语义分割模块填充

        return guidance
    }
}
