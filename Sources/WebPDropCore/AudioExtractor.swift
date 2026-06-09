import Foundation

public struct AudioExtractionSuccess: Sendable, Equatable {
    public let sourceURL: URL
    public let destinationURL: URL
    public let sourceFileSize: Int64?
    public let outputFileSize: Int64?
}

public struct AudioExtractionFailure: Sendable, Equatable {
    public let sourceURL: URL
    public let reason: String
}

public struct AudioExtractionReport: Sendable, Equatable {
    public let successes: [AudioExtractionSuccess]
    public let failures: [AudioExtractionFailure]

    public var attemptedCount: Int {
        successes.count + failures.count
    }
}

public enum AudioExtractorError: LocalizedError, Equatable {
    case extractorUnavailable
    case unsupportedFileType(URL)
    case noAudioTrack(URL)
    case processExecutionFailed(URL, message: String)

    public var errorDescription: String? {
        switch self {
        case .extractorUnavailable:
            return "ffmpeg를 찾지 못했습니다. Homebrew로 설치하세요: brew install ffmpeg"
        case .unsupportedFileType(let url):
            return "지원하지 않는 파일 형식입니다: \(url.lastPathComponent)"
        case .noAudioTrack(let url):
            return "오디오 트랙을 찾을 수 없습니다: \(url.lastPathComponent)"
        case let .processExecutionFailed(url, message):
            return "ffmpeg 실행 실패 (\(url.lastPathComponent)): \(message)"
        }
    }
}

public struct AudioExtractor {
    /// 음원을 추출할 수 있는 입력 컨테이너/파일 확장자.
    public static let supportedExtensions: Set<String> = [
        // 비디오 컨테이너
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv",
        "mpg", "mpeg", "ts", "mts", "m2ts", "3gp", "ogv",
        // 오디오 파일 (재인코딩 용도)
        "aac", "m4a", "mp3", "wav", "flac", "ogg", "opus", "wma", "aiff", "caf",
    ]

    public static let defaultExecutableCandidates = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/homebrew/opt/ffmpeg/bin/ffmpeg",
    ]

    public init() {}

    public var ffmpegURL: URL? {
        if let override = ProcessInfo.processInfo.environment["FFMPEG_PATH"],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        for path in Self.defaultExecutableCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let resolved = resolveFromPath() {
            return resolved
        }

        return nil
    }

    public var isExtractionAvailable: Bool {
        ffmpegURL != nil
    }

    public func canExtract(_ url: URL) -> Bool {
        Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public func makeDestinationURL(
        for sourceURL: URL,
        format: AudioOutputFormat,
        outputDirectory: URL? = nil,
        uniquingIn fileManager: FileManager = .default
    ) -> URL {
        let directory = outputDirectory ?? sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(format.fileExtension)
        var counter = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(counter)")
                .appendingPathExtension(format.fileExtension)
            counter += 1
        }

        return candidate
    }

    @discardableResult
    public func extract(
        sourceURL: URL,
        options: AudioExtractionOptions,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> AudioExtractionSuccess {
        guard let ffmpegURL else {
            throw AudioExtractorError.extractorUnavailable
        }

        guard canExtract(sourceURL) else {
            throw AudioExtractorError.unsupportedFileType(sourceURL)
        }

        let destinationURL = makeDestinationURL(
            for: sourceURL,
            format: options.format,
            outputDirectory: outputDirectory,
            uniquingIn: fileManager
        )

        let output = try runFFmpeg(
            ffmpegURL: ffmpegURL,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            options: options
        )

        guard fileManager.fileExists(atPath: destinationURL.path) else {
            if output.lowercased().contains("does not contain any stream")
                || output.lowercased().contains("output file does not contain any stream") {
                throw AudioExtractorError.noAudioTrack(sourceURL)
            }
            throw AudioExtractorError.processExecutionFailed(sourceURL, message: output)
        }

        return AudioExtractionSuccess(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            sourceFileSize: fileSize(at: sourceURL, fileManager: fileManager),
            outputFileSize: fileSize(at: destinationURL, fileManager: fileManager)
        )
    }

    public func extract(
        urls: [URL],
        options: AudioExtractionOptions,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> AudioExtractionReport {
        var successes: [AudioExtractionSuccess] = []
        var failures: [AudioExtractionFailure] = []

        for url in urls {
            do {
                let result = try extract(
                    sourceURL: url,
                    options: options,
                    outputDirectory: outputDirectory,
                    fileManager: fileManager
                )
                successes.append(result)
            } catch {
                failures.append(
                    AudioExtractionFailure(
                        sourceURL: url,
                        reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            }
        }

        return AudioExtractionReport(successes: successes, failures: failures)
    }

    private func fileSize(at url: URL, fileManager: FileManager) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let rawSize = attributes[.size] as? NSNumber else {
            return nil
        }

        return rawSize.int64Value
    }

    private func resolveFromPath() -> URL? {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for entry in pathEntries {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent("ffmpeg")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private func runFFmpeg(
        ffmpegURL: URL,
        sourceURL: URL,
        destinationURL: URL,
        options: AudioExtractionOptions
    ) throws -> String {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = ffmpegURL
        process.arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", sourceURL.path,
            "-vn",
        ]
            + options.ffmpegAudioArguments()
            + [destinationURL.path]

        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw AudioExtractorError.processExecutionFailed(
                sourceURL,
                message: output.isEmpty ? "알 수 없는 오류" : output
            )
        }

        return output
    }
}
