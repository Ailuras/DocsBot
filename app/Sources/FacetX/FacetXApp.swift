import SwiftUI

@main
struct FacetXApp: App {
    @StateObject private var eventKit = EventKitService()
    @StateObject private var store = ProjectStore()
    @StateObject private var settings = AppSettings()
    @StateObject private var menuBarController = MenuBarController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
                .background {
                    MenuBarInstaller(controller: menuBarController)
                        .environmentObject(eventKit)
                        .environmentObject(store)
                        .environmentObject(settings)
                }
                .frame(minWidth: 760, minHeight: 480)
        }

        // Standard macOS Settings window (⌘,). App-wide container configuration
        // lives here; project management stays in the main window.
        // Fully-qualified because our own `Settings` store would otherwise
        // shadow SwiftUI's Settings scene.
        SwiftUI.Settings {
            SettingsRootView()
                .environmentObject(eventKit)
                .environmentObject(store)
                .environmentObject(settings)
        }
    }
}
