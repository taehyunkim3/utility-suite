import Foundation

public struct WebPConversionOptions: Sendable, Equatable {
    public var quality: Double
    public var deleteOriginalFile: Bool

    public init(quality: Double = 0.8, deleteOriginalFile: Bool = false) {
        self.quality = min(max(quality, 0), 1)
        self.deleteOriginalFile = deleteOriginalFile
    }

    public init(qualityPercentage: Int, deleteOriginalFile: Bool = false) {
        let clamped = min(max(qualityPercentage, 0), 100)
        self.quality = Double(clamped) / 100
        self.deleteOriginalFile = deleteOriginalFile
    }

    public var qualityPercentage: Int {
        Int((quality * 100).rounded())
    }
}
