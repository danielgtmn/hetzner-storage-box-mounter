import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.danielgtmn.hetznermount", category: "App")

@main
struct HetznerMountApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var domainManager = DomainManager.shared

    init() {
        signal(SIGPIPE, SIG_IGN)

        Task { @MainActor in
            await DomainManager.shared.migrateIfNeeded()
        }
    }

    var body: some Scene {
        MenuBarExtra(
            "HetznerMount",
            systemImage: domainManager.anyMounted
                ? "externaldrive.fill.badge.checkmark"
                : "externaldrive.badge.xmark"
        ) {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Window("HetznerMount Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentMinSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Holds the activity token to prevent automatic termination
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("App launched (PID \(ProcessInfo.processInfo.processIdentifier))")

        // Begin a long-running activity that prevents automatic termination and App Nap.
        // This is the system-level way to tell macOS "this process must stay alive".
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Menu bar app providing FileProvider mount service"
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
