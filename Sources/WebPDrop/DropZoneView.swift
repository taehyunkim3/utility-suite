import SwiftUI
import UniformTypeIdentifiers

private final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storedURLs.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedURLs
    }
}

private func extractDroppedFileURL(from item: NSSecureCoding?) -> URL? {
    if let data = item as? Data {
        return URL(dataRepresentation: data, relativeTo: nil)
    }

    if let url = item as? URL {
        return url
    }

    if let nsURL = item as? NSURL {
        return nsURL as URL
    }

    if let string = item as? String,
       let url = URL(string: string),
       url.isFileURL {
        return url
    }

    return nil
}

/// WebP 변환과 음원 추출 탭에서 공통으로 사용하는 드롭 영역.
struct MediaDropZone: View {
    @Binding var isTargeted: Bool
    let iconName: String
    let title: String
    let subtitle: String
    let onTap: () -> Void
    let onDropURLs: ([URL]) -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(isTargeted ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                    )
            }
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 40, weight: .semibold))
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 200)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {
                onTap()
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let collector = DroppedURLCollector()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                if let url = extractDroppedFileURL(from: item) {
                    collector.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            onDropURLs(collector.urls)
        }

        return true
    }
}
