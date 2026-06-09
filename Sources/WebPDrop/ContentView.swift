import SwiftUI

struct ContentView: View {
    @StateObject private var conversionViewModel = ConversionViewModel()
    @StateObject private var audioViewModel = AudioExtractionViewModel()
    @StateObject private var pdfViewModel = PDFExtractionViewModel()
    @State private var selectedTab: Tab = .webp

    enum Tab: Hashable {
        case webp
        case audio
        case pdf
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WebPConversionView(viewModel: conversionViewModel)
                .tabItem {
                    Label("WebP 변환", systemImage: "photo")
                }
                .tag(Tab.webp)

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
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
