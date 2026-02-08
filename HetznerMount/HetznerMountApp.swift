import SwiftUI

@main
struct HetznerMountApp: App {
    @StateObject private var domainManager = DomainManager.shared

    var body: some Scene {
        MenuBarExtra(
            "HetznerMount",
            systemImage: domainManager.isMounted
                ? "externaldrive.fill.badge.checkmark"
                : "externaldrive.badge.xmark"
        ) {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Window("HetznerMount Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}
