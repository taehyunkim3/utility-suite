import SwiftUI
import WebPDropCore

struct VideoOptimizationView: View {
    @ObservedObject var viewModel: VideoOptimizationViewModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                header
                MediaDropZone(
                    isTargeted: $viewModel.isDropTargeted,
                    iconName: "film.stack",
                    title: "MP4/MOV 영상을 여기로 드래그하거나 클릭하세요",
                    subtitle: "영상 분석 후 랜딩 PC/모바일용 MP4와 poster.webp를 출력합니다.",
                    onTap: { viewModel.chooseFiles() },
                    onDropURLs: { viewModel.addFiles(urls: $0) }
                )
                controls
                progressConsole
                content
                footer
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("영상 최적화")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("왜 20초 영상이 35MB인지 분석하고, 랜딩에 바로 쓰는 웹 최적화 MP4로 압축합니다.")
                .foregroundStyle(.secondary)

            if !viewModel.optimizationAvailable {
                Text("ffmpeg/ffprobe를 찾지 못했습니다. brew install ffmpeg 로 설치하세요.")
                    .foregroundStyle(.red)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("프리셋")
                        .font(.headline)

                    Picker("프리셋", selection: $viewModel.selectedPreset) {
                        ForEach(VideoOptimizationPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack(spacing: 8) {
                        Toggle("목표 용량", isOn: $viewModel.useTargetSize)
                        Stepper("\(viewModel.targetMegabytes, specifier: "%.0f") MB 이하", value: $viewModel.targetMegabytes, in: 1...200, step: 1)
                            .disabled(!viewModel.useTargetSize)
                    }
                }
                .frame(maxWidth: 330)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("압축 옵션")
                        .font(.headline)

                    Picker("해상도", selection: $viewModel.widthMode) {
                        ForEach(VideoOptimizationViewModel.WidthMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Picker("FPS", selection: $viewModel.fpsMode) {
                        ForEach(VideoOptimizationViewModel.FPSMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    HStack(spacing: 12) {
                        Picker("코덱", selection: $viewModel.codec) {
                            ForEach(VideoCodec.allCases) { codec in
                                Text(codec.displayName).tag(codec)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 120)

                        qualitySlider
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("웹 최적화")
                        .font(.headline)

                    Toggle("오디오 제거", isOn: $viewModel.removeAudio)
                    Toggle("faststart 적용", isOn: $viewModel.fastStart)
                    Stepper("포스터 \(viewModel.posterTime, specifier: "%.1f")초", value: $viewModel.posterTime, in: 0...30, step: 0.1)

                    Picker("출력 위치", selection: $viewModel.destinationMode) {
                        ForEach(VideoOptimizationViewModel.DestinationMode.allCases) { mode in
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
                .frame(maxWidth: 260)
            }

            HStack(spacing: 10) {
                Button("목록 비우기") {
                    viewModel.clear()
                }
                .disabled(viewModel.items.isEmpty || viewModel.isOptimizing)

                Spacer()

                Button {
                    Task {
                        await viewModel.extractPosters()
                    }
                } label: {
                    Label("포스터 추출", systemImage: "photo")
                }
                .disabled(!viewModel.canOptimize)

                Button {
                    Task {
                        await viewModel.createLandingPackage()
                    }
                } label: {
                    Label("랜딩 패키지 출력", systemImage: "square.stack.3d.up")
                }
                .disabled(!viewModel.canOptimize)

                Button {
                    Task {
                        await viewModel.optimizeAll()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: viewModel.isOptimizing ? "hourglass" : "film.badge.checkmark")
                            .font(.system(size: 20, weight: .bold))
                        Text(viewModel.isOptimizing ? "변환 중..." : "MP4 최적화")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .frame(minWidth: 240, maxWidth: 280)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canOptimize)
            }
        }
    }

    private var qualitySlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("품질")
                Spacer()
                Text(viewModel.quality.displayName)
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: {
                        Double(VideoQualityLevel.allCases.firstIndex(of: viewModel.quality) ?? 1)
                    },
                    set: { value in
                        let index = min(max(Int(value.rounded()), 0), VideoQualityLevel.allCases.count - 1)
                        viewModel.quality = VideoQualityLevel.allCases[index]
                    }
                ),
                in: 0...Double(VideoQualityLevel.allCases.count - 1),
                step: 1
            )
        }
        .frame(minWidth: 160)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 16) {
            sourceList
            resultPanel
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("원본 영상")
                    .font(.headline)
                Spacer()
                Text(viewModel.selectedCountLabel)
                    .foregroundStyle(.secondary)
            }

            List(viewModel.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.filename)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("제거") {
                            viewModel.remove(item)
                        }
                        .buttonStyle(.borderless)
                    }

                    if let metadata = viewModel.metadata(for: item) {
                        Text(metadataSummary(metadata))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if let failure = viewModel.failureReason(for: item) {
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else {
                        Text(viewModel.isAnalyzing ? "분석 중..." : item.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minWidth: 390, minHeight: 220)
        }
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("결과 비교")
                    .font(.headline)
                Spacer()
                if let latestOutputDirectory = viewModel.latestOutputDirectory {
                    Button("출력 폴더 열기") {
                        viewModel.open(latestOutputDirectory)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let report = viewModel.lastReport {
                List {
                    ForEach(report.successes, id: \.destinationURL.path) { success in
                        resultRow(success)
                    }

                    ForEach(report.posters, id: \.destinationURL.path) { poster in
                        posterRow(poster)
                    }

                    ForEach(Array(report.failures.enumerated()), id: \.offset) { _, failure in
                        Text("\(failure.sourceURL.lastPathComponent): \(failure.reason)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("변환 후 원본 대비 용량, 절감률, 비트레이트가 표시됩니다.")
                        .foregroundStyle(.secondary)
                    Text("랜딩 패키지 출력은 파일당 .pc.mp4, .mobile.mp4, .poster.webp를 생성합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            }

            Text("미리보기는 결과 행의 재생 버튼으로 기본 플레이어에서 확인합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 390)
    }

    private func resultRow(_ success: VideoOptimizationSuccess) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(success.destinationURL.lastPathComponent)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("재생") {
                    viewModel.open(success.destinationURL)
                }
                .buttonStyle(.borderless)
                Button("열기") {
                    viewModel.open(success.destinationURL)
                }
                .buttonStyle(.borderless)
            }

            Text(comparisonSummary(success))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func posterRow(_ poster: PosterExtractionSuccess) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(poster.destinationURL.lastPathComponent)
                    .fontWeight(.medium)
                Text("poster.webp · \(formatBytes(poster.fileSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("열기") {
                viewModel.open(poster.destinationURL)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.progressMessage)
                .foregroundStyle(.secondary)

            if let summaryText = viewModel.summaryText {
                Text(summaryText)
                    .font(.subheadline.weight(.semibold))
            }

            if let latestLog = viewModel.latestLog, !latestLog.isEmpty {
                DisclosureGroup("변환 로그 보기") {
                    ScrollView {
                        Text(latestLog)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
    }

    private var progressConsole: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("진행 로그", systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(viewModel.isOptimizing || viewModel.isAnalyzing ? "실행 중" : "대기")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(viewModel.isOptimizing || viewModel.isAnalyzing ? .green : .secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.progressLogLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color(nsColor: .systemGreen))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 118)
                .background(Color.black.opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .systemGreen).opacity(0.24))
                }
                .onChange(of: viewModel.progressLogLines.count) { count in
                    guard count > 0 else {
                        return
                    }

                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
    }

    private func metadataSummary(_ metadata: VideoMetadata) -> String {
        let duration = metadata.duration.map { "\(Int($0.rounded()))초" } ?? "-"
        let codec = metadata.codecName?.uppercased() ?? "-"
        let audio = metadata.hasAudio ? "오디오 포함" : "오디오 없음"
        return "\(metadata.resolutionText) / \(duration) / \(formatFPS(metadata.fps)) / \(codec) / \(formatBytes(metadata.fileSize)) / \(formatBitrate(metadata.averageBitrate)) / \(audio)"
    }

    private func comparisonSummary(_ success: VideoOptimizationSuccess) -> String {
        let original = formatBytes(success.originalFileSize)
        let optimized = formatBytes(success.optimizedFileSize)
        let saved = savingsText(original: success.originalFileSize, optimized: success.optimizedFileSize)
        let originalBitrate = formatBitrate(success.metadata.averageBitrate)
        let optimizedBitrate = formatBitrate(success.optimizedBitrate)
        return "용량 \(original) → \(optimized) / 절감 \(saved) / 비트레이트 \(originalBitrate) → \(optimizedBitrate)"
    }

    private func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes else {
            return "-"
        }

        let megabytes = Double(bytes) / 1_024 / 1_024
        return "\(megabytes.formatted(.number.precision(.fractionLength(1))))MB"
    }

    private func formatBitrate(_ bitsPerSecond: Int64?) -> String {
        guard let bitsPerSecond else {
            return "-"
        }

        let megabits = Double(bitsPerSecond) / 1_000_000
        return "약 \(megabits.formatted(.number.precision(.fractionLength(1))))Mbps"
    }

    private func formatFPS(_ fps: Double?) -> String {
        guard let fps else {
            return "-"
        }

        return "\(fps.formatted(.number.precision(.fractionLength(0...2)))) FPS"
    }

    private func savingsText(original: Int64?, optimized: Int64?) -> String {
        guard let original, let optimized, original > 0 else {
            return "-"
        }

        let ratio = max(0, 1 - (Double(optimized) / Double(original)))
        return "\(ratio.formatted(.percent.precision(.fractionLength(0))))"
    }
}
