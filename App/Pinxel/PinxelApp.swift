import SwiftUI

@main
struct PinxelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra("Pinxel", systemImage: "camera.viewfinder") {
            MenuContent(environment: environment)
        }
        Settings {
            SettingsView(environment: environment)
        }
    }
}
