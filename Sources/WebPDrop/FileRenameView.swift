import SwiftUI
import WebPDropCore

struct FileRenameView: View {
    @ObservedObject var viewModel: FileRenameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            MediaDropZone(
                isTargeted: $viewModel.isDropTargeted,
                iconName: "text.badge.plus",
                title: "이름을 바꿀 파일을 여기로 드래그하거나 클릭하세요",
                subtitle: "모든 파일 형식 지원",
                onTap: { viewModel.chooseFiles() },
                onDropURLs: { viewModel.addFiles(urls: $0) }
            )
            controls
            fileList
            footer
        }
        .padding(4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("파일명 정리")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("접두어·접미어·순번을 조합해 원본 파일명을 변경하거나 복사본을 만듭니다.")
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                namingControls
                    .frame(maxWidth: 360)

                Divider()

                sequenceControls
                    .frame(maxWidth: 300)

                Divider()

                operationControls
            }

            preview

            HStack(spacing: 10) {
                Button("목록 비우기") {
                    viewModel.clear()
                }
                .disabled(viewModel.items.isEmpty || viewModel.isProcessing)
                Button("완료 항목 삭제") {
                    viewModel.clearCompleted()
                }
                .disabled(!viewModel.hasCompletedItems || viewModel.isProcessing)
                Toggle("완료 후 목록 지우기", isOn: $viewModel.clearCompletedItemsAfterProcessing)
                    .disabled(viewModel.isProcessing)
                Spacer()
                Button {
                    Task {
                        await viewModel.processAll()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.isProcessing ? "hourglass" : actionIconName)
                            .font(.system(size: 22, weight: .bold))
                        Text(viewModel.isProcessing ? "처리 중..." : viewModel.operationTitle)
                            .font(.system(size: 22, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                }
                .buttonStyle(.borderedProminent)
                .frame(minWidth: 300, maxWidth: 340)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canProcess)
            }
        }
    }

    private var namingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("이름 규칙")
                .font(.headline)

            TextField("앞에 붙일 글자", text: $viewModel.prefix)
                .textFieldStyle(.roundedBorder)

            TextField("뒤에 붙일 글자", text: $viewModel.suffix)
                .textFieldStyle(.roundedBorder)

            Toggle("기존 파일명 유지", isOn: $viewModel.includeOriginalName)

            Text("확장자는 원래 확장자를 그대로 유지합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sequenceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("순번")
                .font(.headline)

            Toggle("순번 추가", isOn: $viewModel.includeSequence)

            Picker("순번 위치", selection: $viewModel.sequencePlacement) {
                Text("파일명 앞").tag(FileRenameSequencePlacement.beforeName)
                Text("파일명 뒤").tag(FileRenameSequencePlacement.afterName)
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.includeSequence)

            Stepper("시작 번호 \(viewModel.sequenceStart)", value: $viewModel.sequenceStart, in: 0...999_999)
                .disabled(!viewModel.includeSequence)

            Stepper("자리수 \(viewModel.sequenceDigits)", value: $viewModel.sequenceDigits, in: 1...12)
                .disabled(!viewModel.includeSequence)

            TextField("구분자", text: $viewModel.sequenceSeparator)
                .textFieldStyle(.roundedBorder)
                .disabled(!viewModel.includeSequence)
        }
    }

    private var operationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("실행 방식")
                .font(.headline)

            Picker("실행 방식", selection: $viewModel.operation) {
                Text("복사본 생성").tag(FileRenameOperation.createCopy)
                Text("원본 이름 변경").tag(FileRenameOperation.renameOriginal)
            }
            .pickerStyle(.segmented)

            Picker("출력 위치", selection: $viewModel.destinationMode) {
                ForEach(FileRenameViewModel.DestinationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.operation == .renameOriginal)

            if viewModel.operation == .createCopy && viewModel.destinationMode == .customFolder {
                HStack {
                    Text(viewModel.customOutputFolder?.path ?? "폴더를 선택하세요")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(viewModel.customOutputFolder == nil ? .secondary : .primary)
                    Button("폴더 선택") {
                        viewModel.chooseOutputFolder()
                    }
                }
            }

            if viewModel.operation == .renameOriginal {
                Text("원본 파일 자체의 이름이 변경됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("미리보기")
                    .font(.headline)
                Spacer()
                Text("최대 5개 표시")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.previewItems.isEmpty {
                Text("파일을 추가하면 새 파일명이 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(Array(viewModel.previewItems.enumerated()), id: \.offset) { _, item in
                        GridRow {
                            Text(item.source)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            Text(item.destination)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .font(.caption)
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("처리 대기 목록")
                    .font(.headline)
                Spacer()
                Text(viewModel.selectedCountLabel)
                    .foregroundStyle(.secondary)
            }

            List(viewModel.items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.filename)
                                .fontWeight(.medium)
                            if viewModel.isCompleted(item) {
                                Label("완료", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(item.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let failureReason = viewModel.failureReason(for: item) {
                            Text(failureReason)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer()
                    Button("제거") {
                        viewModel.remove(item)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 180)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.progressMessage)
                .foregroundStyle(.secondary)

            if let summaryText = viewModel.summaryText {
                HStack {
                    Text(summaryText)
                        .font(.subheadline.weight(.semibold))
                    if viewModel.hasCompletedItems {
                        Text("완료 표시 \(viewModel.completedCount)개")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Button("출력 폴더 열기") {
                        viewModel.openLatestOutputFolder()
                    }
                }
            }

            if let failures = viewModel.lastReport?.failures, !failures.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("실패 내역")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                        Text("• \(failure.sourceURL.lastPathComponent): \(failure.reason)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var actionIconName: String {
        switch viewModel.operation {
        case .renameOriginal:
            return "text.cursor"
        case .createCopy:
            return "doc.on.doc"
        }
    }
}
