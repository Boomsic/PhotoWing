import SwiftUI

/// 取景框叠加层：三分法网格 + 人物位置指示 + 方向箭头 + 骨骼线
struct GuidanceOverlay: View {
    let guidance: GuidanceResult
    let skeleton: BodySkeleton?
    let viewSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 三分法网格
                ruleOfThirdsGrid(size: geometry.size)

                // 人物骨骼线
                if let skeleton {
                    skeletonLines(skeleton, size: geometry.size)
                }

                // 人物重心位置指示
                if let pos = guidance.composition.currentPosition {
                    positionIndicator(
                        current: pos,
                        target: guidance.composition.targetPosition,
                        size: geometry.size
                    )
                }

                // 方向箭头
                if guidance.composition.score < 70,
                   let arrow = guidance.composition.directionArrow,
                   arrow != .none {
                    directionArrowOverlay(arrow: arrow, size: geometry.size)
                }
            }
        }
        .allowsHitTesting(false)  // 不拦截触摸事件
    }

    // MARK: - 三分法网格

    private func ruleOfThirdsGrid(size: CGSize) -> some View {
        Canvas { context, size in
            let lineColor = Color.white.opacity(0.25)
            let dotColor = Color.white.opacity(0.6)

            // 竖线
            for x in [size.width / 3, size.width * 2 / 3] {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(lineColor), lineWidth: 1)
            }

            // 横线
            for y in [size.height / 3, size.height * 2 / 3] {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 1)
            }

            // 交叉点标记
            for x in [size.width / 3, size.width * 2 / 3] {
                for y in [size.height / 3, size.height * 2 / 3] {
                    let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                }
            }
        }
    }

    // MARK: - 骨骼线

    private func skeletonLines(_ skeleton: BodySkeleton, size: CGSize) -> some View {
        Canvas { context, size in
            let jointColor = Color.green.opacity(0.7)
            let boneColor = Color.green.opacity(0.4)

            // 躯干连线
            let connections: [(BodySkeleton.JointName, BodySkeleton.JointName)] = [
                (.nose, .leftEye), (.leftEye, .leftEar),
                (.nose, .rightEye), (.rightEye, .rightEar),
                (.leftShoulder, .rightShoulder),
                (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
                (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
                (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
                (.leftHip, .rightHip),
                (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
                (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
                (.nose, .leftShoulder),      // 近似颈部
            ]

            for (a, b) in connections {
                guard let pa = skeleton.joint(a),
                      let pb = skeleton.joint(b) else { continue }

                let from = CGPoint(x: pa.x * size.width, y: pa.y * size.height)
                let to = CGPoint(x: pb.x * size.width, y: pb.y * size.height)

                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(boneColor), lineWidth: 2)
            }

            // 关节点
            for joint in skeleton.joints where joint.confidence > 0.3 {
                let pos = CGPoint(x: joint.position.x * size.width,
                                  y: joint.position.y * size.height)
                let rect = CGRect(x: pos.x - 3, y: pos.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: rect), with: .color(jointColor))
            }
        }
    }

    // MARK: - 位置指示器

    private func positionIndicator(current: CGPoint, target: CGPoint, size: CGSize) -> some View {
        ZStack {
            // 目标位置（半透明绿色圆）
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 24, height: 24)
                .position(x: target.x * size.width, y: target.y * size.height)

            // 当前位置（发光效果）
            Circle()
                .fill(guidance.composition.score >= 70 ? Color.green : Color.yellow)
                .frame(width: 12, height: 12)
                .shadow(color: (guidance.composition.score >= 70 ? Color.green : Color.yellow).opacity(0.8),
                        radius: 8)
                .position(x: current.x * size.width, y: current.y * size.height)
        }
    }

    // MARK: - 方向箭头

    private func directionArrowOverlay(arrow: CompositionGuidance.DirectionArrow,
                                        size: CGSize) -> some View {
        let arrowSize: CGFloat = 60
        let position: CGPoint = {
            switch arrow {
            case .left:  return CGPoint(x: size.width * 0.1, y: size.height * 0.5)
            case .right: return CGPoint(x: size.width * 0.9, y: size.height * 0.5)
            case .up:    return CGPoint(x: size.width * 0.5, y: size.height * 0.15)
            case .down:  return CGPoint(x: size.width * 0.5, y: size.height * 0.85)
            default:     return CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            }
        }()

        return Text(arrow.rawValue)
            .font(.system(size: arrowSize))
            .position(position)
            .opacity(0.8)
            // 脉冲动画
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                       value: arrow)
    }
}
