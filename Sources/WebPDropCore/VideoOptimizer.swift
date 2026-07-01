import Foundation

public struct VideoMetadata: Sendable, Equatable {
    public let sourceURL: URL
    public let fileSize: Int64?
    public let duration: Double?
    public let width: Int?
    public let height: Int?
    public let fps: Double?
    public let codecName: String?
    public let hasAudio: Bool
    public let averageBitrate: Int64?

    public var resolutionText: String {
        guard let width, let height else {
            return "-"
        }

        return "\(width)x\(height)"
    }
}

public struct VideoOptimizationSuccess: Sendable, Equatable {
    public let sourceURL: URL
    public let destinationURL: URL
    public let metadata: VideoMetadata
    public let originalFileSize: Int64?
    public let optimizedFileSize: Int64?
    public let optimizedBitrate: Int64?
    public let log: String

    public var bytesSaved: Int64? {
        guard let originalFileSize, let optimizedFileSize else {
            return nil
        }

        return originalFileSize - optimizedFileSize
    }
}

public struct PosterExtractionSuccess: Sendable, Equatable {
    public let sourceURL: URL
    public let destinationURL: URL
    public let fileSize: Int64?
    public let log: String
}

public struct VideoOptimizationFailure: Sendable, Equatable {
    public let sourceURL: URL
    public let reason: String

    public init(sourceURL: URL, reason: String) {
        self.sourceURL = sourceURL
        self.reason = reason
    }
}

public struct VideoOptimizationReport: Sendable, Equatable {
    public let successes: [VideoOptimizationSuccess]
    public let failures: [VideoOptimizationFailure]
    public let posters: [PosterExtractionSuccess]

    public init(
        successes: [VideoOptimizationSuccess],
        failures: [VideoOptimizationFailure],
        posters: [PosterExtractionSuccess]
    ) {
        self.successes = successes
        self.failures = failures
        self.posters = posters
    }

    public var attemptedCount: Int {
        successes.count + failures.count
    }
}

public enum VideoOptimizerError: LocalizedError, Equatable {
    case ffmpegUnavailable
    case ffprobeUnavailable
    case unsupportedFileType(URL)
    case metadataReadFailed(URL, message: String)
    case processExecutionFailed(URL, message: String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegUnavailable:
            return "ffmpeg를 찾지 못했습니다. Homebrew로 설치하세요: brew install ffmpeg"
        case .ffprobeUnavailable:
            return "ffprobe를 찾지 못했습니다. Homebrew로 설치하세요: brew install ffmpeg"
        case .unsupportedFileType(let url):
            return "지원하지 않는 영상 형식입니다: \(url.lastPathComponent)"
        case let .metadataReadFailed(url, message):
            return "영상 정보 분석 실패 (\(url.lastPathComponent)): \(message)"
        case let .processExecutionFailed(url, message):
            return "ffmpeg 실행 실패 (\(url.lastPathComponent)): \(message)"
        }
    }
}

