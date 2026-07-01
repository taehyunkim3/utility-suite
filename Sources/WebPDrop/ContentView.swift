import SwiftUI

struct ContentView: View {
    @StateObject private var conversionViewModel = ConversionViewModel()
    @StateObject private var audioViewModel = AudioExtractionViewModel()
    @StateObject private var pdfViewModel = PDFExtractionViewModel()
    @StateObject private var fileRenameViewModel = FileRenameViewModel()
    @StateObject private var videoViewModel = VideoOptimizationViewModel()
    @State private var selectedTab: Tab = .webp

    enum Tab: Hashable {
        case webp
        case video
        case audio
        case pdf
        case rename
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WebPConversionView(viewModel: conversionViewModel)
                .tabItem {
                    Label("WebP 변환", systemImage: "photo")
                }
                .tag(Tab.webp)

            VideoOptimizationView(viewModel: videoViewModel)
                .tabItem {
                    Label("영상 최적화", systemImage: "film")
                }
                .tag(Tab.video)

            AudioExtractionView(viewModel: audioViewModel)
                .tabItem {
                    Label("음원 추출", systemImage: "music.note")
                }
                .tag(Tab.audio)

            PDFExtractionView(viewModel: pdfViewModel)
                .tabItem {
                    Label("PDF → 이미지", systemImage: "doc.richtext")
                }
                .tag(Tab.pdf)

            FileRenameView(viewModel: fileRenameViewModel)
                .tabItem {
                    Label("파일명 정리", systemImage: "text.badge.plus")
                }
                .tag(Tab.rename)
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 780)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
