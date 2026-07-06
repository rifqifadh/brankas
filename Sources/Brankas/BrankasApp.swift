import SwiftUI
import SwiftData

@main
struct BrankasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.clipboardService)
                .modelContainer(appDelegate.container)
        }
    }
}
