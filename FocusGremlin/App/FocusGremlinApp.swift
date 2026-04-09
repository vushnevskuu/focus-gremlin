import SwiftUI

@main
struct FocusGremlinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(SettingsStore.shared)
        }
        .defaultSize(width: 560, height: 720)
    }
}
