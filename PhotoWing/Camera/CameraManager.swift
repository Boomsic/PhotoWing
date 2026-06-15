import AVFoundation
import Combine
import UIKit

/// 相机管理器：封装 AVCaptureSession，提供实时画面流
@MainActor
final class CameraManager: NSObject, ObservableObject {

    // MARK: - 发布状态

    @Published var isRunning = false
    @Published var currentEV: Float = 0.0           // 当前曝光补偿
    @Published var faceBrightness: Double = 0.5
    @Published var isFocusLocked = false
    @Published var errorMessage: String?

    /// 每帧回调（归一化坐标系，竖屏原点左上）
    var onFrameCaptured: ((CVPixelBuffer, CGSize) -> Void)?

    // MARK: - 内部组件

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    /// 用于 UI 预览的 preview layer
    var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - 初始配置

    /// 请求权限并设置相机
    func requestAndSetup() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        switch status {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            granted = false
        }

        guard granted else {
            errorMessage = "相机权限未授权，请在设置中开启"
            return
        }
        setupSession()
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // 优先用双摄/广角
            guard let device = self.bestCamera() else {
                DispatchQueue.main.async { self.errorMessage = "未找到可用相机" }
                self.session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw CameraError.inputRejected }
                self.session.addInput(input)
            } catch {
                DispatchQueue.main.async { self.errorMessage = "相机初始化失败: \(error.localizedDescription)" }
                self.session.commitConfiguration()
                return
            }

            // 视频输出（实时帧）
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            guard self.session.canAddOutput(self.videoOutput) else {
                DispatchQueue.main.async { self.errorMessage = "无法添加视频输出" }
                self.session.commitConfiguration()
                return
            }
            self.session.addOutput(self.videoOutput)

            // 照片输出
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.session.commitConfiguration()

            // 预览图层
            let layer = AVCaptureVideoPreviewLayer(session: self.session)
            layer.videoGravity = .resizeAspectFill
            self.previewLayer = layer

            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    /// 选最好的后置摄像头
    private func bestCamera() -> AVCaptureDevice? {
        if let dual = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            return dual
        }
        if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return wide
        }
        return AVCaptureDevice.default(for: .video)
    }

    // MARK: - 控制

    func start() {
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    /// 锁定焦点到指定归一化坐标
    func lockFocus(at normalizedPoint: CGPoint) {
        sessionQueue.async {
            guard let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = normalizedPoint
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = normalizedPoint
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.isFocusLocked = true }
            } catch {}
        }
    }

    /// 设置曝光补偿 (-1 到 1)
    func setExposureBias(_ bias: Float) {
        sessionQueue.async {
            guard let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(-1, min(1, bias))
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.currentEV = clamped }
            } catch {}
        }
    }

    /// 拍照
    func capturePhoto(delegate: AVCapturePhotoCaptureDelegate) {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: delegate)
    }

    enum CameraError: Error { case inputRejected }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let size = CGSize(width: width, height: height)

        // 人脸区域亮度采样
        let brightness = estimateFaceBrightness(from: pixelBuffer, size: size)

        DispatchQueue.main.async { [weak self] in
            self?.faceBrightness = brightness
        }

        onFrameCaptured?(pixelBuffer, size)
    }

    /// 快速亮度估算：取画面中心偏上区域（人脸通常位置）
    private func estimateFaceBrightness(from buffer: CVPixelBuffer, size: CGSize) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return 0.5 }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let bufferPtr = baseAddress.assumingMemoryBound(to: UInt8.self)

        // 采样中心偏上 20% 区域（人脸上半部通常在此）
        let roiX = Int(Double(size.width) * 0.3)
        let roiY = Int(Double(size.height) * 0.1)
        let roiW = Int(Double(size.width) * 0.4)
        let roiH = Int(Double(size.height) * 0.3)
        let step = 4  // 降采样

        var total: Double = 0
        var count: Int = 0

        for y in stride(from: roiY, to: roiY + roiH, by: step) {
            for x in stride(from: roiX, to: roiX + roiW, by: step) {
                let offset = y * bytesPerRow + x * 4
                // BT.601 亮度公式
                let b = Double(bufferPtr[offset])
                let g = Double(bufferPtr[offset + 1])
                let r = Double(bufferPtr[offset + 2])
                let luminance = 0.299 * r + 0.587 * g + 0.114 * b
                total += luminance
                count += 1
            }
        }

        return count > 0 ? total / Double(count) / 255.0 : 0.5
    }
}
