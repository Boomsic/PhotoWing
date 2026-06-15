import Foundation

/// 预设参考姿势
struct ReferencePose: Identifiable, Codable {
    let id: String
    let name: String
    let category: PoseCategory
    let description: String
    /// 关键关节的相对位置（以髋部中点为原点，归一化到身高）
    let keypoints: [JointKeypoint]

    struct JointKeypoint: Codable {
        let joint: BodySkeleton.JointName
        /// 相对位置 (x 相对于肩宽, y 相对于身高，髋部中点为原点)
        let relativeX: Double
        let relativeY: Double
    }

    enum PoseCategory: String, Codable, CaseIterable {
        case standing = "站姿"
        case sitting = "坐姿"
        case dynamic = "动态"
        case fresh = "小清新"

        var icon: String {
            switch self {
            case .standing: return "🧍"
            case .sitting: return "🪑"
            case .dynamic: return "🏃"
            case .fresh: return "🌸"
            }
        }
    }
}

// MARK: - 预设姿势库

extension ReferencePose {
    static let library: [ReferencePose] = [
        // === 站姿 ===
        ReferencePose(
            id: "hand_in_pocket",
            name: "单手插兜",
            category: .standing,
            description: "身体微侧，一只手自然插兜，另一只自然下垂",
            keypoints: [
                .init(joint: .leftElbow, relativeX: -0.45, relativeY: -0.12),
                .init(joint: .leftWrist, relativeX: -0.35, relativeY: 0.08),
                .init(joint: .rightElbow, relativeX: 0.50, relativeY: -0.05),
                .init(joint: .rightWrist, relativeX: 0.42, relativeY: 0.12),
            ]
        ),
        ReferencePose(
            id: "cross_arms",
            name: "抱臂站立",
            category: .standing,
            description: "双手交叉抱在胸前，重心放一条腿",
            keypoints: [
                .init(joint: .leftElbow, relativeX: -0.15, relativeY: -0.10),
                .init(joint: .leftWrist, relativeX: 0.05, relativeY: -0.08),
                .init(joint: .rightElbow, relativeX: 0.15, relativeY: -0.10),
                .init(joint: .rightWrist, relativeX: -0.05, relativeY: -0.08),
            ]
        ),
        ReferencePose(
            id: "hair_touch",
            name: "一手撩发",
            category: .standing,
            description: "一只手抬起轻触头发，另一只手自然下垂",
            keypoints: [
                .init(joint: .leftElbow, relativeX: -0.30, relativeY: -0.35),
                .init(joint: .leftWrist, relativeX: -0.15, relativeY: -0.52),
                .init(joint: .rightElbow, relativeX: 0.35, relativeY: -0.05),
                .init(joint: .rightWrist, relativeX: 0.40, relativeY: 0.15),
            ]
        ),
        ReferencePose(
            id: "look_back",
            name: "侧身回头",
            category: .standing,
            description: "身体侧对镜头，回头看向相机",
            keypoints: [
                .init(joint: .nose, relativeX: 0.08, relativeY: -0.55),
                .init(joint: .leftShoulder, relativeX: -0.15, relativeY: -0.28),
                .init(joint: .rightShoulder, relativeX: -0.05, relativeY: -0.32),
            ]
        ),
        ReferencePose(
            id: "one_leg_up",
            name: "单腿微曲",
            category: .standing,
            description: "重心放一条腿，另一条腿膝盖微弯脚尖点地",
            keypoints: [
                .init(joint: .leftKnee, relativeX: -0.10, relativeY: 0.35),
                .init(joint: .leftAnkle, relativeX: -0.10, relativeY: 0.70),
                .init(joint: .rightKnee, relativeX: 0.10, relativeY: 0.30),
                .init(joint: .rightAnkle, relativeX: 0.13, relativeY: 0.60),
            ]
        ),

        // === 坐姿 ===
        ReferencePose(
            id: "leg_cross",
            name: "翘腿坐",
            category: .sitting,
            description: "坐姿，一条腿翘在另一条腿上",
            keypoints: [
                .init(joint: .leftKnee, relativeX: -0.05, relativeY: 0.10),
                .init(joint: .rightKnee, relativeX: 0.05, relativeY: 0.05),
                .init(joint: .rightAnkle, relativeX: -0.02, relativeY: 0.08),
            ]
        ),
        ReferencePose(
            id: "chin_rest",
            name: "托腮",
            category: .sitting,
            description: "一只手托腮，若有所思",
            keypoints: [
                .init(joint: .leftElbow, relativeX: -0.20, relativeY: -0.05),
                .init(joint: .leftWrist, relativeX: -0.05, relativeY: -0.45),
                .init(joint: .rightElbow, relativeX: 0.20, relativeY: -0.10),
                .init(joint: .rightWrist, relativeX: 0.25, relativeY: 0.10),
            ]
        ),

        // === 动态 ===
        ReferencePose(
            id: "walking_shot",
            name: "走路抓拍",
            category: .dynamic,
            description: "自然向前走，手臂自然摆动",
            keypoints: [
                .init(joint: .leftElbow, relativeX: -0.35, relativeY: -0.08),
                .init(joint: .rightElbow, relativeX: 0.30, relativeY: 0.02),
                .init(joint: .leftKnee, relativeX: -0.08, relativeY: 0.30),
                .init(joint: .rightKnee, relativeX: 0.10, relativeY: 0.38),
            ]
        ),
        ReferencePose(
            id: "hair_flip",
            name: "甩头发",
            category: .dynamic,
            description: "转头甩动头发瞬间",
            keypoints: [
                .init(joint: .nose, relativeX: 0.12, relativeY: -0.55),
                .init(joint: .leftWrist, relativeX: -0.15, relativeY: -0.50),
                .init(joint: .rightWrist, relativeX: 0.30, relativeY: 0.10),
            ]
        ),

        // === 小清新 ===
        ReferencePose(
            id: "smell_flower",
            name: "闻花",
            category: .fresh,
            description: "双手轻轻捧花靠近鼻尖",
            keypoints: [
                .init(joint: .leftWrist, relativeX: -0.05, relativeY: -0.48),
                .init(joint: .rightWrist, relativeX: 0.05, relativeY: -0.48),
                .init(joint: .leftElbow, relativeX: -0.20, relativeY: -0.25),
                .init(joint: .rightElbow, relativeX: 0.20, relativeY: -0.25),
            ]
        ),
        ReferencePose(
            id: "look_away",
            name: "看远方",
            category: .fresh,
            description: "侧脸看向远方，身体微侧",
            keypoints: [
                .init(joint: .nose, relativeX: 0.10, relativeY: -0.55),
                .init(joint: .leftShoulder, relativeX: -0.20, relativeY: -0.30),
                .init(joint: .rightShoulder, relativeX: -0.08, relativeY: -0.28),
            ]
        ),
        ReferencePose(
            id: "eyes_closed_smile",
            name: "闭眼微笑",
            category: .fresh,
            description: "自然站立，闭眼抬头微笑",
            keypoints: [
                .init(joint: .nose, relativeX: 0.0, relativeY: -0.58),
                .init(joint: .leftWrist, relativeX: -0.35, relativeY: 0.18),
                .init(joint: .rightWrist, relativeX: 0.35, relativeY: 0.18),
            ]
        ),
    ]
}
