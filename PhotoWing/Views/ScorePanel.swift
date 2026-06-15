import SwiftUI

/// 底部评分和提示面板
struct ScorePanel: View {
    let guidance: GuidanceResult
    let onShutter: () -> Void
    let onPoseLibrary: () -> Void
    let onTogglePose: () -> Void
    let isPoseActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 主提示（大字）
            if let hint = guidance.prioritizedHints.first {
                hintBanner(hint)
            }

            // 评分条
            scoreBar

            // 底部按钮
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

    // MARK: - 提示横幅

    private func hintBanner(_ hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: guidance.isReadyToShoot ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundColor(guidance.isReadyToShoot ? .green : .yellow)
            Text(hint)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 8)
    }

    // MARK: - 评分条

    private var scoreBar: some View {
        HStack(spacing: 12) {
            ScoreChip(label: "构图", score: guidance.composition.score,
                      icon: "rectangle.split.3x3")
            ScoreChip(label: "曝光", score: guidance.exposure.score,
                      icon: "sun.max")
            ScoreChip(label: "姿势", score: guidance.pose.score,
                      icon: "figure.stand")
            ScoreChip(label: "聚焦", score: guidance.focus.score,
                      icon: "scope")

            Spacer()

            Text("综合 \(guidance.overallScore)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(guidance.isReadyToShoot ? .green : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }

    // MARK: - 底部按钮

    private var bottomButtons: some View {
        HStack(spacing: 20) {
            // 姿势库
            Button(action: onPoseLibrary) {
                VStack(spacing: 2) {
                    Image(systemName: "figure.2.arms.open")
                        .font(.title2)
                    Text("姿势库")
                        .font(.caption2)
                }
                .foregroundColor(.white)
            }

            Spacer()

            // 姿势模式切换
            Button(action: onTogglePose) {
                VStack(spacing: 2) {
                    Image(systemName: isPoseActive ? "figure.stand.line.dotted.figure.stand" : "figure.stand")
                        .font(.title2)
                    Text(isPoseActive ? "关闭参考" : "姿势参考")
                        .font(.caption2)
                }
                .foregroundColor(isPoseActive ? .yellow : .white)
            }

            Spacer()

            // 快门按钮
            Button(action: onShutter) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 64, height: 64)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 50, height: 50)
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - 单项评分条

struct ScoreChip: View {
    let label: String
    let score: Int
    let icon: String

    private var color: Color {
        score >= 70 ? .green : (score >= 40 ? .yellow : .red)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text("\(score)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.2))
        .clipShape(Capsule())
    }
}
