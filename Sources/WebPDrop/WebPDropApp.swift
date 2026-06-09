import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
