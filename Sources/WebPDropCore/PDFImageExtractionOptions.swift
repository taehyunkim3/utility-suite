import Foundation

public enum PDFImageFormat: String, Sendable, CaseIterable, Identifiable {
    case png
    case jpeg

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        }
    }

    public var displayName: String {
        switch self {
        case .png:
            return "PNG (무손실)"
        case .jpeg:
            return "JPEG"
        }
    }

    public var supportsQuality: Bool {
        self == .jpeg
    }
}

public struct PDFImageExtractionOptions: Sendable, Equatable {
    public static let availableDPIs = [72, 150, 200, 300, 600]

    public var format: PDFImageFormat
    public var dpi: Int
    public var jpegQuality: Double

    public init(format: PDFImageFormat = .png, dpi: Int = 150, jpegQuality: Double = 0.85) {
        self.format = format
        self.dpi = min(max(dpi, 36), 1200)
        self.jpegQuality = min(max(jpegQuality, 0), 1)
    }

    /// 렌더링 배율 (72 DPI 기준).
    public var renderScale: Double {
        Double(dpi) / 72.0
    }

    public var jpegQualityPercentage: Int {
        Int((jpegQuality * 100).rounded())
    }
}
