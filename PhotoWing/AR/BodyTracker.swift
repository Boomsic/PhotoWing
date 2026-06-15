import ARKit
import Vision
import Combine
import UIKit

/// 人体骨骼追踪器：ARKit 优先，Vision 降级
@MainActor
final class BodyTracker: NSObject, ObservableObject {

    // MARK: - 发布状态

    @Published var skeleton: BodySkeleton?
    @Published var isTracking = false
    @Published var trackingMethod: TrackingMethod = .none

    enum TrackingMethod: String {
        case arkit = "ARKit 3D骨骼"
        case vision = "Vision 2D姿态"
        case none = "未追踪"
    }

    // MARK: - ARKit

    private let arSession = ARSession()
    private var arkitEnabled: Bool {
        ARBodyTrackingConfiguration.isSupported
    }

    // MARK: - Vision 降级方案

    private let visionQueue = DispatchQueue(label: "vision.tracker", qos: .userInitiated)
    private let bodyPoseRequest = VNDetectHumanBodyPoseRequest()
    private let faceRequest = VNDetectFaceRectanglesRequest()

    // MARK: - 启动

    func start() {
        if arkitEnabled {
            startARKit()
        } else {
            startVisionLoop()
        }
    }

    func stop() {
        arSession.pause()
        isTracking = false
        trackingMethod = .none
    }

    // MARK: - ARKit 模式

    private func startARKit() {
        let config = ARBodyTrackingConfiguration()
        config.isAutoFocusEnabled = true
        arSession.delegate = self
        arSession.run(config, options: [.resetTracking])
        trackingMethod = .arkit
        isTracking = true
    }

    // MARK: - Vision 降级模式（相机每帧调用）

    private var lastVisionTime: Date = .distantPast
    private let visionInterval: TimeInterval = 0.1  // 10fps

    private func startVisionLoop() {
        trackingMethod = .vision
        isTracking = true
    }

    /// 相机帧回调，传入 pixel buffer
    func processFrame(_ pixelBuffer: CVPixelBuffer, size: CGSize) {
        guard trackingMethod == .vision else { return }

        let now = Date()
        guard now.timeIntervalSince(lastVisionTime) >= visionInterval else { return }
        lastVisionTime = now

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        visionQueue.async { [weak self] in
            guard let self else { return }

            // 人体姿态
            try? handler.perform([self.bodyPoseRequest])
            // 人脸（用于补充头部位置）
            try? handler.perform([self.faceRequest])

            guard let pose = self.bodyPoseRequest.results?.first else {
                DispatchQueue.main.async { self.isTracking = false }
                return
            }

            let skeleton = self.convertVisionPose(pose, imageSize: size)
            DispatchQueue.main.async { [weak self] in
                self?.skeleton = skeleton
                self?.isTracking = true
            }
        }
    }

    // MARK: - Vision → 统一 BodySkeleton

    private func convertVisionPose(_ observation: VNHumanBodyPoseObservation,
                                   imageSize: CGSize) -> BodySkeleton {
        var joints: [BodySkeleton.JointPoint] = []

        let mapping: [(VNHumanBodyPoseObservation.JointName, BodySkeleton.JointName)] = [
            (.nose, .nose),
            (.leftEye, .leftEye), (.rightEye, .rightEye),
            (.leftEar, .leftEar), (.rightEar, .rightEar),
            (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
            (.leftHip, .leftHip), (.rightHip, .rightHip),
            (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
        ]

        let allPoints = try? observation.recognizedPoints(.all)

        for (visionJoint, ourJoint) in mapping {
            if let point = allPoints?[visionJoint], point.confidence > 0.3 {
                // Vision 的 y 轴是翻转的（左下原点），需翻转为左上原点
                let normalized = CGPoint(
                    x: point.location.x,
                    y: 1.0 - point.location.y
                )
                joints.append(.init(name: ourJoint, position: normalized, confidence: Float(point.confidence)))
            } else {
                joints.append(.init(name: ourJoint, position: .zero, confidence: 0))
            }
        }

        return BodySkeleton(
            joints: joints,
            confidence: Float(observation.confidence),
            timestamp: Date()
        )
    }
}

// MARK: - ARSessionDelegate

extension BodyTracker: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }

            let skeleton3D = bodyAnchor.skeleton
            var joints: [BodySkeleton.JointPoint] = []

            // ARKit 的关节名称映射
            let arkitJoints: [(ARSkeleton.JointName, BodySkeleton.JointName)] = [
                (.head, .nose),
                (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
                (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
                (.leftHand, .leftWrist), (.rightHand, .rightWrist),
                (.leftHip, .leftHip), (.rightHip, .rightHip),
                (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
                (.leftFoot, .leftAnkle), (.rightFoot, .rightAnkle),
            ]

            for (arJoint, ourJoint) in arkitJoints {
                if skeleton3D.isJointTracked(arJoint) {
                    let transform = skeleton3D.localTransform(for: arJoint)
                    let position = transform.columns.3
                    // ARKit 3D 坐标 → 简化 2D 归一化（由上层相机投影矩阵转换）
                    // 此处存储原始值，UI 层通过 camera.projectionMatrix 做投影
                    joints.append(.init(
                        name: ourJoint,
                        position: CGPoint(x: CGFloat(position.x), y: CGFloat(position.y)),
                        confidence: 0.9
                    ))
                } else {
                    joints.append(.init(name: ourJoint, position: .zero, confidence: 0))
                }
            }

            // 补充 Vision 才有的关节
            for filler in [BodySkeleton.JointName.leftEye, .rightEye, .leftEar, .rightEar] {
                joints.append(.init(name: filler, position: .zero, confidence: 0))
            }

            DispatchQueue.main.async { [weak self] in
                self?.skeleton = BodySkeleton(
                    joints: joints,
                    confidence: 0.9,
                    timestamp: Date()
                )
                self?.isTracking = true
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isTracking = false
            // 降级到 Vision
            self?.startVisionLoop()
        }
    }
}
