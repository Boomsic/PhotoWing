import AVFoundation
import Combine

/// 自动相机控制器：自动曝光 + 自动对焦 + 自动白平衡
/// 用户无需手动调任何参数，App 全程自动优化
@MainActor
final class AutoCameraController: ObservableObject {

    // MARK: - 发布状态

    @Published var isAutoExposureEnabled = true
    @Published var isAutoFocusEnabled = true
    @Published var isAutoWhiteBalanceEnabled = true
    @Published var currentAction: String = ""       // 当前正在做什么
    @Published var exposureTarget: Float = 0.0      // 当前 EV 目标
    @Published var lastAdjustment: Date = .now

    /// 操作模式
    enum CameraMode: String, CaseIterable {
        case fullAuto = "🤖 全自动"
        case semiAuto = "🎯 半自动"
        case manual = "👋 手动"

        var description: String {
            switch self {
            case .fullAuto: return "曝光·对焦·白平衡全部自动"
            case .semiAuto: return "自动优化参数，你控制构图"
            case .manual: return "所有参数手动调节"
            }
        }
    }

    @Published var mode: CameraMode = .fullAuto

    // MARK: - 场景自适应参数（动态更新，不再写死）

    /// 当前场景策略（由 SceneAnalyzer 每帧更新）
    var sceneStrategy: SceneAnalyzer.SceneStrategy = SceneAnalyzer.SceneType.urbanDefault.strategy

    /// 调整间隔（防抖）
    private let adjustInterval: TimeInterval = 0.3

    private var cameraManager: CameraManager?

    func bind(to camera: CameraManager) {
        self.cameraManager = camera
    }

    /// 每帧调用，自动决定是否需要调整
    func autoAdjust(faceBrightness: Double,
                    facePosition: CGPoint?,
                    skeleton: BodySkeleton?) {

        guard mode != .manual else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAdjustment) >= adjustInterval else { return }

        // 1. 自动曝光（使用场景自适应参数）
        if isAutoExposureEnabled {
            autoAdjustExposure(faceBrightness: faceBrightness)
        }

        // 2. 自动对焦（使用场景自适应敏感度）
        if isAutoFocusEnabled, let facePos = facePosition ?? skeleton?.headPosition {
            autoAdjustFocus(to: facePos)
        }

        lastAdjustment = now
    }

    // MARK: - 自动曝光逻辑（场景自适应）

    private func autoAdjustExposure(faceBrightness: Double) {
        guard let camera = cameraManager else { return }

        let targetRange = sceneStrategy.faceBrightnessTarget
        let evSpeed = Float(sceneStrategy.evAdjustSpeed)

        // 在人脸亮度理想区间内 → 不调
        if targetRange.contains(faceBrightness) {
            currentAction = ""
            return
        }

        // 需要提亮
        if faceBrightness < targetRange.lowerBound {
            let needed = Float((targetRange.lowerBound - faceBrightness) * 2.5)
            let target = min(Float(sceneStrategy.maxEV), camera.currentEV + min(evSpeed, needed))

            if camera.currentEV >= Float(sceneStrategy.maxEV) - 0.05 {
                currentAction = sceneStrategy.hint.isEmpty
                    ? "🔆 太暗了，试试开闪光灯"
                    : sceneStrategy.hint
                return
            }

            camera.setExposureBias(target)
            exposureTarget = target
            currentAction = "☀️ 自动提亮中..."

        // 需要压暗
        } else if faceBrightness > targetRange.upperBound {
            let needed = Float((faceBrightness - targetRange.upperBound) * 2.5)
            let target = max(Float(sceneStrategy.minEV), camera.currentEV - min(evSpeed, needed))

            if camera.currentEV <= Float(sceneStrategy.minEV) + 0.05 {
                currentAction = "🌑 太亮了，换个方向拍"
                return
            }

            camera.setExposureBias(target)
            exposureTarget = target
            currentAction = "🌥️ 自动压暗中..."
        }
    }

    // MARK: - 自动对焦逻辑

    private var lastFocusPoint: CGPoint?

    private func autoAdjustFocus(to facePoint: CGPoint) {
        guard let camera = cameraManager else { return }

        // 人脸没怎么移动 → 不重新对焦（省电+避免频繁呼吸效应）
        // 使用场景自适应敏感度（暗光更频繁对焦，明亮场景可以放松）
        if let last = lastFocusPoint {
            let distance = hypot(facePoint.x - last.x, facePoint.y - last.y)
            if distance < sceneStrategy.focusSensitivity { return }
        }

        camera.lockFocus(at: facePoint)
        lastFocusPoint = facePoint

        if currentAction.isEmpty {
            currentAction = "🔍 已锁焦到人脸"
            // 2秒后清除提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if self?.currentAction == "🔍 已锁焦到人脸" {
                    self?.currentAction = ""
                }
            }
        }
    }

    // MARK: - 模式切换

    func setMode(_ mode: CameraMode) {
        self.mode = mode

        switch mode {
        case .fullAuto:
            isAutoExposureEnabled = true
            isAutoFocusEnabled = true
            isAutoWhiteBalanceEnabled = true
            currentAction = "🤖 全自动模式已开启"
        case .semiAuto:
            isAutoExposureEnabled = true
            isAutoFocusEnabled = true
            isAutoWhiteBalanceEnabled = false
            currentAction = "🎯 半自动：曝光对焦自动，构图你来"
        case .manual:
            isAutoExposureEnabled = false
            isAutoFocusEnabled = false
            isAutoWhiteBalanceEnabled = false
            currentAction = "👋 手动模式：全部自己调"
        }

        // 3 秒后清除
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.currentAction == self?.mode.description || self?.currentAction.hasPrefix(self?.mode.rawValue ?? "") ?? false {
                self?.currentAction = ""
            }
        }
    }

    /// 从美学指令快速设置曝光（一次性，不参与连续自调）
    func setExposureBiasFromAesthetic(_ bias: Float) {
        cameraManager?.setExposureBias(bias)
        currentAction = "🎬 曝光已预设"
    }
}