public struct VideoOptimizer {
    public static let supportedExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv",
        "mpg", "mpeg", "ts", "mts", "m2ts", "3gp", "ogv",
    ]

    public static let ffmpegExecutableCandidates = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/homebrew/opt/ffmpeg/bin/ffmpeg",
    ]

    public static let ffprobeExecutableCandidates = [
        "/opt/homebrew/bin/ffprobe",
        "/usr/local/bin/ffprobe",
        "/opt/homebrew/opt/ffmpeg/bin/ffprobe",
    ]

    public init() {}

    public var ffmpegURL: URL? {
        executableURL(
            environmentKey: "FFMPEG_PATH",
            executableName: "ffmpeg",
            candidates: Self.ffmpegExecutableCandidates
        )
    }

    public var ffprobeURL: URL? {
        executableURL(
            environmentKey: "FFPROBE_PATH",
            executableName: "ffprobe",
            candidates: Self.ffprobeExecutableCandidates
        )
    }

    public var isOptimizationAvailable: Bool {
        ffmpegURL != nil && ffprobeURL != nil
    }

    public func canOptimize(_ url: URL) -> Bool {
        Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public func analyze(sourceURL: URL, fileManager: FileManager = .default) throws -> VideoMetadata {
        guard let ffprobeURL else {
            throw VideoOptimizerError.ffprobeUnavailable
        }

        guard canOptimize(sourceURL) else {
            throw VideoOptimizerError.unsupportedFileType(sourceURL)
        }

        let data = try runProcessData(
            executableURL: ffprobeURL,
            arguments: [
                "-v", "error",
                "-print_format", "json",
                "-show_format",
                "-show_streams",
                sourceURL.path,
            ],
            sourceURL: sourceURL,
            failureMapper: { VideoOptimizerError.metadataReadFailed(sourceURL, message: $0) }
        )

        do {
            let response = try JSONDecoder().decode(FFProbeResponse.self, from: data)
            let videoStream = response.streams.first { $0.codecType == "video" }
            let audioStream = response.streams.first { $0.codecType == "audio" }
            let duration = response.format?.duration.flatMap(Double.init)
                ?? videoStream?.duration.flatMap(Double.init)
            let averageBitrate = response.format?.bitRate.flatMap(Int64.init)
                ?? bitrateFromFileSize(fileSize(at: sourceURL, fileManager: fileManager), duration: duration)

            return VideoMetadata(
                sourceURL: sourceURL,
                fileSize: fileSize(at: sourceURL, fileManager: fileManager),
                duration: duration,
                width: videoStream?.width,
                height: videoStream?.height,
                fps: parseFrameRate(videoStream?.averageFrameRate ?? videoStream?.realFrameRate),
                codecName: videoStream?.codecName,
                hasAudio: audioStream != nil,
                averageBitrate: averageBitrate
            )
        } catch {
            throw VideoOptimizerError.metadataReadFailed(sourceURL, message: error.localizedDescription)
        }
    }

    @discardableResult
    public func optimize(
        sourceURL: URL,
        options: VideoOptimizationOptions,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> VideoOptimizationSuccess {
        guard let ffmpegURL else {
            throw VideoOptimizerError.ffmpegUnavailable
        }

        let metadata = try analyze(sourceURL: sourceURL, fileManager: fileManager)
        let destinationURL = makeDestinationURL(
            for: sourceURL,
            suffix: options.outputSuffix,
            fileExtension: "mp4",
            outputDirectory: outputDirectory,
            uniquingIn: fileManager
        )
        let output = try runProcessText(
            executableURL: ffmpegURL,
            arguments: ffmpegArguments(sourceURL: sourceURL, destinationURL: destinationURL, metadata: metadata, options: options),
            sourceURL: sourceURL,
            failureMapper: { VideoOptimizerError.processExecutionFailed(sourceURL, message: $0) }
        )

        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw VideoOptimizerError.processExecutionFailed(sourceURL, message: output)
        }

        let optimizedSize = fileSize(at: destinationURL, fileManager: fileManager)
        let optimizedBitrate = bitrateFromFileSize(optimizedSize, duration: metadata.duration)

        return VideoOptimizationSuccess(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            metadata: metadata,
            originalFileSize: metadata.fileSize,
            optimizedFileSize: optimizedSize,
            optimizedBitrate: optimizedBitrate,
            log: output
        )
    }

    @discardableResult
    public func extractPoster(
        sourceURL: URL,
        time: Double = 1,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> PosterExtractionSuccess {
        guard let ffmpegURL else {
            throw VideoOptimizerError.ffmpegUnavailable
        }

        guard canOptimize(sourceURL) else {
            throw VideoOptimizerError.unsupportedFileType(sourceURL)
        }

        let destinationURL = makeDestinationURL(
            for: sourceURL,
            suffix: "poster",
            fileExtension: "webp",
            outputDirectory: outputDirectory,
            uniquingIn: fileManager
        )
        let output = try runProcessText(
            executableURL: ffmpegURL,
            arguments: [
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-ss", String(format: "%.2f", time),
                "-i", sourceURL.path,
                "-frames:v", "1",
                "-compression_level", "6",
                "-quality", "82",
                destinationURL.path,
            ],
            sourceURL: sourceURL,
            failureMapper: { VideoOptimizerError.processExecutionFailed(sourceURL, message: $0) }
        )

        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw VideoOptimizerError.processExecutionFailed(sourceURL, message: output)
        }

        return PosterExtractionSuccess(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            fileSize: fileSize(at: destinationURL, fileManager: fileManager),
            log: output
        )
    }

    public func optimize(
        urls: [URL],
        options: VideoOptimizationOptions,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> VideoOptimizationReport {
        var successes: [VideoOptimizationSuccess] = []
        var failures: [VideoOptimizationFailure] = []

        for url in urls {
            do {
                successes.append(
                    try optimize(
                        sourceURL: url,
                        options: options,
                        outputDirectory: outputDirectory,
                        fileManager: fileManager
                    )
                )
            } catch {
                failures.append(
                    VideoOptimizationFailure(
                        sourceURL: url,
                        reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            }
        }

        return VideoOptimizationReport(successes: successes, failures: failures, posters: [])
    }

    public func createLandingPackage(
        sourceURL: URL,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> VideoOptimizationReport {
        var successes: [VideoOptimizationSuccess] = []
        var failures: [VideoOptimizationFailure] = []
        var posters: [PosterExtractionSuccess] = []

        let jobs: [VideoOptimizationOptions] = [
            VideoOptimizationOptions(
                codec: .h264,
                width: 1920,
                fps: 30,
                removeAudio: true,
                fastStart: true,
                quality: .high,
                targetMegabytes: 12,
                outputSuffix: "pc"
            ),
            VideoOptimizationOptions(
                codec: .h264,
                width: 1280,
                fps: 30,
                removeAudio: true,
                fastStart: true,
                quality: .high,
                targetMegabytes: 5,
                outputSuffix: "mobile"
            ),
        ]

        for options in jobs {
            do {
                successes.append(
                    try optimize(
                        sourceURL: sourceURL,
                        options: options,
                        outputDirectory: outputDirectory,
                        fileManager: fileManager
                    )
                )
            } catch {
                failures.append(
                    VideoOptimizationFailure(
                        sourceURL: sourceURL,
                        reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            }
        }

        do {
            posters.append(
                try extractPoster(
                    sourceURL: sourceURL,
                    time: 1,
                    outputDirectory: outputDirectory,
                    fileManager: fileManager
                )
            )
        } catch {
            failures.append(
                VideoOptimizationFailure(
                    sourceURL: sourceURL,
                    reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            )
        }

        return VideoOptimizationReport(successes: successes, failures: failures, posters: posters)
    }

    private func ffmpegArguments(
        sourceURL: URL,
        destinationURL: URL,
        metadata: VideoMetadata,
        options: VideoOptimizationOptions
    ) -> [String] {
        var arguments = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", sourceURL.path,
            "-map", "0:v:0",
        ]

        if options.removeAudio {
            arguments.append("-an")
        } else {
            arguments += ["-map", "0:a?", "-c:a", "aac", "-b:a", "128k"]
        }

        if let width = options.width, let sourceWidth = metadata.width, sourceWidth > width {
            arguments += ["-vf", "scale=\(width):-2"]
        }

        if let fps = options.fps, let sourceFPS = metadata.fps, sourceFPS > Double(fps) {
            arguments += ["-r", "\(fps)"]
        } else if let fps = options.fps, metadata.fps == nil {
            arguments += ["-r", "\(fps)"]
        }

        arguments += ["-c:v", options.codec.ffmpegEncoder]

        if let targetMegabytes = options.targetMegabytes,
           let duration = metadata.duration,
           duration > 0 {
            let videoBitrateKbps = targetVideoBitrateKbps(
                targetMegabytes: targetMegabytes,
                duration: duration,
                reservesAudio: !options.removeAudio
            )
            arguments += [
                "-b:v", "\(videoBitrateKbps)k",
                "-maxrate", "\(Int(Double(videoBitrateKbps) * 1.25))k",
                "-bufsize", "\(videoBitrateKbps * 2)k",
            ]
        } else {
            arguments += ["-crf", "\(options.quality.crf(for: options.codec))"]
        }

        if options.codec == .h264 {
            arguments += ["-preset", "medium", "-pix_fmt", "yuv420p"]
        } else {
            arguments += ["-preset", "medium", "-pix_fmt", "yuv420p", "-tag:v", "hvc1"]
        }

        if options.fastStart {
            arguments += ["-movflags", "+faststart"]
        }

        arguments.append(destinationURL.path)
        return arguments
    }

    private func targetVideoBitrateKbps(targetMegabytes: Double, duration: Double, reservesAudio: Bool) -> Int {
        let targetBits = targetMegabytes * 1_024 * 1_024 * 8
        let totalKbps = (targetBits / duration) / 1_000
        let audioReserveKbps = reservesAudio ? 128.0 : 0
        return max(250, Int((totalKbps - audioReserveKbps) * 0.92))
    }

    private func makeDestinationURL(
        for sourceURL: URL,
        suffix: String,
        fileExtension: String,
        outputDirectory: URL?,
        uniquingIn fileManager: FileManager
    ) -> URL {
        let directory = outputDirectory ?? sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let cleanedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleanedSuffix.isEmpty ? baseName : "\(baseName).\(cleanedSuffix)"
        var candidate = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
        var counter = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(name)-\(counter)")
                .appendingPathExtension(fileExtension)
            counter += 1
        }

        return candidate
    }

    private func fileSize(at url: URL, fileManager: FileManager) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let rawSize = attributes[.size] as? NSNumber else {
            return nil
        }

        return rawSize.int64Value
    }

    private func bitrateFromFileSize(_ fileSize: Int64?, duration: Double?) -> Int64? {
        guard let fileSize, let duration, duration > 0 else {
            return nil
        }

        return Int64((Double(fileSize) * 8) / duration)
    }

    private func parseFrameRate(_ rawValue: String?) -> Double? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        let parts = rawValue.split(separator: "/")
        if parts.count == 2,
           let numerator = Double(parts[0]),
           let denominator = Double(parts[1]),
           denominator != 0 {
            return numerator / denominator
        }

        return Double(rawValue)
    }

    private func executableURL(environmentKey: String, executableName: String, candidates: [String]) -> URL? {
        if let override = ProcessInfo.processInfo.environment[environmentKey],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for entry in pathEntries {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent(executableName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private func runProcessText(
        executableURL: URL,
        arguments: [String],
        sourceURL: URL,
        failureMapper: (String) -> VideoOptimizerError
    ) throws -> String {
        let data = try runProcessData(
            executableURL: executableURL,
            arguments: arguments,
            sourceURL: sourceURL,
            failureMapper: failureMapper
        )

        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func runProcessData(
        executableURL: URL,
        arguments: [String],
        sourceURL: URL,
        failureMapper: (String) -> VideoOptimizerError
    ) throws -> Data {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw failureMapper(output.isEmpty ? "알 수 없는 오류" : output)
        }

        return data
    }
}

private struct FFProbeResponse: Decodable {
    let streams: [FFProbeStream]
    let format: FFProbeFormat?
}

private struct FFProbeStream: Decodable {
    let codecName: String?
    let codecType: String?
    let width: Int?
    let height: Int?
    let averageFrameRate: String?
    let realFrameRate: String?
    let duration: String?

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case codecType = "codec_type"
        case width
        case height
        case averageFrameRate = "avg_frame_rate"
        case realFrameRate = "r_frame_rate"
        case duration
    }
}

private struct FFProbeFormat: Decodable {
    let duration: String?
    let bitRate: String?

    enum CodingKeys: String, CodingKey {
        case duration
        case bitRate = "bit_rate"
    }
}
