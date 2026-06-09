import AppKit
import Combine
import Foundation
import WebPDropCore

@MainActor
final class PDFExtractionViewModel: ObservableObject {
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

    @Published var items: [Item] = [] {
        didSet { refreshActionState() }
    }
    @Published var outputFormat: PDFImageFormat = .png
    @Published var dpi: Int = 150
    @Published var imageQuality: Double = 0.85
    @Published var destinationMode: DestinationMode = .sameFolder {
        didSet { refreshActionState() }
    }
    @Published var customOutputFolder: URL? {
        didSet { refreshActionState() }
    }
    @Published var isDropTargeted = false
    @Published var isExtracting = false {
        didSet { refreshActionState() }
    }
    @Published var progressMessage = "PDF 파일을 드롭하거나 선택하세요."
    @Published var lastReport: PDFImageExtractionReport?
    @Published private(set) var completedSourcePaths: Set<String> = []
    @Published private(set) var failedReasonsBySourcePath: [String: String] = [:]
    @Published private(set) var pageCountsBySourcePath: [String: Int] = [:]
    @Published private(set) var canExtract = false

    private let extractor = PDFImageExtractor()

    init() {
        refreshActionState()
    }

    var availableDPIs: [Int] {
        PDFImageExtractionOptions.availableDPIs
    }

    var imageQualityPercentage: Int {
        Int((imageQuality * 100).rounded())
    }

    var selectedCountLabel: String {
        "\(items.count)개 선택됨"
    }

    var completedCount: Int {
        items.filter { completedSourcePaths.contains($0.url.path) }.count
    }

    var hasCompletedItems: Bool {
        completedCount > 0
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

        return lastReport?.successes.first?.outputDirectory
    }

    var summaryText: String? {
        guard let lastReport else {
            return nil
        }

        let successCount = lastReport.successes.count
        let failureCount = lastReport.failures.count
        let imageCount = lastReport.totalImageCount
        return "추출 완료: \(successCount)개 PDF, 총 \(imageCount)장 이미지, \(failureCount)개 실패"
    }

    func addFiles(urls: [URL]) {
        let filtered = urls
            .filter { extractor.canExtract($0) }
            .map(Item.init(url:))

        let existing = Set(items)
        let newItems = filtered.filter { !existing.contains($0) }

        for item in newItems {
            completedSourcePaths.remove(item.url.path)
            failedReasonsBySourcePath.removeValue(forKey: item.url.path)
            pageCountsBySourcePath.removeValue(forKey: item.url.path)
        }

        items.append(contentsOf: newItems)
        items.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }

        if newItems.isEmpty {
            progressMessage = "추가할 수 있는 PDF 파일이 없습니다."
        } else {
            progressMessage = "\(newItems.count)개 파일을 추가했습니다."
        }
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        completedSourcePaths.remove(item.url.path)
        failedReasonsBySourcePath.removeValue(forKey: item.url.path)
        pageCountsBySourcePath.removeValue(forKey: item.url.path)
    }

    func clear() {
        items.removeAll()
        completedSourcePaths.removeAll()
        failedReasonsBySourcePath.removeAll()
        pageCountsBySourcePath.removeAll()
        lastReport = nil
        progressMessage = "선택 목록을 비웠습니다."
    }

    func clearCompleted() {
        let completedPaths = completedSourcePaths
        guard !completedPaths.isEmpty else {
            return
        }

        items.removeAll { completedPaths.contains($0.url.path) }
        completedSourcePaths.removeAll()
        for path in completedPaths {
            failedReasonsBySourcePath.removeValue(forKey: path)
            pageCountsBySourcePath.removeValue(forKey: path)
        }
        progressMessage = "완료된 항목을 목록에서 제거했습니다."
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
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

    func extractAll() async {
        guard !items.isEmpty else {
            progressMessage = "추출할 파일이 없습니다."
            return
        }

        if destinationMode == .customFolder && customOutputFolder == nil {
            progressMessage = "출력 폴더를 먼저 선택하세요."
            return
        }

        isExtracting = true
        lastReport = nil
        progressMessage = "PDF를 이미지로 추출 중..."

        let sourceURLs = items.map(\.url)
        let options = PDFImageExtractionOptions(
            format: outputFormat,
            dpi: dpi,
            quality: imageQuality
        )
        let outputDirectory = outputDirectory

        let report = await Task.detached(priority: .userInitiated) {
            PDFImageExtractor().extract(
                urls: sourceURLs,
                options: options,
                outputDirectory: outputDirectory
            )
        }.value

        lastReport = report

        let completedPaths = Set(report.successes.map(\.sourceURL.path))
        completedSourcePaths.formUnion(completedPaths)

        for success in report.successes {
            pageCountsBySourcePath[success.sourceURL.path] = success.pageCount
            failedReasonsBySourcePath.removeValue(forKey: success.sourceURL.path)
        }

        for failure in report.failures {
            failedReasonsBySourcePath[failure.sourceURL.path] = failure.reason
        }

        isExtracting = false

        if report.failures.isEmpty {
            progressMessage = "모든 PDF의 이미지 추출이 완료되었습니다."
        } else {
            progressMessage = "일부 PDF는 이미지 추출에 실패했습니다."
        }
    }

    func isCompleted(_ item: Item) -> Bool {
        completedSourcePaths.contains(item.url.path)
    }

    func pageCount(for item: Item) -> Int? {
        pageCountsBySourcePath[item.url.path]
    }

    func failureReason(for item: Item) -> String? {
        failedReasonsBySourcePath[item.url.path]
    }

    func openLatestOutputFolder() {
        guard let latestOutputDirectory else {
            return
        }

        NSWorkspace.shared.open(latestOutputDirectory)
    }

    private func refreshActionState() {
        canExtract = !items.isEmpty
            && !isExtracting
            && (destinationMode == .sameFolder || customOutputFolder != nil)
    }
}
