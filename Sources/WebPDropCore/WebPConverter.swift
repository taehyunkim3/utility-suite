import Foundation
import ImageIO

public struct ConversionSuccess: Sendable, Equatable {
    public let sourceURL: URL
    public let destinationURL: URL
    public let originalFileSize: Int64?
    public let convertedFileSize: Int64?

    public var bytesSaved: Int64? {
        guard let originalFileSize, let convertedFileSize else {
            return nil
        }

        return originalFileSize - convertedFileSize
    }
}

public struct ConversionFailure: Sendable, Equatable {
    public let sourceURL: URL
    public let reason: String
}

public struct BatchConversionReport: Sendable, Equatable {
    public let successes: [ConversionSuccess]
    public let failures: [ConversionFailure]

    public var attemptedCount: Int {
        successes.count + failures.count
    }
}

public enum WebPConverterError: LocalizedError, Equatable {
    case encoderUnavailable
    case unsupportedFileType(URL)
    case processExecutionFailed(URL, message: String)

    public var errorDescription: String? {
        switch self {
        case .encoderUnavailable:
            return "Unable to find the cwebp encoder. Install it with Homebrew: brew install webp"
        case .unsupportedFileType(let url):
            return "Unsupported file type: \(url.lastPathComponent)"
        case let .processExecutionFailed(url, message):
            return "cwebp failed for \(url.lastPathComponent): \(message)"
        }
    }
}

public struct WebPConverter {
    public static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg"]

    public static let defaultExecutableCandidates = [
        "/opt/homebrew/bin/cwebp",
        "/usr/local/bin/cwebp",
        "/opt/homebrew/opt/webp/bin/cwebp",
    ]

    public init() {}

    public var encoderURL: URL? {
        if let override = ProcessInfo.processInfo.environment["WEBP_CWEBP_PATH"],
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

    public var isEncodingAvailable: Bool {
        encoderURL != nil
    }

    public func canConvert(_ url: URL) -> Bool {
        Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public func makeDestinationURL(
        for sourceURL: URL,
        outputDirectory: URL? = nil,
        uniquingIn fileManager: FileManager = .default
    ) -> URL {
        let directory = outputDirectory ?? sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension("webp")
        var counter = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(counter)")
                .appendingPathExtension("webp")
            counter += 1
        }

        return candidate
    }

    public func convert(
        sourceURL: URL,
        options: WebPConversionOptions,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ConversionSuccess {
        guard let encoderURL else {
            throw WebPConverterError.encoderUnavailable
        }

        guard canConvert(sourceURL) else {
            throw WebPConverterError.unsupportedFileType(sourceURL)
        }

        let destinationURL = makeDestinationURL(
            for: sourceURL,
            outputDirectory: outputDirectory,
            uniquingIn: fileManager
        )
        let output = try runCWebP(
            encoderURL: encoderURL,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            qualityPercentage: options.qualityPercentage
        )

        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw WebPConverterError.processExecutionFailed(sourceURL, message: output)
        }

        return ConversionSuccess(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            originalFileSize: fileSize(at: sourceURL, fileManager: fileManager),
            convertedFileSize: fileSize(at: destinationURL, fileManager: fileManager)
        )
    }

    public func convert(
        urls: [URL],
        options: WebPConversionOptions,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> BatchConversionReport {
        var successes: [ConversionSuccess] = []
        var failures: [ConversionFailure] = []

        for url in urls {
            do {
                let result = try convert(
                    sourceURL: url,
                    options: options,
                    outputDirectory: outputDirectory,
                    fileManager: fileManager
                )
                successes.append(result)
            } catch {
                failures.append(
                    ConversionFailure(
                        sourceURL: url,
                        reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            }
        }

        return BatchConversionReport(successes: successes, failures: failures)
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
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent("cwebp")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private func runCWebP(
        encoderURL: URL,
        sourceURL: URL,
        destinationURL: URL,
        qualityPercentage: Int
    ) throws -> String {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = encoderURL
        process.arguments = [
            "-quiet",
            "-q",
            "\(qualityPercentage)",
            "-o",
            destinationURL.path,
            sourceURL.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw WebPConverterError.processExecutionFailed(sourceURL, message: output.isEmpty ? "Unknown error" : output)
        }

        return output
    }
}
