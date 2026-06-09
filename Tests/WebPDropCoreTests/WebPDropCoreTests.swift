import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WebPDropCore

@Test func makeDestinationURLAddsSuffixWhenNeeded() throws {
    let converter = WebPConverter()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let source = directory.appendingPathComponent("sample.png")
    FileManager.default.createFile(atPath: source.path, contents: Data(), attributes: nil)

    let first = converter.makeDestinationURL(for: source, outputDirectory: directory)
    #expect(first.lastPathComponent == "sample.webp")

    FileManager.default.createFile(atPath: first.path, contents: Data(), attributes: nil)

    let second = converter.makeDestinationURL(for: source, outputDirectory: directory)
    #expect(second.lastPathComponent == "sample-1.webp")
}

@Test func convertPNGIntoWebP() throws {
    let converter = WebPConverter()
    #expect(converter.isEncodingAvailable)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let source = directory.appendingPathComponent("fixture.png")
    try writeTestPNG(to: source)

    let result = try converter.convert(
        sourceURL: source,
        options: WebPConversionOptions(qualityPercentage: 75),
        outputDirectory: directory
    )

    #expect(result.destinationURL.pathExtension == "webp")
    #expect(FileManager.default.fileExists(atPath: result.destinationURL.path))
    #expect(result.convertedFileSize != nil)
}

@Test func audioDestinationURLUsesFormatExtension() throws {
    let extractor = AudioExtractor()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let source = directory.appendingPathComponent("recording.mp4")
    FileManager.default.createFile(atPath: source.path, contents: Data(), attributes: nil)

    let first = extractor.makeDestinationURL(for: source, format: .mp3, outputDirectory: directory)
    #expect(first.lastPathComponent == "recording.mp3")

    FileManager.default.createFile(atPath: first.path, contents: Data(), attributes: nil)

    let second = extractor.makeDestinationURL(for: source, format: .mp3, outputDirectory: directory)
    #expect(second.lastPathComponent == "recording-1.mp3")

    let m4a = extractor.makeDestinationURL(for: source, format: .m4a, outputDirectory: directory)
    #expect(m4a.lastPathComponent == "recording.m4a")
}

@Test func audioExtractorRecognizesSupportedTypes() {
    let extractor = AudioExtractor()
    #expect(extractor.canExtract(URL(fileURLWithPath: "/tmp/clip.mp4")))
    #expect(extractor.canExtract(URL(fileURLWithPath: "/tmp/clip.MOV")))
    #expect(extractor.canExtract(URL(fileURLWithPath: "/tmp/audio.m4a")))
    #expect(!extractor.canExtract(URL(fileURLWithPath: "/tmp/image.png")))
}

@Test func audioOptionsBuildExpectedFFmpegArguments() {
    let mp3 = AudioExtractionOptions(format: .mp3, bitrateKbps: 256)
    #expect(mp3.ffmpegAudioArguments() == ["-c:a", "libmp3lame", "-b:a", "256k"])

    let m4a = AudioExtractionOptions(format: .m4a, bitrateKbps: 192)
    #expect(m4a.ffmpegAudioArguments() == ["-c:a", "aac", "-b:a", "192k"])

    let wav = AudioExtractionOptions(format: .wav)
    #expect(wav.ffmpegAudioArguments() == ["-c:a", "pcm_s16le"])

    let flac = AudioExtractionOptions(format: .flac)
    #expect(flac.ffmpegAudioArguments() == ["-c:a", "flac"])
}

private func writeTestPNG(to url: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: nil,
        width: 24,
        height: 24,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw TestImageError.contextCreationFailed
    }

    context.setFillColor(red: 0.17, green: 0.55, blue: 0.83, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))

    guard let image = context.makeImage() else {
        throw TestImageError.imageCreationFailed
    }

    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TestImageError.destinationCreationFailed
    }

    CGImageDestinationAddImage(destination, image, nil)

    guard CGImageDestinationFinalize(destination) else {
        throw TestImageError.destinationFinalizeFailed
    }
}

enum TestImageError: Error {
    case contextCreationFailed
    case imageCreationFailed
    case destinationCreationFailed
    case destinationFinalizeFailed
}
