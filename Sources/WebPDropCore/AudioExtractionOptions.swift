import Foundation

public enum AudioOutputFormat: String, Sendable, CaseIterable, Identifiable {
    case mp3
    case m4a
    case aac
    case wav
    case flac

    public var id: String { rawValue }

    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .mp3:
            return "MP3"
        case .m4a:
            return "M4A (AAC)"
        case .aac:
            return "AAC"
        case .wav:
            return "WAV (무손실)"
        case .flac:
            return "FLAC (무손실)"
        }
    }

    public var isLossless: Bool {
        self == .wav || self == .flac
    }

    public var supportsBitrate: Bool {
        !isLossless
    }
}

public struct AudioExtractionOptions: Sendable, Equatable {
    public static let availableBitrates = [96, 128, 160, 192, 256, 320]

    public var format: AudioOutputFormat
    public var bitrateKbps: Int

    public init(format: AudioOutputFormat = .mp3, bitrateKbps: Int = 192) {
        self.format = format
        self.bitrateKbps = min(max(bitrateKbps, 64), 320)
    }

    /// ffmpeg에 전달할 오디오 코덱/비트레이트 인자.
    public func ffmpegAudioArguments() -> [String] {
        switch format {
        case .mp3:
            return ["-c:a", "libmp3lame", "-b:a", "\(bitrateKbps)k"]
        case .m4a, .aac:
            return ["-c:a", "aac", "-b:a", "\(bitrateKbps)k"]
        case .wav:
            return ["-c:a", "pcm_s16le"]
        case .flac:
            return ["-c:a", "flac"]
        }
    }
}
