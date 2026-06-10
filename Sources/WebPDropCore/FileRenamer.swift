import Foundation

public enum FileRenameOperation: String, CaseIterable, Identifiable, Sendable {
    case renameOriginal
    case createCopy

    public var id: String { rawValue }
}

public enum FileRenameSequencePlacement: String, CaseIterable, Identifiable, Sendable {
    case beforeName
    case afterName

    public var id: String { rawValue }
}

public struct FileRenameOptions: Sendable, Equatable {
    public var prefix: String
    public var suffix: String
    public var includeOriginalName: Bool
    public var includeSequence: Bool
    public var sequenceStart: Int
    public var sequenceDigits: Int
    public var sequenceSeparator: String
    public var sequencePlacement: FileRenameSequencePlacement
    public var operation: FileRenameOperation

    public init(
        prefix: String = "",
        suffix: String = "",
        includeOriginalName: Bool = true,
        includeSequence: Bool = false,
        sequenceStart: Int = 1,
        sequenceDigits: Int = 3,
        sequenceSeparator: String = "_",
        sequencePlacement: FileRenameSequencePlacement = .afterName,
        operation: FileRenameOperation = .createCopy
    ) {
        self.prefix = prefix
        self.suffix = suffix
        self.includeOriginalName = includeOriginalName
        self.includeSequence = includeSequence
        self.sequenceStart = sequenceStart
        self.sequenceDigits = sequenceDigits
        self.sequenceSeparator = sequenceSeparator
        self.sequencePlacement = sequencePlacement
        self.operation = operation
    }
}

public struct FileRenameSuccess: Sendable, Equatable {
    public let sourceURL: URL
    public let destinationURL: URL
    public let operation: FileRenameOperation
}

public struct FileRenameFailure: Sendable, Equatable {
    public let sourceURL: URL
    public let reason: String
}

public struct BatchFileRenameReport: Sendable, Equatable {
    public let successes: [FileRenameSuccess]
    public let failures: [FileRenameFailure]

    public var attemptedCount: Int {
        successes.count + failures.count
    }
}

public enum FileRenamerError: LocalizedError, Equatable {
    case sourceMissing(URL)
    case sourceIsDirectory(URL)
    case emptyDestinationName(URL)
    case invalidDestinationDirectory(URL)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let url):
            return "파일을 찾을 수 없습니다: \(url.lastPathComponent)"
        case .sourceIsDirectory(let url):
            return "폴더는 이름 변경 대상에서 제외됩니다: \(url.lastPathComponent)"
        case .emptyDestinationName(let url):
            return "새 파일명이 비어 있습니다: \(url.lastPathComponent)"
        case .invalidDestinationDirectory(let url):
            return "출력 폴더를 사용할 수 없습니다: \(url.path)"
        }
    }
}

public struct FileRenamer {
    public init() {}

    public func makeDestinationURL(
        for sourceURL: URL,
        itemIndex: Int,
        options: FileRenameOptions,
        outputDirectory: URL? = nil,
        uniquingIn fileManager: FileManager = .default
    ) throws -> URL {
        let directory = outputDirectory ?? sourceURL.deletingLastPathComponent()
        let baseName = makeBaseName(for: sourceURL, itemIndex: itemIndex, options: options)

        guard !baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileRenamerError.emptyDestinationName(sourceURL)
        }

        var candidate = directory.appendingPathComponent(baseName)
        let pathExtension = sourceURL.pathExtension
        if !pathExtension.isEmpty {
            candidate.appendPathExtension(pathExtension)
        }

        if candidate.standardizedFileURL == sourceURL.standardizedFileURL {
            candidate = addUniqueSuffix(to: candidate, suffix: "-1")
        }

        var uniqueCandidate = candidate
        var counter = 1

        while fileManager.fileExists(atPath: uniqueCandidate.path) {
            uniqueCandidate = addUniqueSuffix(to: candidate, suffix: "-\(counter)")
            counter += 1
        }

        return uniqueCandidate
    }

    public func rename(
        sourceURL: URL,
        itemIndex: Int,
        options: FileRenameOptions,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> FileRenameSuccess {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw FileRenamerError.sourceMissing(sourceURL)
        }

        guard !isDirectory.boolValue else {
            throw FileRenamerError.sourceIsDirectory(sourceURL)
        }

        if let outputDirectory {
            var outputIsDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: outputDirectory.path, isDirectory: &outputIsDirectory),
                  outputIsDirectory.boolValue else {
                throw FileRenamerError.invalidDestinationDirectory(outputDirectory)
            }
        }

        let destinationURL = try makeDestinationURL(
            for: sourceURL,
            itemIndex: itemIndex,
            options: options,
            outputDirectory: outputDirectory,
            uniquingIn: fileManager
        )

        switch options.operation {
        case .renameOriginal:
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        case .createCopy:
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return FileRenameSuccess(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            operation: options.operation
        )
    }

    public func rename(
        urls: [URL],
        options: FileRenameOptions,
        outputDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> BatchFileRenameReport {
        var successes: [FileRenameSuccess] = []
        var failures: [FileRenameFailure] = []

        for (index, url) in urls.enumerated() {
            do {
                let result = try rename(
                    sourceURL: url,
                    itemIndex: index,
                    options: options,
                    outputDirectory: outputDirectory,
                    fileManager: fileManager
                )
                successes.append(result)
            } catch {
                failures.append(
                    FileRenameFailure(
                        sourceURL: url,
                        reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    )
                )
            }
        }

        return BatchFileRenameReport(successes: successes, failures: failures)
    }

    private func makeBaseName(
        for sourceURL: URL,
        itemIndex: Int,
        options: FileRenameOptions
    ) -> String {
        let originalName = options.includeOriginalName ? sourceURL.deletingPathExtension().lastPathComponent : ""
        let sequence = makeSequence(itemIndex: itemIndex, options: options)
        let nameWithSequence: String

        switch options.sequencePlacement {
        case .beforeName:
            nameWithSequence = join(sequence, originalName, separator: options.sequenceSeparator)
        case .afterName:
            nameWithSequence = join(originalName, sequence, separator: options.sequenceSeparator)
        }

        return "\(options.prefix)\(nameWithSequence)\(options.suffix)"
    }

    private func makeSequence(itemIndex: Int, options: FileRenameOptions) -> String {
        guard options.includeSequence else {
            return ""
        }

        let number = max(0, options.sequenceStart) + itemIndex
        let digitCount = min(max(options.sequenceDigits, 1), 12)
        return String(format: "%0*d", digitCount, number)
    }

    private func join(_ left: String, _ right: String, separator: String) -> String {
        guard !left.isEmpty else {
            return right
        }

        guard !right.isEmpty else {
            return left
        }

        return "\(left)\(separator)\(right)"
    }

    private func addUniqueSuffix(to url: URL, suffix: String) -> URL {
        let directory = url.deletingLastPathComponent()
        let pathExtension = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(baseName)\(suffix)")

        if !pathExtension.isEmpty {
            candidate.appendPathExtension(pathExtension)
        }

        return candidate
    }
}
