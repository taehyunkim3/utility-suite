import SwiftUI

struct WebPConversionView: View {
    @ObservedObject var viewModel: ConversionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            MediaDropZone(
                isTargeted: $viewModel.isDropTargeted,
                iconName: "tray.and.arrow.down.fill",
                title: "이미지를 여기로 드래그하거나 클릭하세요",
                subtitle: "PNG, JPG, JPEG 파일 지원",
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
            Text("Utility Suite")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("드래그앤드롭으로 여러 이미지를 한 번에 WebP로 변환합니다.")
                .foregroundStyle(.secondary)

            if !viewModel.encodingAvailable {
                Text("현재 시스템에서 WebP 인코더를 찾지 못했습니다.")
                    .foregroundStyle(.red)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("품질")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.qualityPercentage)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $viewModel.quality, in: 0...1)
                }
                .frame(maxWidth: 280)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("출력 위치")
                        .font(.headline)

                    Picker("출력 위치", selection: $viewModel.destinationMode) {
                        ForEach(ConversionViewModel.DestinationMode.allCases) { mode in
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
                .disabled(viewModel.items.isEmpty || viewModel.isConverting)
                Button("완료 항목 삭제") {
                    viewModel.clearCompleted()
                }
                .disabled(!viewModel.hasCompletedItems || viewModel.isConverting)
                Spacer()
                Button {
                    Task {
                        await viewModel.convertAll()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.isConverting ? "hourglass" : "arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.system(size: 22, weight: .bold))
                        Text(viewModel.isConverting ? "변환 중..." : "WebP로 변환")
                            .font(.system(size: 22, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 76)
                }
                .buttonStyle(.borderedProminent)
                .frame(minWidth: 300, maxWidth: 340)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canConvert)
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("변환 대기 목록")
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
}
