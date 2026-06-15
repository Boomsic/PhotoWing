import SwiftUI

/// 半透明参考姿势叠加层
struct PoseGhostView: View {
    let referencePose: ReferencePose
    let skeleton: BodySkeleton?
    let matchScore: Int
    let viewSize: CGSize

    var body: some View {
        Canvas { context, size in
            drawReferencePose(context: &context, size: size)
            drawMatchFeedback(context: &context, size: size)
        }
        .opacity(0.35)
        .allowsHitTesting(false)
    }

    // MARK: - 绘制参考姿势（关节 + 连线）

    private func drawReferencePose(context: inout GraphicsContext, size: CGSize) {
        guard skeleton != nil else { return }

        let color: Color = matchScore >= 75 ? .green : .yellow

        // 构建参考姿态的绝对位置
        // 使用当前人物的髋部中点和肩宽做缩放
        var positions: [BodySkeleton.JointName: CGPoint] = [:]

        for kp in referencePose.keypoints {
            // 相对坐标 → 绝对屏幕坐标（以画面中心偏下为髋部参考点）
            let cx = size.width * 0.5
            let cy = size.height * 0.55  // 髋部在画面 55% 处
            let scale = size.height * 0.35  // 缩放因子

            let x = cx + CGFloat(kp.relativeX) * scale
            let y = cy - CGFloat(kp.relativeY) * scale  // Y 轴翻转
            positions[kp.joint] = CGPoint(x: x, y: y)
        }

        // 连线（与 GuidanceOverlay 相同骨骼连接）
        let connections: [(BodySkeleton.JointName, BodySkeleton.JointName)] = [
            (.leftShoulder, .rightShoulder),
            (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.leftHip, .rightHip),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        ]

        for (a, b) in connections {
            guard let pa = positions[a], let pb = positions[b] else { continue }
            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            // 虚线效果：用 strokeStyle dash
            context.stroke(path,
                          with: .color(color.opacity(0.6)),
                          style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
        }

        // 关节点
        for (_, pos) in positions {
            let rect = CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.7)))
        }
    }

    // MARK: - 匹配反馈

    private func drawMatchFeedback(context: inout GraphicsContext, size: CGSize) {
        guard matchScore > 0 else { return }

        let text = "\(matchScore)%"
        let resolvedText = context.resolve(
            Text(text)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(matchScore >= 75 ? .green : .yellow)
        )

        let textSize = resolvedText.measure(in: size)
        let pos = CGPoint(x: size.width - textSize.width / 2 - 20,
                          y: size.height * 0.15)
        context.draw(resolvedText, at: pos)
    }
}
