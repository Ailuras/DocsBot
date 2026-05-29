import SwiftUI

@main
struct DocsBotApp: App {
    @StateObject private var eventKit = EventKitService()
    @StateObject private var store = ProjectStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
                .frame(minWidth: 760, minHeight: 480)
        }

        // Menu bar quick-capture: add a prefixed item to a project without
        // opening the main window. Shares the same stores/services.
        MenuBarExtra("DocsBot", systemImage: "diamond") {
            QuickCaptureView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
        }
        .menuBarExtraStyle(.window)

        // Standard macOS Settings window (⌘,). All configuration lives here;
        // the main window and menu bar are for use. Fully-qualified because our
        // own `Settings` store would otherwise shadow SwiftUI's Settings scene.
        SwiftUI.Settings {
            SettingsRootView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
        }
    }
}
