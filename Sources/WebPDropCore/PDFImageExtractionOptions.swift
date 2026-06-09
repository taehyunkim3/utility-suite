import Foundation

public enum PDFImageFormat: String, Sendable, CaseIterable, Identifiable {
    case png
    case jpeg
    case webp

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        case .webp:
            return "webp"
        }
    }

    public var displayName: String {
        switch self {
        case .png:
            return "PNG (무손실)"
        case .jpeg:
            return "JPEG"
        case .webp:
            return "WebP"
        }
    }

    public var supportsQuality: Bool {
        self == .jpeg || self == .webp
    }
}

public struct PDFImageExtractionOptions: Sendable, Equatable {
    public static let availableDPIs = [72, 150, 200, 300, 600]

    public var format: PDFImageFormat
    public var dpi: Int
    public var quality: Double

    public init(format: PDFImageFormat = .png, dpi: Int = 150, quality: Double = 0.85) {
        self.format = format
        self.dpi = min(max(dpi, 36), 1200)
        self.quality = min(max(quality, 0), 1)
    }

    public init(format: PDFImageFormat = .png, dpi: Int = 150, jpegQuality: Double) {
        self.init(format: format, dpi: dpi, quality: jpegQuality)
    }

    /// 렌더링 배율 (72 DPI 기준).
    public var renderScale: Double {
        Double(dpi) / 72.0
    }

    public var qualityPercentage: Int {
        Int((quality * 100).rounded())
    }

    public var jpegQualityPercentage: Int {
        qualityPercentage
    }
}
