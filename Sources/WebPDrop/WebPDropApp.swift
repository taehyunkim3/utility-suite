import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let minimumWindowSize = NSSize(width: 1120, height: 860)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [minimumWindowSize] in
            for window in NSApp.windows {
                window.minSize = minimumWindowSize

                if window.frame.width < minimumWindowSize.width || window.frame.height < minimumWindowSize.height {
                    let width = max(window.frame.width, minimumWindowSize.width)
                    let height = max(window.frame.height, minimumWindowSize.height)
                    var frame = window.frame
                    frame.origin.y -= height - frame.height
                    frame.size = NSSize(width: width, height: height)
                    window.setFrame(frame, display: true)
                }
            }
        }
    }
}

@main
struct WebPDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("오픈소스 라이선스") {
                    openOpenSourceLicenses()
                }
            }
        }
        .defaultSize(width: 1180, height: 900)
        .windowResizability(.contentSize)
    }

    private func openOpenSourceLicenses() {
        guard let resourceURL = Bundle.main.resourceURL else {
            return
        }

        let noticeURL = resourceURL
            .appendingPathComponent("ThirdPartyLicenses/cwebp/NOTICE.md")

        if FileManager.default.fileExists(atPath: noticeURL.path) {
            NSWorkspace.shared.open(noticeURL)
        }
    }
}
