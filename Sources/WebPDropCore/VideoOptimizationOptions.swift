import Foundation

public enum VideoCodec: String, CaseIterable, Identifiable, Sendable {
    case h264
    case hevc

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        }
    }

    var ffmpegEncoder: String {
        switch self {
        case .h264:
            return "libx264"
        case .hevc:
            return "libx265"
        }
    }
}

public enum VideoQualityLevel: String, CaseIterable, Identifiable, Sendable {
    case low
    case normal
    case high
    case maximum

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .low:
            return "낮음"
        case .normal:
            return "보통"
        case .high:
            return "높음"
        case .maximum:
            return "최대"
        }
    }

    func crf(for codec: VideoCodec) -> Int {
        switch (self, codec) {
        case (.low, .h264):
            return 31
        case (.normal, .h264):
            return 26
        case (.high, .h264):
            return 21
        case (.maximum, .h264):
            return 17
        case (.low, .hevc):
            return 33
        case (.normal, .hevc):
            return 28
        case (.high, .hevc):
            return 23
        case (.maximum, .hevc):
            return 19
        }
    }
}

public enum VideoOptimizationPreset: String, CaseIterable, Identifiable, Sendable {
    case landingDesktop
    case landingMobile
    case quickPreview
    case maximumQuality

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .landingDesktop:
            return "랜딩 PC"
        case .landingMobile:
            return "랜딩 모바일"
        case .quickPreview:
            return "가벼운 미리보기"
        case .maximumQuality:
            return "최대 품질"
        }
    }

    public var suggestedTargetMegabytes: Double? {
        switch self {
        case .landingDesktop:
            return 12
        case .landingMobile:
            return 5
        case .quickPreview:
            return 3
        case .maximumQuality:
            return nil
        }
    }

    public var defaultWidth: Int? {
        switch self {
        case .landingDesktop:
            return 1920
        case .landingMobile:
            return 1280
        case .quickPreview:
            return 720
        case .maximumQuality:
            return nil
        }
    }

    public var defaultFPS: Int? {
        switch self {
        case .landingDesktop, .landingMobile, .quickPreview:
            return 30
        case .maximumQuality:
            return nil
        }
    }

    public var defaultQuality: VideoQualityLevel {
        switch self {
        case .landingDesktop, .landingMobile:
            return .high
        case .quickPreview:
            return .low
        case .maximumQuality:
            return .maximum
        }
    }

    public var outputSuffix: String {
        switch self {
        case .landingDesktop:
            return "pc"
        case .landingMobile:
            return "mobile"
        case .quickPreview:
            return "preview"
        case .maximumQuality:
            return "max"
        }
    }
}

public struct VideoOptimizationOptions: Sendable, Equatable {
    public let codec: VideoCodec
    public let width: Int?
    public let fps: Int?
    public let removeAudio: Bool
    public let fastStart: Bool
    public let quality: VideoQualityLevel
    public let targetMegabytes: Double?
    public let outputSuffix: String

    public init(
        codec: VideoCodec = .h264,
        width: Int? = nil,
        fps: Int? = nil,
        removeAudio: Bool = true,
        fastStart: Bool = true,
        quality: VideoQualityLevel = .high,
        targetMegabytes: Double? = nil,
        outputSuffix: String = "optimized"
    ) {
        self.codec = codec
        self.width = width
        self.fps = fps
        self.removeAudio = removeAudio
        self.fastStart = fastStart
        self.quality = quality
        self.targetMegabytes = targetMegabytes
        self.outputSuffix = outputSuffix
    }
}
