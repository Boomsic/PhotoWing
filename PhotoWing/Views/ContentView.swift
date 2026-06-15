import SwiftUI
import AVFoundation

/// 主拍摄界面 — 集成自动控制 + 教学
struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var bodyTracker = BodyTracker()
    @StateObject private var orchestrator = GuidanceOrchestrator()
    @StateObject private var autoCamera = AutoCameraController()
    @StateObject private var voiceListener = VoiceCommandListener()
    private let cinematicFilter = CinematicFilter()

    @State private var showPoseLibrary = false
    @State private var showTutorial = false
    @State private var viewSize: CGSize = .zero
    @State private var backgroundBrightness: Double = 0.5
    @State private var isSetup = false
    @State private var showModePicker = false

    // 美学指令
    @State private var activeAesthetic: AestheticCommand?
    @State private var aestheticStrategy: AestheticPresetEngine.AestheticStrategy?
    @State private var activeIntent: AestheticIntent?
    @State private var mergedStrategy: IntentToParameterMapper.MergedStrategy?
    @State private var cinematicConfig = CinematicEngine.CinematicConfig()
    @State private var showCommandBar = true

    private let intentParser = AestheticIntentParser()
    private let intentMapper = IntentToParameterMapper()

    /// 是否第一次使用
    @AppStorage("hasCompletedTutorial") private var hasCompletedTutorial = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // ═══════════════════════════════
                // 1. 相机预览（全屏底层）
                // ═══════════════════════════════
                CameraPreview(session: cameraManager.session)
                    .ignoresSafeArea()

                // ═══════════════════════════════
                // 2. 指导叠加层（网格+骨骼+指示）
                // ═══════════════════════════════
                GuidanceOverlay(
                    guidance: orchestrator.result,
                    skeleton: bodyTracker.skeleton,
                    viewSize: geometry.size
                )

                // ═══════════════════════════════
                // 3. 姿势参考叠加
                // ═══════════════════════════════
                if orchestrator.isPoseModeActive,
                   let pose = orchestrator.selectedPose {
                    PoseGhostView(
                        referencePose: pose,
                        skeleton: bodyTracker.skeleton,
                        matchScore: orchestrator.result.pose.score,
                        viewSize: geometry.size
                    )
                }

                // ═══════════════════════════════
                // 4. 场景切换 + 自动操作提示条
                // ═══════════════════════════════
                VStack {
                    if !orchestrator.sceneJustChanged.isEmpty {
                        sceneChangeBanner
                    } else if !autoCamera.currentAction.isEmpty {
                        autoActionBanner
                    }
                    Spacer()
                }

                // ═══════════════════════════════
                // 5. 顶部状态栏
                // ═══════════════════════════════
                topStatusBar

                // ═══════════════════════════════
                // 5.5 美学指令快捷栏（居中悬浮）
                // ═══════════════════════════════
                if showCommandBar {
                    VStack {
                        Spacer()
                        AestheticCommandBar(
                            activeCommand: $activeAesthetic,
                            onSelect: { cmd in applyAesthetic(cmd) },
                            onDismiss: { clearAesthetic() }
                        )
                        .padding(.bottom, 160)
                    }
                }

                // ═══════════════════════════════
                // 6. 底部面板
                // ═══════════════════════════════
                VStack {
                    Spacer()
                    bottomPanel
                }

                // ═══════════════════════════════
                // 7. 模式选择器
                // ═══════════════════════════════
                if showModePicker {
                    modePickerOverlay
                }

                // ═══════════════════════════════
                // 8. 新手教学覆盖层
                // ═══════════════════════════════
                if showTutorial {
                    TutorialView(
                        isShowing: $showTutorial,
                        orchestrator: orchestrator,
                        bodyTracker: bodyTracker
                    )
                    .transition(.opacity)
                }
            }
            .onAppear {
                viewSize = geometry.size
                setup()
            }
            .onChange(of: geometry.size) { newSize in
                viewSize = newSize
            }
            .onChange(of: voiceListener.matchedCommand) { cmd in
                if let cmd { applyAesthetic(cmd) }
            }
        }
        .sheet(isPresented: $showPoseLibrary) {
            PoseLibraryView(
                isPresented: $showPoseLibrary,
                orchestrator: orchestrator
            )
        }
        .alert("相机权限", isPresented: Binding(
            get: { cameraManager.errorMessage != nil },
            set: { if !$0 { cameraManager.errorMessage = nil } }
        )) {
            Button("去设置") { openSettings() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(cameraManager.errorMessage ?? "")
        }
    }

    // MARK: - 场景切换横幅

    private var sceneChangeBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption)
            Text(orchestrator.sceneJustChanged)
                .font(.caption.weight(.medium))
                .lineLimit(2)
        }
        .foregroundColor(.black)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.cyan.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4)
        .padding(.horizontal, 20)
        .padding(.top, 100)
        .animation(.easeInOut(duration: 0.3), value: orchestrator.sceneJustChanged)
    }

    // MARK: - 自动操作横幅

    private var autoActionBanner: some View {
        VStack {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.arrow.triangle.2.circlepath")
                    .font(.caption)
                Text(autoCamera.currentAction)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.9))
            .clipShape(Capsule())
            .shadow(radius: 4)
            .padding(.top, 100)

            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: autoCamera.currentAction)
    }

    // MARK: - 顶部状态栏

    private var topStatusBar: some View {
        VStack {
            HStack {
                // 左侧：标题 + 场景
                VStack(alignment: .leading, spacing: 2) {
                    Text("📷 拍照助手")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    HStack(spacing: 4) {
                        Text(orchestrator.sceneDescription)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                        Text(bodyTracker.trackingMethod.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                Spacer()

                // 右侧：模式标签 + 语音
                HStack(spacing: 8) {
                    // 语音按钮
                    Button(action: {
                        if voiceListener.isListening {
                            voiceListener.stopListening()
                            if let cmd = voiceListener.matchedCommand {
                                applyAesthetic(cmd)
                            }
                        } else {
                            voiceListener.requestPermission()
                            voiceListener.startListening()
                        }
                    }) {
                        Image(systemName: voiceListener.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 12))
                            .foregroundColor(voiceListener.isListening ? .red : .white.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    // 模式标签
                    Button(action: { showModePicker.toggle() }) {
                        HStack(spacing: 4) {
                            Text(autoCamera.mode.rawValue)
                                .font(.caption2)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.6), Color.black.opacity(0.01)],
                    startPoint: .top, endPoint: .bottom
                )
            )

            Spacer()
        }
    }

    // MARK: - 底部面板（整合自动控制器状态）

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // 综合评分大数字
            if orchestrator.result.overallScore > 0 {
                HStack {
                    Spacer()
                    Text("\(orchestrator.result.overallScore)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(orchestrator.result.isReadyToShoot ? .green : .yellow)
                    Text("分")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
                .padding(.bottom, 6)
            }

            // 提示
            if let hint = orchestrator.result.prioritizedHints.first {
                Text(hint)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 8)
            }

            // 评分条
            scoreBar
                .padding(.bottom, 8)

            // 底部按钮行
            bottomButtons
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.01), Color.black.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private var scoreBar: some View {
        HStack(spacing: 10) {
            ScoreChip(label: "构图", score: orchestrator.result.composition.score,
                      icon: "rectangle.split.3x3")
            ScoreChip(label: "曝光", score: orchestrator.result.exposure.score,
                      icon: autoCamera.isAutoExposureEnabled ? "sun.max.fill" : "sun.max")
            ScoreChip(label: "姿势", score: orchestrator.result.pose.score,
                      icon: orchestrator.isPoseModeActive ? "figure.stand.line.dotted.figure.stand" : "figure.stand")
            ScoreChip(label: "聚焦", score: orchestrator.result.focus.score,
                      icon: autoCamera.isAutoFocusEnabled ? "scope" : "eye")
            Spacer()
        }
    }

    private var bottomButtons: some View {
        HStack(spacing: 20) {
            // 姿势库
            Button(action: { showPoseLibrary = true }) {
                VStack(spacing: 2) {
                    Image(systemName: "figure.2.arms.open").font(.title2)
                    Text("姿势库").font(.caption2)
                }.foregroundColor(.white)
            }

            Spacer()

            // 姿势参考开关
            Button(action: { orchestrator.togglePoseMode() }) {
                VStack(spacing: 2) {
                    Image(systemName: orchestrator.isPoseModeActive
                          ? "figure.stand.line.dotted.figure.stand"
                          : "figure.stand")
                        .font(.title2)
                    Text(orchestrator.isPoseModeActive ? "关闭" : "姿势").font(.caption2)
                }
                .foregroundColor(orchestrator.isPoseModeActive ? .yellow : .white)
            }

            Spacer()

            // 教程按钮
            Button(action: { showTutorial = true }) {
                VStack(spacing: 2) {
                    Image(systemName: "questionmark.circle").font(.title2)
                    Text("教学").font(.caption2)
                }.foregroundColor(.white)
            }

            Spacer()

            // 快门
            Button(action: takePhoto) {
                ZStack {
                    Circle()
                        .stroke(
                            orchestrator.result.isReadyToShoot ? Color.green : Color.white,
                            lineWidth: 3
                        )
                        .frame(width: 64, height: 64)
                    Circle()
                        .fill(orchestrator.result.isReadyToShoot ? Color.green : Color.white)
                        .frame(width: 50, height: 50)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 模式选择器

    private var modePickerOverlay: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture { showModePicker = false }
            .overlay(
                VStack(spacing: 0) {
                    Text("选择操作模式")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 16)

                    ForEach(AutoCameraController.CameraMode.allCases, id: \.self) { mode in
                        Button(action: {
                            autoCamera.setMode(mode)
                            showModePicker = false
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.rawValue)
                                        .font(.body.weight(.medium))
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if autoCamera.mode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.yellow)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }
                    }

                    Button("取消") { showModePicker = false }
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.vertical, 12)
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 40)
            )
    }

    // MARK: - 初始化

    private func setup() {
        guard !isSetup else { return }
        isSetup = true

        Task {
            await cameraManager.requestAndSetup()

            // 绑定自动控制器到相机
            autoCamera.bind(to: cameraManager)

            // 帧回调
            cameraManager.onFrameCaptured = { pixelBuffer, size in
                // 1. 人体追踪
                bodyTracker.processFrame(pixelBuffer, size: size)

                // 2. 背景亮度
                let bgBrightness = estimateBackgroundBrightness(from: pixelBuffer)
                DispatchQueue.main.async {
                    self.backgroundBrightness = bgBrightness
                }

                // 3. 自动曝光 & 对焦
                DispatchQueue.main.async {
                    autoCamera.autoAdjust(
                        faceBrightness: cameraManager.faceBrightness,
                        facePosition: bodyTracker.skeleton?.headPosition,
                        skeleton: bodyTracker.skeleton
                    )
                }

                // 4. 汇总指导（含场景分析）
                DispatchQueue.main.async {
                    orchestrator.update(
                        skeleton: bodyTracker.skeleton,
                        faceBrightness: cameraManager.faceBrightness,
                        backgroundBrightness: backgroundBrightness,
                        isFocusLocked: cameraManager.isFocusLocked,
                        pixelBuffer: pixelBuffer,
                        viewSize: viewSize,
                        depthData: nil  // TODO: 接入 AVCaptureDepthDataOutput
                    )

                    // 5. 美学意图覆盖（语义向量→参数融合）
                    if let strategy = mergedStrategy {
                        let override = SceneAnalyzer.SceneStrategy(
                            faceBrightnessTarget: strategy.faceBrightnessTarget,
                            evAdjustSpeed: strategy.evAdjustSpeed,
                            maxEV: strategy.evBias > 0 ? 1.0 : 1.0,
                            minEV: strategy.evBias < 0 ? -1.0 : -1.0,
                            focusSensitivity: strategy.targetDepthOfField == .shallow ? 0.03 : 0.06,
                            idealBodyRatio: strategy.idealBodyRatio,
                            headroomRatio: strategy.headroomRatio,
                            hint: strategy.quickTip
                        )
                        autoCamera.sceneStrategy = override
                        autoCamera.setExposureBiasFromAesthetic(Float(strategy.evBias))
                    } else {
                        autoCamera.sceneStrategy = orchestrator.sceneStrategy
                    }

                    // 6. 电影滤镜处理
                    if cinematicConfig.isActive, let filter = cinematicFilter {
                        _ = filter.apply(to: pixelBuffer, config: cinematicConfig, viewSize: viewSize)
                    }
                }
            }

            cameraManager.start()
            bodyTracker.start()

            // 首次使用 → 弹出教学
            if !hasCompletedTutorial {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showTutorial = true
                }
            }
        }
    }

    // MARK: - 拍照

    private func takePhoto() {
        let delegate = PhotoCaptureDelegate()
        cameraManager.capturePhoto(delegate: delegate)

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    // MARK: - 美学指令（升级版：任意文本→语义向量→参数融合）

    /// 从按钮或语音触发
    private func applyAesthetic(_ cmd: AestheticCommand) {
        activeAesthetic = cmd
        applyFromText(cmd.rawValue)
    }

    /// 核心：任意自然语言 → 全参数
    private func applyFromText(_ text: String) {
        // 1. 解析 → 10维语义向量
        let intent = intentParser.parseFull(text)
        activeIntent = intent

        // 2. 与当前场景参数融合
        let sceneParams = AdaptiveParameterEngine().computeParameters(for: orchestrator.featureVector)
        mergedStrategy = intentMapper.merge(sceneParams: sceneParams, intent: intent)

        // 3. 电影配置
        cinematicConfig = CinematicEngine.CinematicConfig()
        cinematicConfig.isActive = mergedStrategy?.cinematicAspectActive ?? false
        cinematicConfig.aspectRatio = mergedStrategy?.cinematicAspectRatio ?? .widescreen185
        cinematicConfig.colorGrade = mergedStrategy?.colorGrade ?? .none
        cinematicConfig.filmGrain = mergedStrategy?.filmGrain ?? 0

        // 4. 显示引导
        let tip = mergedStrategy?.quickTip ?? ""
        let guides = (mergedStrategy?.photographerGuide ?? []).joined(separator: " | ")
        orchestrator.sceneJustChanged = "🎬 \(tip)"
        if !guides.isEmpty {
            autoCamera.currentAction = guides
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.orchestrator.sceneJustChanged = ""
        }
    }

    private func clearAesthetic() {
        activeAesthetic = nil
        activeIntent = nil
        mergedStrategy = nil
        cinematicConfig.isActive = false
    }

    /// 语音指令
    private func handleVoiceCommand(_ text: String) {
        applyFromText(text)
    }

    // MARK: - 辅助

    private func estimateBackgroundBrightness(from buffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return 0.5 }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        var total: Double = 0
        var count: Int = 0
        let margin = 40

        for y in 0..<min(40, height) {
            for x in stride(from: 0, to: width, by: 4) {
                let idx = y * bytesPerRow + x * 4
                if idx + 2 < bytesPerRow * height {
                    let luminance = 0.299 * Double(ptr[idx + 2]) +
                                    0.587 * Double(ptr[idx + 1]) +
                                    0.114 * Double(ptr[idx])
                    total += luminance
                    count += 1
                }
            }
        }
        _ = margin
        return count > 0 ? total / Double(count) / 255.0 : 0.5
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - 照片捕获代理

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let imageData = photo.fileDataRepresentation() else { return }
        UIImageWriteToSavedPhotosAlbum(
            UIImage(data: imageData) ?? UIImage(),
            nil, nil, nil
        )
    }
}
