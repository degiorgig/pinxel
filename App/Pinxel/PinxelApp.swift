import SwiftUI

@main
struct PinxelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra("Pinxel", image: "MenuBarIcon") {
            MenuContent(environment: environment)
        }
        .commands { EditorCommands() }
        Settings {
            SettingsView(environment: environment)
        }
    }
}
