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

@Test func converterFindsSupportedImagesInsideFolders() throws {
    let converter = WebPConverter()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let nested = directory.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    let rootImage = directory.appendingPathComponent("root.png")
    let nestedImage = nested.appendingPathComponent("nested.JPG")
    let unsupported = nested.appendingPathComponent("notes.txt")
    FileManager.default.createFile(atPath: rootImage.path, contents: Data(), attributes: nil)
    FileManager.default.createFile(atPath: nestedImage.path, contents: Data(), attributes: nil)
    FileManager.default.createFile(atPath: unsupported.path, contents: Data(), attributes: nil)

    let files = converter.convertibleFiles(from: [directory])

    #expect(Set(files.map(\.lastPathComponent)) == Set(["root.png", "nested.JPG"]))
    #expect(files.count == 2)
}

@Test func convertPNGIntoWebPAndDeletesOriginalWhenRequested() throws {
    let converter = WebPConverter()
    #expect(converter.isEncodingAvailable)

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let source = directory.appendingPathComponent("delete-me.png")
    try writeTestPNG(to: source)

    let result = try converter.convert(
        sourceURL: source,
        options: WebPConversionOptions(qualityPercentage: 75, deleteOriginalFile: true),
        outputDirectory: directory
    )

    #expect(FileManager.default.fileExists(atPath: result.destinationURL.path))
    #expect(!FileManager.default.fileExists(atPath: source.path))
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

@Test func pdfDestinationURLPadsPageNumber() throws {
    let extractor = PDFImageExtractor()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let source = directory.appendingPathComponent("report.pdf")

    let first = extractor.makeDestinationURL(for: source, pageNumber: 1, pageCount: 9, format: .png, outputDirectory: directory)
    #expect(first.lastPathComponent == "report-01.png")

    let large = extractor.makeDestinationURL(for: source, pageNumber: 7, pageCount: 120, format: .jpeg, outputDirectory: directory)
    #expect(large.lastPathComponent == "report-007.jpg")

    let webp = extractor.makeDestinationURL(for: source, pageNumber: 3, pageCount: 12, format: .webp, outputDirectory: directory)
    #expect(webp.lastPathComponent == "report-03.webp")
}

@Test func pdfExtractorRecognizesSupportedTypes() {
    let extractor = PDFImageExtractor()
    #expect(extractor.canExtract(URL(fileURLWithPath: "/tmp/file.pdf")))
    #expect(extractor.canExtract(URL(fileURLWithPath: "/tmp/file.PDF")))
    #expect(!extractor.canExtract(URL(fileURLWithPath: "/tmp/file.png")))
}

@Test func pdfExtractionProducesOneImagePerPage() throws {
    let extractor = PDFImageExtractor()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let source = directory.appendingPathComponent("multipage.pdf")
    try writeTestPDF(to: source, pageCount: 3)

    let result = try extractor.extract(
        sourceURL: source,
        options: PDFImageExtractionOptions(format: .png, dpi: 72),
        outputDirectory: directory
    )

    #expect(result.pageCount == 3)
    for url in result.outputURLs {
        #expect(url.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Test func pdfExtractionProducesWebPImages() throws {
    let extractor = PDFImageExtractor()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let source = directory.appendingPathComponent("webp-pages.pdf")
    try writeTestPDF(to: source, pageCount: 2)

    let result = try extractor.extract(
        sourceURL: source,
        options: PDFImageExtractionOptions(format: .webp, dpi: 72, quality: 0.7),
        outputDirectory: directory
    )

    #expect(result.pageCount == 2)
    for url in result.outputURLs {
        #expect(url.pathExtension == "webp")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Test func fileRenamerBuildsNameWithPrefixSuffixAndSequence() throws {
    let renamer = FileRenamer()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let source = directory.appendingPathComponent("sample image.png")
    FileManager.default.createFile(atPath: source.path, contents: Data(), attributes: nil)

    let options = FileRenameOptions(
        prefix: "new-",
        suffix: "-done",
        includeOriginalName: true,
        includeSequence: true,
        sequenceStart: 7,
        sequenceDigits: 4,
        sequenceSeparator: "_",
        sequencePlacement: .afterName,
        operation: .createCopy
    )

    let destination = try renamer.makeDestinationURL(for: source, itemIndex: 2, options: options)
    #expect(destination.lastPathComponent == "new-sample image_0009-done.png")
}

@Test func fileRenamerCanCreateCopyWithoutOriginalName() throws {
    let renamer = FileRenamer()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let source = directory.appendingPathComponent("original.txt")
    try "hello".write(to: source, atomically: true, encoding: .utf8)

    let options = FileRenameOptions(
        prefix: "asset-",
        includeOriginalName: false,
        includeSequence: true,
        sequenceStart: 1,
        sequenceDigits: 2,
        operation: .createCopy
    )

    let result = try renamer.rename(sourceURL: source, itemIndex: 0, options: options)

    #expect(result.destinationURL.lastPathComponent == "asset-01.txt")
    #expect(FileManager.default.fileExists(atPath: source.path))
    #expect(FileManager.default.fileExists(atPath: result.destinationURL.path))
}

@Test func fileRenamerCanRenameOriginal() throws {
    let renamer = FileRenamer()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let source = directory.appendingPathComponent("draft.md")
    try "hello".write(to: source, atomically: true, encoding: .utf8)

    let options = FileRenameOptions(
        suffix: "-final",
        operation: .renameOriginal
    )

    let result = try renamer.rename(sourceURL: source, itemIndex: 0, options: options)

    #expect(result.destinationURL.lastPathComponent == "draft-final.md")
    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(FileManager.default.fileExists(atPath: result.destinationURL.path))
}

private func writeTestPDF(to url: URL, pageCount: Int) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 280)

    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        throw TestImageError.contextCreationFailed
    }

    for index in 0..<pageCount {
        context.beginPDFPage(nil)
        let shade = CGFloat(index + 1) / CGFloat(pageCount + 1)
        context.setFillColor(red: shade, green: 0.4, blue: 0.7, alpha: 1)
        context.fill(mediaBox)
        context.endPDFPage()
    }

    context.closePDF()
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
