import Foundation
import CoreGraphics

/// 标准化的身体骨骼数据（统一 ARKit 和 Vision 输出）
struct BodySkeleton {
    /// 17 个关节点，采用 Vision 的索引顺序
    var joints: [JointPoint]
    /// 检测置信度 0-1
    var confidence: Float
    /// 时间戳
    var timestamp: Date

    /// 单关节
    struct JointPoint {
        let name: JointName
        /// 归一化坐标 (0-1)，相对于相机画面
        var position: CGPoint
        /// 该关节的置信度 0-1
        var confidence: Float
    }

    enum JointName: Int, CaseIterable {
        case nose = 0
        case leftEye, rightEye
        case leftEar, rightEar
        case leftShoulder, rightShoulder
        case leftElbow, rightElbow
        case leftWrist, rightWrist
        case leftHip, rightHip
        case leftKnee, rightKnee
        case leftAnkle, rightAnkle
    }

    // MARK: - 便捷访问

    var headPosition: CGPoint? { joint(.nose) }
    var leftShoulderPos: CGPoint? { joint(.leftShoulder) }
    var rightShoulderPos: CGPoint? { joint(.rightShoulder) }
    var leftHipPos: CGPoint? { joint(.leftHip) }
    var rightHipPos: CGPoint? { joint(.rightHip) }
    var leftHandPos: CGPoint? { joint(.leftWrist) }
    var rightHandPos: CGPoint? { joint(.rightWrist) }

    /// 人物包围盒（归一化坐标）
    var boundingBox: CGRect? {
        let positions = joints.compactMap { $0.confidence > 0.3 ? $0.position : nil }
        guard !positions.isEmpty else { return nil }
        let xs = positions.map(\.x), ys = positions.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 人体重心（髋部中点）
    var centerOfMass: CGPoint? {
        guard let lh = leftHipPos, let rh = rightHipPos else { return nil }
        return CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
    }

    /// 肩部中点
    var shoulderCenter: CGPoint? {
        guard let ls = leftShoulderPos, let rs = rightShoulderPos else { return nil }
        return CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
    }

    func joint(_ name: JointName) -> CGPoint? {
        guard name.rawValue < joints.count,
              joints[name.rawValue].confidence > 0.3 else { return nil }
        return joints[name.rawValue].position
    }

    /// 所有有效关节的坐标数组
    var validJointPositions: [CGPoint] {
        joints.filter { $0.confidence > 0.3 }.map(\.position)
    }
}
