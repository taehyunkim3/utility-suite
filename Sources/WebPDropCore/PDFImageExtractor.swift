import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public struct PDFImageExtractionSuccess: Sendable, Equatable {
    public let sourceURL: URL
    public let outputURLs: [URL]

    public var pageCount: Int {
        outputURLs.count
    }

    public var outputDirectory: URL? {
        outputURLs.first?.deletingLastPathComponent()
    }
}

public struct PDFImageExtractionFailure: Sendable, Equatable {
    public let sourceURL: URL
    public let reason: String
}

public struct PDFImageExtractionReport: Sendable, Equatable {
    public let successes: [PDFImageExtractionSuccess]
    public let failures: [PDFImageExtractionFailure]

    public var attemptedCount: Int {
        successes.count + failures.count
    }

    public var totalImageCount: Int {
        successes.reduce(0) { $0 + $1.pageCount }
    }
}

public enum PDFImageExtractorError: LocalizedError, Equatable {
    case unsupportedFileType(URL)
    case cannotOpenDocument(URL)
    case noPages(URL)
    case renderFailed(URL, pageNumber: Int)
    case writeFailed(URL)
    case webPEncoderUnavailable
    case webPEncodingFailed(URL, message: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let url):
            return "지원하지 않는 파일 형식입니다: \(url.lastPathComponent)"
        case .cannotOpenDocument(let url):
            return "PDF를 열 수 없습니다: \(url.lastPathComponent)"
        case .noPages(let url):
            return "페이지가 없는 PDF입니다: \(url.lastPathComponent)"
        case let .renderFailed(url, pageNumber):
            return "\(pageNumber)페이지 렌더링 실패: \(url.lastPathComponent)"
        case .writeFailed(let url):
            return "이미지 저장 실패: \(url.lastPathComponent)"
        case .webPEncoderUnavailable:
            return "WebP 인코더를 찾지 못했습니다. brew install webp 로 설치하세요."
        case let .webPEncodingFailed(url, message):
            return "WebP 저장 실패: \(url.lastPathComponent) \(message)"
        }
    }
}

public struct PDFImageExtractor {
    public static let supportedExtensions: Set<String> = ["pdf"]

    public init() {}

    public func canExtract(_ url: URL) -> Bool {
        Self.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public func makeDestinationURL(
        for sourceURL: URL,
        pageNumber: Int,
        pageCount: Int,
        format: PDFImageFormat,
        outputDirectory: URL? = nil,
        uniquingIn fileManager: FileManager = .default
    ) -> URL {
        let directory = outputDirectory ?? sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let padWidth = max(String(pageCount).count, 2)
        let padded = String(format: "%0\(padWidth)d", pageNumber)

        var candidate = directory
            .appendingPathComponent("\(baseName)-\(padded)")
            .appendingPathExtension(format.fileExtension)
        var counter = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(padded)-\(counter)")
                .appendingPathExtension(format.fileExtension)
            counter += 1
        }

        return candidate
    }

    @discardableResult
    public func extract(
        sourceURL: URL,
        options: PDFImageExtractionOptions,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> PDFImageExtractionSuccess {
        guard canExtract(sourceURL) else {
            throw PDFImageExtractorError.unsupportedFileType(sourceURL)
        }

        guard let document = PDFDocument(url: sourceURL) else {
            throw PDFImageExtractorError.cannotOpenDocument(sourceURL)
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw PDFImageExtractorError.noPages(sourceURL)
        }

        let scale = CGFloat(options.renderScale)
        var outputURLs: [URL] = []

        for index in 0..<pageCount {
            let pageNumber = index + 1

            guard let page = document.page(at: index),
                  let image = renderPage(page, scale: scale) else {
                throw PDFImageExtractorError.renderFailed(sourceURL, pageNumber: pageNumber)
            }

            let destinationURL = makeDestinationURL(
                for: sourceURL,
                pageNumber: pageNumber,
                pageCount: pageCount,
                format: options.format,
                outputDirectory: outputDirectory,
                uniquingIn: fileManager
            )

            try writeImage(image, to: destinationURL, options: options, fileManager: fileManager)
            outputURLs.append(destinationURL)
        }

        return PDFImageExtractionSuccess(sourceURL: sourceURL, outputURLs: outputURLs)
    }

    public func extract(
        urls: [URL],
        options: PDFImageExtractionOptions,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> PDFImageExtractionReport {
        var successes: [PDFImageExtractionSuccess] = []
        var failures: [PDFImageExtractionFailure] = []

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
                    PDFImageExtractionFailure(
                        sourceURL: url,
                        reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            }
        }

        return PDFImageExtractionReport(successes: successes, failures: failures)
    }

    private func renderPage(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())

        guard width > 0, height > 0 else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        return context.makeImage()
    }

    private func writeImage(
        _ image: CGImage,
        to url: URL,
        options: PDFImageExtractionOptions,
        fileManager: FileManager
    ) throws {
        if options.format == .webp {
            try writeWebPImage(image, to: url, options: options, fileManager: fileManager)
            return
        }

        let type: CFString
        switch options.format {
        case .png:
            type = UTType.png.identifier as CFString
        case .jpeg:
            type = UTType.jpeg.identifier as CFString
        case .webp:
            preconditionFailure("WebP is handled before ImageIO encoding.")
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw PDFImageExtractorError.writeFailed(url)
        }

        var properties: [CFString: Any] = [:]
        if options.format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = options.quality
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw PDFImageExtractorError.writeFailed(url)
        }
    }

    private func writeWebPImage(
        _ image: CGImage,
        to url: URL,
        options: PDFImageExtractionOptions,
        fileManager: FileManager
    ) throws {
        guard let encoderURL = WebPConverter().encoderURL else {
            throw PDFImageExtractorError.webPEncoderUnavailable
        }

        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("UtilitySuitePDF-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let temporaryPNGURL = temporaryDirectory.appendingPathComponent("page.png")
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        try writePNGImage(image, to: temporaryPNGURL)
        try runCWebP(
            encoderURL: encoderURL,
            sourceURL: temporaryPNGURL,
            destinationURL: url,
            qualityPercentage: options.qualityPercentage
        )

        guard fileManager.fileExists(atPath: url.path) else {
            throw PDFImageExtractorError.writeFailed(url)
        }
    }

    private func writePNGImage(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PDFImageExtractorError.writeFailed(url)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw PDFImageExtractorError.writeFailed(url)
        }
    }

    private func runCWebP(
        encoderURL: URL,
        sourceURL: URL,
        destinationURL: URL,
        qualityPercentage: Int
    ) throws {
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
            throw PDFImageExtractorError.webPEncodingFailed(destinationURL, message: output.isEmpty ? "Unknown error" : output)
        }
    }
}
