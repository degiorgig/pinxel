import SwiftUI

@main
struct PinxelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppEnvironment.shared

    var body: some Scene {
        MenuBarExtra("Pinxel", systemImage: "camera.viewfinder") {
            MenuContent(environment: environment)
        }
        .commands {
            EditorCommands()
            // Formato → Font: ⌘B, ⌘I, ⌘U mentre si scrive un testo sulla tela.
            TextFormattingCommands()
        }
        Settings {
            SettingsView(environment: environment)
        }
    }
}
