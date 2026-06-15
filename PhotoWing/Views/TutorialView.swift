import SwiftUI

/// 新手教学：三步学会拍照
struct TutorialView: View {
    @Binding var isShowing: Bool
    @ObservedObject var orchestrator: GuidanceOrchestrator
    @ObservedObject var bodyTracker: BodyTracker

    @State private var currentStep: TutorialStep = .welcome
    @State private var stepProgress: Double = 0

    enum TutorialStep: Int, CaseIterable {
        case welcome = 0
        case findPerson
        case followGuide
        case readyToShoot
        case done

        var title: String {
            switch self {
            case .welcome:     return "欢迎使用拍照助手"
            case .findPerson:  return "第一步：对准人物"
            case .followGuide: return "第二步：跟随指引"
            case .readyToShoot: return "第三步：按下快门"
            case .done:        return "你学会了！"
            }
        }

        var instruction: String {
            switch self {
            case .welcome:
                return "我是你的 AI 摄影教练\n三步教你拍出让女朋友满意的照片"
            case .findPerson:
                return "把手机对准她\n让整个人出现在画面中"
            case .followGuide:
                return "看到屏幕上的箭头了吗？\n跟着箭头调整手机位置"
            case .readyToShoot:
                return "当顶部评分变绿\n大胆按下快门！"
            case .done:
                return "就这么简单 ✨\n每次拍照都这样用"
            }
        }

        var icon: String {
            switch self {
            case .welcome:     return "camera.viewfinder"
            case .findPerson:  return "person.fill.viewfinder"
            case .followGuide: return "arrow.up.and.down.and.arrow.left.and.right"
            case .readyToShoot: return "button.programmable"
            case .done:        return "hand.thumbsup.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    // 防止误触穿透
                }

            VStack(spacing: 24) {
                Spacer()

                // 图标
                Image(systemName: currentStep.icon)
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
                    .padding(.bottom, 8)

                // 标题
                Text(currentStep.title)
                    .font(.title2.bold())
                    .foregroundColor(.white)

                // 说明
                Text(currentStep.instruction)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 32)

                // 实时状态指示
                if currentStep == .findPerson {
                    statusIndicator(
                        detected: bodyTracker.skeleton != nil,
                        label: bodyTracker.skeleton != nil ? "✅ 已检测到人物" : "👤 等待检测人物..."
                    )
                } else if currentStep == .followGuide {
                    statusIndicator(
                        detected: orchestrator.result.composition.score >= 70,
                        label: orchestrator.result.composition.score >= 70
                            ? "✅ 构图到位！(\(orchestrator.result.composition.score)分)"
                            : "🎯 跟随箭头调整... (\(orchestrator.result.composition.score)分)"
                    )
                } else if currentStep == .readyToShoot {
                    statusIndicator(
                        detected: orchestrator.result.isReadyToShoot,
                        label: orchestrator.result.isReadyToShoot
                            ? "✅ 完美！按快门！"
                            : "⏳ 等待参数自动优化..."
                    )
                }

                // 进度指示器
                HStack(spacing: 8) {
                    ForEach(TutorialStep.allCases.dropFirst().dropLast(), id: \.rawValue) { step in
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.yellow : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.vertical, 8)

                // 按钮
                VStack(spacing: 12) {
                    Button(action: advanceStep) {
                        HStack(spacing: 8) {
                            Text(buttonLabel)
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            canAdvance ? Color.yellow : Color.white.opacity(0.2)
                        )
                        .foregroundColor(canAdvance ? .black : .white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canAdvance)
                    .padding(.horizontal, 32)

                    if currentStep != .welcome && currentStep != .done {
                        Button("跳过教学，直接使用") {
                            isShowing = false
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    }
                }

                Spacer()
            }
        }
        .onChange(of: bodyTracker.skeleton?.confidence ?? 0) { _ in
            checkAutoAdvance()
        }
        .onChange(of: orchestrator.result.composition.score) { _ in
            checkAutoAdvance()
        }
    }

    // MARK: - 状态指示器

    private func statusIndicator(detected: Bool, label: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(detected ? Color.green : Color.white.opacity(0.3))
                .frame(width: 10, height: 10)
            Text(label)
                .font(.subheadline)
                .foregroundColor(detected ? .green : .white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 自动推进

    private var canAdvance: Bool {
        switch currentStep {
        case .welcome: return true
        case .findPerson: return bodyTracker.skeleton != nil
        case .followGuide: return orchestrator.result.composition.score >= 65
        case .readyToShoot: return orchestrator.result.isReadyToShoot
        case .done: return true
        }
    }

    private var buttonLabel: String {
        switch currentStep {
        case .welcome:     return "开始学习"
        case .findPerson:  return bodyTracker.skeleton != nil ? "下一步" : "等待检测..."
        case .followGuide: return orchestrator.result.composition.score >= 65 ? "下一步" : "继续调整..."
        case .readyToShoot: return orchestrator.result.isReadyToShoot ? "完成教学" : "等待就绪..."
        case .done:        return "开始拍照"
        }
    }

    private func checkAutoAdvance() {
        // 当条件满足时自动闪烁提示，但需要用户手动点按钮（防止跳跃）
        // 如果条件极好（比如 all green），可以自动推进
        if currentStep == .findPerson,
           bodyTracker.skeleton?.confidence ?? 0 > 0.8 {
            // 人体检测非常稳定，自动推进
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.currentStep == .findPerson {
                    self.advanceStep()
                }
            }
        }
    }

    private func advanceStep() {
        guard canAdvance else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            if let next = TutorialStep(rawValue: currentStep.rawValue + 1) {
                currentStep = next
                if next == .done {
                    // 完成教学
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        isShowing = false
                    }
                }
            } else {
                isShowing = false
            }
        }
    }
}
