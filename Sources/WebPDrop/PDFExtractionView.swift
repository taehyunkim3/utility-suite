import SwiftUI
import WebPDropCore

struct PDFExtractionView: View {
    @ObservedObject var viewModel: PDFExtractionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            MediaDropZone(
                isTargeted: $viewModel.isDropTargeted,
                iconName: "doc.richtext",
                title: "PDF 파일을 여기로 드래그하거나 클릭하세요",
                subtitle: "각 페이지를 PNG·JPEG 이미지로 저장합니다",
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
            Text("PDF → 이미지")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("PDF의 모든 페이지를 한 장씩 이미지 파일로 추출합니다.")
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("출력 포맷")
                        .font(.headline)

                    Picker("출력 포맷", selection: $viewModel.outputFormat) {
                        ForEach(PDFImageFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)

                    HStack(spacing: 8) {
                        Text("해상도")
                            .font(.subheadline)
                        Picker("해상도", selection: $viewModel.dpi) {
                            ForEach(viewModel.availableDPIs, id: \.self) { value in
                                Text("\(value) DPI").tag(value)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 130)
                    }

                    if viewModel.outputFormat.supportsQuality {
                        HStack(spacing: 8) {
                            Text("품질")
                                .font(.subheadline)
                            Slider(value: $viewModel.jpegQuality, in: 0...1)
                                .frame(maxWidth: 140)
                            Text("\(viewModel.jpegQualityPercentage)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 300)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("출력 위치")
                        .font(.headline)

                    Picker("출력 위치", selection: $viewModel.destinationMode) {
                        ForEach(PDFExtractionViewModel.DestinationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.destinationMode == .customFolder {
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
                }
            }

            HStack(spacing: 10) {
                Button("목록 비우기") {
                    viewModel.clear()
                }
                .disabled(viewModel.items.isEmpty || viewModel.isExtracting)
                Button("완료 항목 삭제") {
                    viewModel.clearCompleted()
                }
                .disabled(!viewModel.hasCompletedItems || viewModel.isExtracting)
                Spacer()
                Button {
                    Task {
                        await viewModel.extractAll()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.isExtracting ? "hourglass" : "photo.on.rectangle.angled")
                            .font(.system(size: 22, weight: .bold))
                        Text(viewModel.isExtracting ? "추출 중..." : "이미지로 추출")
                            .font(.system(size: 22, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                }
                .buttonStyle(.borderedProminent)
                .frame(minWidth: 300, maxWidth: 340)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canExtract)
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("추출 대기 목록")
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
                            if let pages = viewModel.pageCount(for: item) {
                                Text("\(pages)장")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
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
            .frame(minHeight: 200)
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
}
