import AppKit
import Combine
import Foundation
import WebPDropCore

@MainActor
final class FileRenameViewModel: ObservableObject {
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
    @Published var prefix = "" {
        didSet { refreshActionState() }
    }
    @Published var suffix = "" {
        didSet { refreshActionState() }
    }
    @Published var includeOriginalName = true {
        didSet { refreshActionState() }
    }
    @Published var includeSequence = false {
        didSet { refreshActionState() }
    }
    @Published var sequenceStart = 1 {
        didSet { refreshActionState() }
    }
    @Published var sequenceDigits = 3 {
        didSet { refreshActionState() }
    }
    @Published var sequenceSeparator = "_"
    @Published var sequencePlacement: FileRenameSequencePlacement = .afterName {
        didSet { refreshActionState() }
    }
    @Published var operation: FileRenameOperation = .createCopy {
        didSet { refreshActionState() }
    }
    @Published var destinationMode: DestinationMode = .sameFolder {
        didSet { refreshActionState() }
    }
    @Published var customOutputFolder: URL? {
        didSet { refreshActionState() }
    }
    @Published var isDropTargeted = false
    @Published var isProcessing = false {
        didSet { refreshActionState() }
    }
    @Published var progressMessage = "이름을 바꿀 파일을 드롭하거나 선택하세요."
    @Published var lastReport: BatchFileRenameReport?
    @Published private(set) var completedSourcePaths: Set<String> = []
    @Published private(set) var failedReasonsBySourcePath: [String: String] = [:]
    @Published private(set) var canProcess = false

    private let renamer = FileRenamer()

    init() {
        refreshActionState()
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
        guard operation == .createCopy else {
            return nil
        }

        switch destinationMode {
        case .sameFolder:
            return nil
        case .customFolder:
            return customOutputFolder
        }
    }

    var latestOutputDirectory: URL? {
        if operation == .createCopy,
           destinationMode == .customFolder,
           let customOutputFolder {
            return customOutputFolder
        }

        return lastReport?.successes.first?.destinationURL.deletingLastPathComponent()
    }

    var summaryText: String? {
        guard let lastReport else {
            return nil
        }

        let successCount = lastReport.successes.count
        let failureCount = lastReport.failures.count
        switch operation {
        case .renameOriginal:
            return "이름 변경 완료: \(successCount)개 성공, \(failureCount)개 실패"
        case .createCopy:
            return "복사본 생성 완료: \(successCount)개 성공, \(failureCount)개 실패"
        }
    }

    var options: FileRenameOptions {
        FileRenameOptions(
            prefix: prefix,
            suffix: suffix,
            includeOriginalName: includeOriginalName,
            includeSequence: includeSequence,
            sequenceStart: sequenceStart,
            sequenceDigits: sequenceDigits,
            sequenceSeparator: sequenceSeparator,
            sequencePlacement: sequencePlacement,
            operation: operation
        )
    }

    var operationTitle: String {
        switch operation {
        case .renameOriginal:
            return "원본 이름 변경"
        case .createCopy:
            return "복사본 생성"
        }
    }

    var previewItems: [(source: String, destination: String)] {
        items.prefix(5).enumerated().map { index, item in
            let destinationURL = try? renamer.makeDestinationURL(
                for: item.url,
                itemIndex: index,
                options: options,
                outputDirectory: outputDirectory
            )
            return (item.filename, destinationURL?.lastPathComponent ?? "새 파일명 없음")
        }
    }

    func addFiles(urls: [URL]) {
        let filtered = urls
            .filter { isFile($0) }
            .map(Item.init(url:))

        let existing = Set(items)
        let newItems = filtered.filter { !existing.contains($0) }

        for item in newItems {
            completedSourcePaths.remove(item.url.path)
            failedReasonsBySourcePath.removeValue(forKey: item.url.path)
        }

        items.append(contentsOf: newItems)
        items.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }

        if newItems.isEmpty {
            progressMessage = "추가할 수 있는 파일이 없습니다."
        } else {
            progressMessage = "\(newItems.count)개 파일을 추가했습니다."
        }
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        completedSourcePaths.remove(item.url.path)
        failedReasonsBySourcePath.removeValue(forKey: item.url.path)
    }

    func clear() {
        items.removeAll()
        completedSourcePaths.removeAll()
        failedReasonsBySourcePath.removeAll()
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
        }
        progressMessage = "완료된 항목을 목록에서 제거했습니다."
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
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

    func processAll() async {
        guard !items.isEmpty else {
            progressMessage = "처리할 파일이 없습니다."
            return
        }

        guard hasValidNamingRule else {
            progressMessage = "새 파일명이 비어 있습니다. 기존 이름 유지, 접두어/접미어, 순번 중 하나를 사용하세요."
            return
        }

        if operation == .createCopy && destinationMode == .customFolder && customOutputFolder == nil {
            progressMessage = "출력 폴더를 먼저 선택하세요."
            return
        }

        isProcessing = true
        lastReport = nil
        progressMessage = operation == .renameOriginal ? "파일 이름 변경 중..." : "복사본 생성 중..."

        let sourceURLs = items.map(\.url)
        let options = options
        let outputDirectory = outputDirectory

        let report = await Task.detached(priority: .userInitiated) {
            FileRenamer().rename(
                urls: sourceURLs,
                options: options,
                outputDirectory: outputDirectory
            )
        }.value

        lastReport = report
        let completedPaths = Set(report.successes.map(\.sourceURL.path))
        completedSourcePaths.formUnion(completedPaths)

        for path in completedPaths {
            failedReasonsBySourcePath.removeValue(forKey: path)
        }

        for failure in report.failures {
            failedReasonsBySourcePath[failure.sourceURL.path] = failure.reason
        }

        isProcessing = false

        if report.failures.isEmpty {
            progressMessage = "모든 파일 처리가 완료되었습니다."
        } else {
            progressMessage = "일부 파일 처리에 실패했습니다."
        }
    }

    func isCompleted(_ item: Item) -> Bool {
        completedSourcePaths.contains(item.url.path)
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

    private var hasValidNamingRule: Bool {
        includeOriginalName
            || includeSequence
            || !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func refreshActionState() {
        canProcess = !items.isEmpty
            && !isProcessing
            && hasValidNamingRule
            && (operation == .renameOriginal || destinationMode == .sameFolder || customOutputFolder != nil)
    }

    private func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }
}
