import SwiftUI
import Speech
import AVFoundation

/// 美学指令快捷栏
/// 她一句话 → 一键切换全套拍摄策略
struct AestheticCommandBar: View {
    @Binding var activeCommand: AestheticCommand?
    let onSelect: (AestheticCommand) -> Void
    let onDismiss: () -> Void

    // 最常用的 4 个放外面（一行显示）
    static let quickCommands: [AestheticCommand] = [
        .longerLegs, .smallerFace, .cinematic, .warmPortrait
    ]

    // 更多选项
    static let moreCommands: [AestheticCommand] = [
        .hongKongVibe, .japaneseFresh, .silhouette, .coolFashion
    ]

    @State private var showMore = false

    var body: some View {
        VStack(spacing: 8) {
            // 主行：4 个最常用指令
            HStack(spacing: 8) {
                ForEach(Self.quickCommands, id: \.self) { cmd in
                    commandButton(cmd)
                }

                // 更多按钮
                Button(action: { showMore.toggle() }) {
                    VStack(spacing: 2) {
                        Image(systemName: showMore ? "chevron.down" : "ellipsis")
                            .font(.system(size: 14))
                        Text("更多")
                            .font(.system(size: 9))
                    }
                    .frame(width: 52, height: 52)
                    .foregroundColor(.white.opacity(0.8))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            // 展开行
            if showMore {
                HStack(spacing: 8) {
                    ForEach(Self.moreCommands, id: \.self) { cmd in
                        commandButton(cmd)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.25), value: showMore)
    }

    private func commandButton(_ cmd: AestheticCommand) -> some View {
        Button(action: {
            if activeCommand == cmd {
                activeCommand = nil
                onDismiss()
            } else {
                activeCommand = cmd
                onSelect(cmd)
            }
        }) {
            VStack(spacing: 2) {
                Text(cmd.rawValue.components(separatedBy: " ").first ?? "")
                    .font(.system(size: 11))
                Text(cmd.rawValue.components(separatedBy: " ").dropFirst().joined(separator: " "))
                    .font(.system(size: 9))
                    .opacity(0.8)
            }
            .frame(width: 58, height: 44)
            .foregroundColor(activeCommand == cmd ? .black : .white)
            .background(
                activeCommand == cmd
                    ? Color.yellow
                    : Color.white.opacity(0.12)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - 语音指令监听器（iOS Speech Framework）

import Speech

@MainActor
final class VoiceCommandListener: ObservableObject {

    @Published var isListening = false
    @Published var recognizedText: String = ""
    @Published var matchedCommand: AestheticCommand?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    func startListening() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        stopListening()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.recognizedText = text

                // 实时匹配美学指令
                if let matched = AestheticPresetEngine.match(from: text) {
                    self.matchedCommand = matched.command
                }
            }
            if error != nil {
                self.stopListening()
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }
}
