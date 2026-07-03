import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WebPDropCore

@MainActor
final class VideoOptimizationViewModel: ObservableObject {
    struct Item: Identifiable, Hashable {
        let url: URL

        var id: String { url.path }
        var filename: String { url.lastPathComponent }
    }

    enum DestinationMode: String, CaseIterable, Identifiable {
        case sameFolder
        case customFolder

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sameFolder:
                return "원본 폴더"
            case .customFolder:
                return "사용자 지정 폴더"
            }
        }
    }

    enum WidthMode: String, CaseIterable, Identifiable {
        case original
        case width1920
        case width1280
        case width720

        var id: String { rawValue }

        var title: String {
            switch self {
            case .original:
                return "원본 유지"
            case .width1920:
                return "1920"
            case .width1280:
                return "1280"
            case .width720:
                return "720"
            }
        }

        var width: Int? {
            switch self {
            case .original:
                return nil
            case .width1920:
                return 1920
            case .width1280:
                return 1280
            case .width720:
                return 720
            }
        }
    }

    enum FPSMode: String, CaseIterable, Identifiable {
        case original
        case fps30
        case fps24

        var id: String { rawValue }

        var title: String {
            switch self {
            case .original:
                return "원본 유지"
            case .fps30:
                return "30 FPS"
            case .fps24:
                return "24 FPS"
            }
        }

        var fps: Int? {
            switch self {
            case .original:
                return nil
            case .fps30:
                return 30
            case .fps24:
                return 24
            }
        }
    }

    @Published var items: [Item] = [] {
        didSet { refreshActionState() }
    }
    @Published var selectedPreset: VideoOptimizationPreset = .landingDesktop {
        didSet { applyPreset(selectedPreset) }
    }
    @Published var widthMode: WidthMode = .width1920
    @Published var fpsMode: FPSMode = .fps30
    @Published var codec: VideoCodec = .h264
    @Published var quality: VideoQualityLevel = .high
    @Published var removeAudio = true
    @Published var fastStart = true
    @Published var useTargetSize = true
    @Published var targetMegabytes: Double = 12
    @Published var posterTime: Double = 1 {
        didSet {
            let roundedTime = min(30, max(0, (posterTime * 10).rounded() / 10))
            if posterTime != roundedTime {
                posterTime = roundedTime
            }
        }
    }
    @Published var destinationMode: DestinationMode = .sameFolder {
        didSet { refreshActionState() }
    }
    @Published var customOutputFolder: URL? {
        didSet { refreshActionState() }
    }
    @Published var isDropTargeted = false
    @Published var isAnalyzing = false
    @Published var isOptimizing = false {
        didSet { refreshActionState() }
    }
    @Published var progressMessage = "MP4/MOV 파일을 드롭하면 영상 정보를 분석합니다."
    @Published var lastReport: VideoOptimizationReport?
    @Published var latestLog: String?
    @Published var progressLogLines: [String] = []
    @Published private(set) var metadataBySourcePath: [String: VideoMetadata] = [:]
    @Published private(set) var failedReasonsBySourcePath: [String: String] = [:]
    @Published private(set) var canOptimize = false

    private let optimizer = VideoOptimizer()

    init() {
        applyPreset(.landingDesktop)
        appendLog("대기 중: MP4/MOV 파일을 드롭하세요.")
        refreshActionState()
    }

    var selectedCountLabel: String {
        "\(items.count)개 선택됨"
    }

    var optimizationAvailable: Bool {
        optimizer.isOptimizationAvailable
    }

    var outputDirectory: URL? {
        switch destinationMode {
        case .sameFolder:
            return nil
        case .customFolder:
            return customOutputFolder
        }
    }

    var latestOutputDirectory: URL? {
        if let customOutputFolder, destinationMode == .customFolder {
            return customOutputFolder
        }

        if let output = lastReport?.successes.first?.destinationURL {
            return output.deletingLastPathComponent()
        }

        return lastReport?.posters.first?.destinationURL.deletingLastPathComponent()
    }

    var summaryText: String? {
        guard let lastReport else {
            return nil
        }

        let posterText = lastReport.posters.isEmpty ? "" : ", 포스터 \(lastReport.posters.count)개"
        return "완료: 영상 \(lastReport.successes.count)개 성공, \(lastReport.failures.count)개 실패\(posterText)"
    }

    func metadata(for item: Item) -> VideoMetadata? {
        metadataBySourcePath[item.url.path]
    }

    func failureReason(for item: Item) -> String? {
        failedReasonsBySourcePath[item.url.path]
    }

    func addFiles(urls: [URL]) {
        let filtered = urls
            .filter { optimizer.canOptimize($0) }
            .map(Item.init(url:))

        let existing = Set(items)
        let newItems = filtered.filter { !existing.contains($0) }

        for item in newItems {
            failedReasonsBySourcePath.removeValue(forKey: item.url.path)
        }

        items.append(contentsOf: newItems)
        items.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }

        if newItems.isEmpty {
            progressMessage = "추가할 수 있는 영상 파일이 없습니다."
            appendLog("지원하지 않는 파일이거나 이미 목록에 있습니다.")
        } else {
            progressMessage = "\(newItems.count)개 영상 파일을 추가했습니다. 분석 중..."
            appendLog("\(newItems.count)개 파일 추가됨. 영상 정보 분석 시작.")
            Task {
                await analyze(items: newItems)
            }
        }
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        metadataBySourcePath.removeValue(forKey: item.url.path)
        failedReasonsBySourcePath.removeValue(forKey: item.url.path)
    }

    func clear() {
        items.removeAll()
        metadataBySourcePath.removeAll()
        failedReasonsBySourcePath.removeAll()
        lastReport = nil
        latestLog = nil
        progressLogLines.removeAll()
        appendLog("선택 목록을 비웠습니다.")
        progressMessage = "선택 목록을 비웠습니다."
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "추가"

        guard panel.runModal() == .OK else {
            return
        }

        addFiles(urls: panel.urls)
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "선택"

        if panel.runModal() == .OK {
            customOutputFolder = panel.url
            progressMessage = "출력 폴더를 \(panel.url?.lastPathComponent ?? "선택한 폴더")로 설정했습니다."
        }
    }

    func optimizeAll() async {
        guard validateBeforeRun() else {
            return
        }

        isOptimizing = true
        lastReport = nil
        latestLog = nil
        progressMessage = "\(selectedPreset.displayName) 프리셋으로 변환 중..."
        appendLog("\(selectedPreset.displayName) 프리셋 변환 시작.")

        let options = makeOptions(outputSuffix: selectedPreset.outputSuffix)
        let outputDirectory = outputDirectory
        var successes: [VideoOptimizationSuccess] = []
        var failures: [VideoOptimizationFailure] = []

        for item in items {
            appendLog("ffmpeg 실행 중: \(item.filename)")
            let result = await Task.detached(priority: .userInitiated) {
                do {
                    return (
                        try VideoOptimizer().optimize(
                            sourceURL: item.url,
                            options: options,
                            outputDirectory: outputDirectory
                        ) as VideoOptimizationSuccess?,
                        nil as String?
                    )
                } catch {
                    return (nil as VideoOptimizationSuccess?, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }.value

            if let success = result.0 {
                successes.append(success)
                appendLog("완료: \(success.destinationURL.lastPathComponent) (\(formatBytesForLog(success.optimizedFileSize)))")
            } else if let reason = result.1 {
                failures.append(VideoOptimizationFailure(sourceURL: item.url, reason: reason))
                appendLog("실패: \(item.filename) - \(reason)")
            }
        }

        let report = VideoOptimizationReport(successes: successes, failures: failures, posters: [])

        apply(report: report)
        isOptimizing = false
        appendLog("변환 종료: 성공 \(report.successes.count)개, 실패 \(report.failures.count)개.")
        progressMessage = report.failures.isEmpty ? "영상 최적화가 완료되었습니다." : "일부 영상 최적화에 실패했습니다."
    }

    func createLandingPackage() async {
        guard validateBeforeRun() else {
            return
        }

        isOptimizing = true
        lastReport = nil
        latestLog = nil
        progressMessage = "PC/모바일 MP4와 poster.webp를 일괄 출력 중..."
        appendLog("랜딩 패키지 출력 시작.")

        let outputDirectory = outputDirectory
        var successes: [VideoOptimizationSuccess] = []
        var failures: [VideoOptimizationFailure] = []
        var posters: [PosterExtractionSuccess] = []

        for item in items {
            appendLog("패키지 시작: \(item.filename)")

            let desktopOptions = VideoOptimizationOptions(
                codec: .h264,
                width: 1920,
                fps: 30,
                removeAudio: true,
                fastStart: true,
                quality: .high,
                targetMegabytes: 12,
                outputSuffix: "pc"
            )
            appendLog("PC MP4 변환 중: \(item.filename)")
            let desktopResult = await optimize(item: item, options: desktopOptions, outputDirectory: outputDirectory)
            if let success = desktopResult.0 {
                successes.append(success)
                appendLog("PC 완료: \(success.destinationURL.lastPathComponent) (\(formatBytesForLog(success.optimizedFileSize)))")
            } else if let reason = desktopResult.1 {
                failures.append(VideoOptimizationFailure(sourceURL: item.url, reason: reason))
                appendLog("PC 실패: \(item.filename) - \(reason)")
            }

            let mobileOptions = VideoOptimizationOptions(
                codec: .h264,
                width: 1280,
                fps: 30,
                removeAudio: true,
                fastStart: true,
                quality: .high,
                targetMegabytes: 5,
                outputSuffix: "mobile"
            )
            appendLog("모바일 MP4 변환 중: \(item.filename)")
            let mobileResult = await optimize(item: item, options: mobileOptions, outputDirectory: outputDirectory)
            if let success = mobileResult.0 {
                successes.append(success)
                appendLog("모바일 완료: \(success.destinationURL.lastPathComponent) (\(formatBytesForLog(success.optimizedFileSize)))")
            } else if let reason = mobileResult.1 {
                failures.append(VideoOptimizationFailure(sourceURL: item.url, reason: reason))
                appendLog("모바일 실패: \(item.filename) - \(reason)")
            }

            appendLog("poster.webp 추출 중: \(item.filename)")
            let posterResult = await extractPoster(item: item, outputDirectory: outputDirectory)
            if let poster = posterResult.0 {
                posters.append(poster)
                appendLog("포스터 완료: \(poster.destinationURL.lastPathComponent) (\(formatBytesForLog(poster.fileSize)))")
            } else if let reason = posterResult.1 {
                failures.append(VideoOptimizationFailure(sourceURL: item.url, reason: reason))
                appendLog("포스터 실패: \(item.filename) - \(reason)")
            }
        }

        let report = VideoOptimizationReport(successes: successes, failures: failures, posters: posters)

        apply(report: report)
        isOptimizing = false
        appendLog("랜딩 패키지 종료: 영상 \(report.successes.count)개, 포스터 \(report.posters.count)개, 실패 \(report.failures.count)개.")
        progressMessage = report.failures.isEmpty ? "랜딩 패키지 출력이 완료되었습니다." : "일부 랜딩 패키지 출력에 실패했습니다."
    }

    func extractPosters() async {
        guard validateBeforeRun() else {
            return
        }

        isOptimizing = true
        lastReport = nil
        latestLog = nil
        progressMessage = "poster.webp 추출 중..."
        appendLog("포스터 추출 시작.")

        let outputDirectory = outputDirectory
        var failures: [VideoOptimizationFailure] = []
        var posters: [PosterExtractionSuccess] = []

        for item in items {
            appendLog("poster.webp 추출 중: \(item.filename)")
            let result = await extractPoster(item: item, outputDirectory: outputDirectory)
            if let poster = result.0 {
                posters.append(poster)
                appendLog("포스터 완료: \(poster.destinationURL.lastPathComponent) (\(formatBytesForLog(poster.fileSize)))")
            } else if let reason = result.1 {
                failures.append(VideoOptimizationFailure(sourceURL: item.url, reason: reason))
                appendLog("포스터 실패: \(item.filename) - \(reason)")
            }
        }

        let report = VideoOptimizationReport(successes: [], failures: failures, posters: posters)

        apply(report: report)
        isOptimizing = false
        appendLog("포스터 추출 종료: 성공 \(report.posters.count)개, 실패 \(report.failures.count)개.")
        progressMessage = report.failures.isEmpty ? "포스터 이미지 추출이 완료되었습니다." : "일부 포스터 이미지 추출에 실패했습니다."
    }

    func openLatestOutputFolder() {
        guard let latestOutputDirectory else {
            return
        }

        NSWorkspace.shared.open(latestOutputDirectory)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func applyPreset(_ preset: VideoOptimizationPreset) {
        widthMode = widthMode(for: preset.defaultWidth)
        fpsMode = fpsMode(for: preset.defaultFPS)
        quality = preset.defaultQuality
        removeAudio = true
        fastStart = true
        useTargetSize = preset.suggestedTargetMegabytes != nil
        targetMegabytes = preset.suggestedTargetMegabytes ?? targetMegabytes
    }

    private func analyze(items targetItems: [Item]) async {
        guard optimizer.ffprobeURL != nil else {
            progressMessage = "ffprobe를 찾지 못했습니다. brew install ffmpeg 로 설치하세요."
            appendLog("ffprobe 없음: brew install ffmpeg 필요.")
            return
        }

        isAnalyzing = true

        for item in targetItems {
            appendLog("ffprobe 분석 중: \(item.filename)")
            let result = await Task.detached(priority: .userInitiated) {
                do {
                    return (try VideoOptimizer().analyze(sourceURL: item.url) as VideoMetadata?, nil as String?)
                } catch {
                    return (nil as VideoMetadata?, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }.value

            if let metadata = result.0 {
                metadataBySourcePath[item.url.path] = metadata
                failedReasonsBySourcePath.removeValue(forKey: item.url.path)
                appendLog("분석 완료: \(item.filename) - \(metadata.resolutionText), \(formatBytesForLog(metadata.fileSize)), \(formatBitrateForLog(metadata.averageBitrate))")
            } else if let reason = result.1 {
                failedReasonsBySourcePath[item.url.path] = reason
                appendLog("분석 실패: \(item.filename) - \(reason)")
            }
        }

        isAnalyzing = false
        appendLog("영상 정보 분석 종료.")
        progressMessage = "영상 정보 분석이 완료되었습니다."
    }

    private func validateBeforeRun() -> Bool {
        guard optimizationAvailable else {
            progressMessage = "ffmpeg/ffprobe를 찾지 못했습니다. brew install ffmpeg 로 설치하세요."
            return false
        }

        guard !items.isEmpty else {
            progressMessage = "변환할 영상 파일이 없습니다."
            return false
        }

        if destinationMode == .customFolder && customOutputFolder == nil {
            progressMessage = "출력 폴더를 먼저 선택하세요."
            return false
        }

        return true
    }

    private func makeOptions(outputSuffix: String) -> VideoOptimizationOptions {
        VideoOptimizationOptions(
            codec: codec,
            width: widthMode.width,
            fps: fpsMode.fps,
            removeAudio: removeAudio,
            fastStart: fastStart,
            quality: quality,
            targetMegabytes: useTargetSize ? targetMegabytes : nil,
            outputSuffix: outputSuffix
        )
    }

    private func apply(report: VideoOptimizationReport) {
        lastReport = report
        latestLog = (report.successes.map(\.log) + report.posters.map(\.log))
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        for success in report.successes {
            metadataBySourcePath[success.sourceURL.path] = success.metadata
            failedReasonsBySourcePath.removeValue(forKey: success.sourceURL.path)
        }

        for failure in report.failures {
            failedReasonsBySourcePath[failure.sourceURL.path] = failure.reason
        }
    }

    private func optimize(
        item: Item,
        options: VideoOptimizationOptions,
        outputDirectory: URL?
    ) async -> (VideoOptimizationSuccess?, String?) {
        await Task.detached(priority: .userInitiated) {
            do {
                return (
                    try VideoOptimizer().optimize(
                        sourceURL: item.url,
                        options: options,
                        outputDirectory: outputDirectory
                    ) as VideoOptimizationSuccess?,
                    nil as String?
                )
            } catch {
                return (nil as VideoOptimizationSuccess?, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }.value
    }

    private func extractPoster(
        item: Item,
        outputDirectory: URL?
    ) async -> (PosterExtractionSuccess?, String?) {
        let time = posterTime

        return await Task.detached(priority: .userInitiated) {
            do {
                return (
                    try VideoOptimizer().extractPoster(
                        sourceURL: item.url,
                        time: time,
                        outputDirectory: outputDirectory
                    ) as PosterExtractionSuccess?,
                    nil as String?
                )
            } catch {
                return (nil as PosterExtractionSuccess?, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }.value
    }

    private func appendLog(_ message: String) {
        let timestamp = Date().formatted(.dateTime.hour().minute().second())
        progressLogLines.append("[\(timestamp)] \(message)")

        if progressLogLines.count > 200 {
            progressLogLines.removeFirst(progressLogLines.count - 200)
        }
    }

    private func formatBytesForLog(_ bytes: Int64?) -> String {
        guard let bytes else {
            return "-"
        }

        let megabytes = Double(bytes) / 1_024 / 1_024
        return "\(megabytes.formatted(.number.precision(.fractionLength(1))))MB"
    }

    private func formatBitrateForLog(_ bitsPerSecond: Int64?) -> String {
        guard let bitsPerSecond else {
            return "-"
        }

        let megabits = Double(bitsPerSecond) / 1_000_000
        return "\(megabits.formatted(.number.precision(.fractionLength(1))))Mbps"
    }

    private func refreshActionState() {
        canOptimize = !items.isEmpty
            && !isOptimizing
            && (destinationMode == .sameFolder || customOutputFolder != nil)
    }

    private func widthMode(for width: Int?) -> WidthMode {
        switch width {
        case 1920:
            return .width1920
        case 1280:
            return .width1280
        case 720:
            return .width720
        default:
            return .original
        }
    }

    private func fpsMode(for fps: Int?) -> FPSMode {
        switch fps {
        case 30:
            return .fps30
        case 24:
            return .fps24
        default:
            return .original
        }
    }
}
