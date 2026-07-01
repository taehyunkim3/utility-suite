import SwiftUI
import WebPDropCore

struct AudioExtractionView: View {
    @ObservedObject var viewModel: AudioExtractionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            MediaDropZone(
                isTargeted: $viewModel.isDropTargeted,
                iconName: "waveform",
                title: "영상/음성 파일을 여기로 드래그하거나 클릭하세요",
                subtitle: "MP4, MOV, MKV, M4A 등 지원",
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
            Text("음원 추출")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("녹화 영상 등에서 오디오만 뽑아 MP3·M4A 등으로 저장합니다.")
                .foregroundStyle(.secondary)

            if !viewModel.extractionAvailable {
                Text("ffmpeg를 찾지 못했습니다. brew install ffmpeg 로 설치하세요.")
                    .foregroundStyle(.red)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("출력 포맷")
                        .font(.headline)

                    Picker("출력 포맷", selection: $viewModel.outputFormat) {
                        ForEach(AudioOutputFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)

                    if viewModel.outputFormat.supportsBitrate {
                        HStack(spacing: 8) {
                            Text("비트레이트")
                                .font(.subheadline)
                            Picker("비트레이트", selection: $viewModel.bitrateKbps) {
                                ForEach(viewModel.availableBitrates, id: \.self) { rate in
                                    Text("\(rate) kbps").tag(rate)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 130)
                        }
                    } else {
                        Text("무손실 포맷은 비트레이트 설정이 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 280)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("출력 위치")
                        .font(.headline)

                    Picker("출력 위치", selection: $viewModel.destinationMode) {
                        ForEach(AudioExtractionViewModel.DestinationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

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
                Toggle("완료 후 목록 지우기", isOn: $viewModel.clearCompletedItemsAfterExtraction)
                    .disabled(viewModel.isExtracting)
                Spacer()
                Button {
                    Task {
                        await viewModel.extractAll()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.isExtracting ? "hourglass" : "waveform.badge.plus")
                            .font(.system(size: 22, weight: .bold))
                        Text(viewModel.isExtracting ? "추출 중..." : "음원 추출")
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
