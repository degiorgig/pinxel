import SwiftUI

@main
struct PinxelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Pinxel", systemImage: "camera.viewfinder") {
            Button("Esci da Pinxel") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
