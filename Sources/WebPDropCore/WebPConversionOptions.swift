import Foundation

public struct WebPConversionOptions: Sendable, Equatable {
    public var quality: Double

    public init(quality: Double = 0.8) {
        self.quality = min(max(quality, 0), 1)
    }

    public init(qualityPercentage: Int) {
        let clamped = min(max(qualityPercentage, 0), 100)
        self.quality = Double(clamped) / 100
    }

    public var qualityPercentage: Int {
        Int((quality * 100).rounded())
    }
}
