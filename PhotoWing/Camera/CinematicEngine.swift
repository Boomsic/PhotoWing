import Foundation
import CoreGraphics

// MARK: - 电影引擎

/// 管理电影感画面：遮幅、调色、帧率、景深
struct CinematicEngine {

    // MARK: - 配置

    struct CinematicConfig {
        var isActive: Bool = false
        var aspectRatio: AspectRatio = .widescreen235
        var colorGrade: ColorGrade = .tealOrange
        var filmGrain: Double = 0.03          // 0-0.1
        var letterboxOpacity: Double = 1.0    // 遮幅透明度
        var targetFPS: Int = 24

        enum AspectRatio: CaseIterable {
            case widescreen235   // 2.35:1 (电影宽银幕)
            case widescreen185   // 1.85:1
            case imax            // 1.43:1
            case square          // 1:1 (复古)

            var ratio: CGFloat {
                switch self {
                case .widescreen235: return 2.35
                case .widescreen185: return 1.85
                case .imax:          return 1.43
                case .square:        return 1.0
                }
            }

            var name: String {
                switch self {
                case .widescreen235: return "2.35:1 宽银幕"
                case .widescreen185: return "1.85:1"
                case .imax:          return "1.43:1 IMAX"
                case .square:        return "1:1 方形"
                }
            }
        }

        enum ColorGrade: CaseIterable {
            case tealOrange     // 青橙调（好莱坞标配）
            case vintageWarm    // 复古暖调
            case bleachBypass   // 漂白留银（高对比低饱和）
            case crossProcess   // 交叉冲洗
            case monochrome     // 黑白
            case none           // 不做调色

            var description: String {
                switch self {
                case .tealOrange:    return "青橙调（好莱坞）"
                case .vintageWarm:   return "复古暖调"
                case .bleachBypass:  return "漂白留银"
                case .crossProcess:  return "交叉冲洗"
                case .monochrome:    return "黑白"
                case .none:          return "无调色"
                }
            }

            /// 3x3 色彩矩阵（RGB 空间变换）
            var colorMatrix: [Float] {
                switch self {
                case .tealOrange:
                    // 暗部→青，亮部→橙
                    return [
                        1.00,  0.05, -0.05,
                        -0.02, 1.00,  0.02,
                        -0.10, -0.15, 1.25
                    ]
                case .vintageWarm:
                    return [
                        1.15, -0.05, -0.10,
                        -0.10, 1.05, -0.05,
                        -0.15, -0.20, 0.95
                    ]
                case .bleachBypass:
                    return [
                        0.90,  0.10,  0.05,
                        0.05,  0.85,  0.05,
                        0.05,  0.10,  0.80
                    ]
                case .crossProcess:
                    return [
                        1.10, -0.20,  0.10,
                        -0.15, 1.25, -0.10,
                        0.05,  0.15,  0.80
                    ]
                case .monochrome:
                    return [
                        0.299, 0.587, 0.114,
                        0.299, 0.587, 0.114,
                        0.299, 0.587, 0.114
                    ]
                case .none:
                    return [
                        1, 0, 0,
                        0, 1, 0,
                        0, 0, 1
                    ]
                }
            }

            /// 亮度曲线偏移
            var brightnessOffset: Float {
                switch self {
                case .tealOrange:    return 0.02
                case .vintageWarm:   return 0.05
                case .bleachBypass:  return -0.05
                case .crossProcess:  return 0.0
                case .monochrome:    return 0.0
                case .none:          return 0.0
                }
            }

            /// 饱和度缩放
            var saturationScale: Float {
                switch self {
                case .tealOrange:    return 0.90
                case .vintageWarm:   return 0.75
                case .bleachBypass:  return 0.30
                case .crossProcess:  return 1.15
                case .monochrome:    return 0.0
                case .none:          return 1.0
                }
            }

            /// 对比度 gamma
            var contrastGamma: Float {
                switch self {
                case .tealOrange:    return 1.10
                case .vintageWarm:   return 0.95
                case .bleachBypass:  return 1.30
                case .crossProcess:  return 1.05
                case .monochrome:    return 1.15
                case .none:          return 1.0
                }
            }
        }
    }

    // MARK: - 遮幅计算

    /// 给定画面尺寸，计算上下遮幅区域
    static func letterboxRects(viewSize: CGSize, aspectRatio: CinematicConfig.AspectRatio) -> (top: CGRect, bottom: CGRect) {
        let viewAspect = viewSize.width / max(1, viewSize.height)
        let targetAspect = aspectRatio.ratio

        if viewAspect > targetAspect {
            // 画面太宽，上下加黑边
            let targetHeight = viewSize.width / targetAspect
            let barHeight = (viewSize.height - targetHeight) / 2
            return (
                top: CGRect(x: 0, y: 0, width: viewSize.width, height: barHeight),
                bottom: CGRect(x: 0, y: viewSize.height - barHeight, width: viewSize.width, height: barHeight)
            )
        } else {
            // 画面太窄，左右加黑边（少见）
            let targetWidth = viewSize.height * targetAspect
            let barWidth = (viewSize.width - targetWidth) / 2
            return (
                top: CGRect(x: 0, y: 0, width: barWidth, height: viewSize.height),
                bottom: CGRect(x: viewSize.width - barWidth, y: 0, width: barWidth, height: viewSize.height)
            )
        }
    }

    // MARK: - 给美学预设生成电影配置

    static func cinematicConfig(for aesthetic: AestheticPresetEngine.AestheticStrategy) -> CinematicConfig {
        var config = CinematicConfig()
        config.isActive = true

        switch aesthetic.command {
        case .cinematic:
            config.aspectRatio = .widescreen235
            config.colorGrade = .tealOrange
            config.filmGrain = 0.04
        case .hongKongVibe:
            config.aspectRatio = .widescreen185
            config.colorGrade = .crossProcess
            config.filmGrain = 0.06
        case .japaneseFresh:
            config.aspectRatio = .widescreen185
            config.colorGrade = .none   // 日系靠色温偏移，不靠 LUT
            config.filmGrain = 0.01
        case .silhouette:
            config.aspectRatio = .widescreen235
            config.colorGrade = .monochrome  // 剪影用黑白很出效果
            config.filmGrain = 0.02
        case .warmPortrait:
            config.aspectRatio = .widescreen185
            config.colorGrade = .vintageWarm
            config.filmGrain = 0.02
        case .coolFashion:
            config.aspectRatio = .widescreen185
            config.colorGrade = .bleachBypass
            config.filmGrain = 0.02
        default:
            config.aspectRatio = .widescreen185
            config.colorGrade = .none
            config.filmGrain = 0
        }

        return config
    }
}
