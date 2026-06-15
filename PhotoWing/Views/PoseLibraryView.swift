import SwiftUI

/// 姿势参考库选择面板
struct PoseLibraryView: View {
    @Binding var isPresented: Bool
    @ObservedObject var orchestrator: GuidanceOrchestrator

    private let poses = ReferencePose.library

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ReferencePose.PoseCategory.allCases, id: \.self) { category in
                        categorySection(category)
                    }
                }
                .padding()
            }
            .navigationTitle("姿势参考库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { isPresented = false }
                }
            }
            .background(Color.black)
        }
        .preferredColorScheme(.dark)
    }

    private func categorySection(_ category: ReferencePose.PoseCategory) -> some View {
        let categoryPoses = poses.filter { $0.category == category }

        guard !categoryPoses.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(VStack(alignment: .leading, spacing: 8) {
            Text("\(category.icon) \(category.rawValue)")
                .font(.headline)
                .foregroundColor(.white)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(categoryPoses) { pose in
                    poseCard(pose)
                }
            }
        })
    }

    private func poseCard(_ pose: ReferencePose) -> some View {
        Button(action: {
            orchestrator.selectPose(pose)
            isPresented = false
        }) {
            VStack(spacing: 6) {
                // 简易线条人示意图
                poseIcon
                    .frame(width: 50, height: 70)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(pose.name)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(6)
            .background(
                orchestrator.selectedPose?.id == pose.id
                    ? Color.yellow.opacity(0.3)
                    : Color.white.opacity(0.05)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        orchestrator.selectedPose?.id == pose.id
                            ? Color.yellow.opacity(0.6)
                            : Color.clear,
                        lineWidth: 2
                    )
            )
        }
    }

    /// 简易线条人示意（纯 SwiftUI 路径）
    private var poseIcon: some View {
        Canvas { context, size in
            let cx = size.width / 2
            let headY = size.height * 0.15
            let bodyY = size.height * 0.45
            let hipY = size.height * 0.55

            // 头
            let headRect = CGRect(x: cx - 6, y: headY - 4, width: 12, height: 12)
            context.fill(Path(ellipseIn: headRect), with: .color(.white.opacity(0.8)))

            // 躯干
            var bodyPath = Path()
            bodyPath.move(to: CGPoint(x: cx, y: headY + 8))
            bodyPath.addLine(to: CGPoint(x: cx, y: hipY))
            context.stroke(bodyPath, with: .color(.white.opacity(0.6)), lineWidth: 2)

            // 双臂
            for side in [-1.0, 1.0] {
                let sx = cx + CGFloat(side) * 14
                var armPath = Path()
                armPath.move(to: CGPoint(x: cx, y: bodyY))
                armPath.addLine(to: CGPoint(x: sx, y: hipY))
                context.stroke(armPath, with: .color(.white.opacity(0.5)), lineWidth: 1.5)
            }

            // 双腿
            for side in [-1.0, 1.0] {
                let lx = cx + CGFloat(side) * 6
                var legPath = Path()
                legPath.move(to: CGPoint(x: cx, y: hipY))
                legPath.addLine(to: CGPoint(x: lx, y: size.height * 0.95))
                context.stroke(legPath, with: .color(.white.opacity(0.5)), lineWidth: 1.5)
            }
        }
    }
}
