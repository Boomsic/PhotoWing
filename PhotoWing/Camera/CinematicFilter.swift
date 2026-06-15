import Metal
import MetalKit
import CoreImage

/// Metal 滤镜管线：封装电影调色 + 遮幅叠加
final class CinematicFilter {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let gradePipeline: MTLComputePipelineState
    private let letterboxPipeline: MTLComputePipelineState
    private let context: CIContext

    private var time: Float = 0

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            return nil
        }

        self.device = device
        self.commandQueue = queue

        guard let gradeFunc = library.makeFunction(name: "cinematicGrade"),
              let letterboxFunc = library.makeFunction(name: "letterboxOverlay") else {
            return nil
        }

        do {
            gradePipeline = try device.makeComputePipelineState(function: gradeFunc)
            letterboxPipeline = try device.makeComputePipelineState(function: letterboxFunc)
        } catch {
            return nil
        }

        context = CIContext(mtlDevice: device)
    }

    /// 应用电影调色 + 遮幅
    func apply(to pixelBuffer: CVPixelBuffer,
               config: CinematicEngine.CinematicConfig,
               viewSize: CGSize) -> CVPixelBuffer? {

        guard config.isActive else { return pixelBuffer }

        time += 0.016  // ~60fps 时间推进

        // 创建 Metal 纹理
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cvTexture)

        guard let textureCache = makeTextureCache(),
              let inTexture = makeTexture(from: pixelBuffer, cache: textureCache),
              let outTexture = makeEmptyTexture(width: width, height: height) else {
            return pixelBuffer
        }

        // 1. 色彩调色
        guard let cmdBuffer = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeComputeCommandEncoder() else {
            return pixelBuffer
        }

        var uniforms = CinematicEngine.CinematicConfig.ColorGrade.tealOrange
        let grade = config.colorGrade
        let matrix = grade.colorMatrix
        var uniformsStruct = ColorGradeUniforms(
            colorMatrix: matrix,
            brightnessOffset: grade.brightnessOffset,
            saturationScale: grade.saturationScale,
            contrastGamma: grade.contrastGamma,
            filmGrain: Float(config.filmGrain),
            time: time
        )

        encoder.setComputePipelineState(gradePipeline)
        encoder.setTexture(inTexture, index: 0)
        encoder.setTexture(outTexture, index: 1)
        encoder.setBytes(&uniformsStruct, length: MemoryLayout<ColorGradeUniforms>.size, index: 0)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (width + 15) / 16,
            height: (height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        // 2. 遮幅
        if config.aspectRatio != .imax {
            let letterboxRects = CinematicEngine.letterboxRects(
                viewSize: CGSize(width: width, height: height),
                aspectRatio: config.aspectRatio
            )

            guard let lbEncoder = cmdBuffer.makeComputeCommandEncoder() else { return pixelBuffer }
            var topH = Float(letterboxRects.top.height)
            var bottomH = Float(letterboxRects.bottom.height)

            lbEncoder.setComputePipelineState(letterboxPipeline)
            lbEncoder.setTexture(outTexture, index: 0)
            lbEncoder.setBytes(&topH, length: MemoryLayout<Float>.size, index: 0)
            lbEncoder.setBytes(&bottomH, length: MemoryLayout<Float>.size, index: 1)
            lbEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            lbEncoder.endEncoding()
        }

        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()

        // 纹理 → CVPixelBuffer
        return textureToPixelBuffer(outTexture)
    }

    // MARK: - 工具

    private func makeTextureCache() -> CVMetalTextureCache? {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        return cache
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer, cache: CVMetalTextureCache) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        return cvTexture.flatMap { CVMetalTextureGetTexture($0) }
    }

    private func makeEmptyTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: desc)
    }

    private func textureToPixelBuffer(_ texture: MTLTexture) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let width = texture.width, height = texture.height
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                           kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(CVPixelBufferGetBaseAddress(buffer)!,
                        bytesPerRow: bytesPerRow,
                        from: region,
                        mipmapLevel: 0)
        return buffer
    }

    // 给 Metal shader 的 uniforms 结构体（C 兼容）
    private struct ColorGradeUniforms {
        var colorMatrix: (Float, Float, Float, Float, Float, Float, Float, Float, Float)
        var brightnessOffset: Float
        var saturationScale: Float
        var contrastGamma: Float
        var filmGrain: Float
        var time: Float

        init(colorMatrix: [Float], brightnessOffset: Float, saturationScale: Float,
             contrastGamma: Float, filmGrain: Float, time: Float) {
            self.colorMatrix = (
                colorMatrix[0], colorMatrix[1], colorMatrix[2],
                colorMatrix[3], colorMatrix[4], colorMatrix[5],
                colorMatrix[6], colorMatrix[7], colorMatrix[8]
            )
            self.brightnessOffset = brightnessOffset
            self.saturationScale = saturationScale
            self.contrastGamma = contrastGamma
            self.filmGrain = filmGrain
            self.time = time
        }
    }
}
