import AppCore
import CaptureKit
import SwiftUI

struct MenuContent: View {
    let environment: AppEnvironment
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("\(HotKeyAction.area.title)  \(environment.settings.combo(for: .area).displayString)") { environment.capture(.area) }
        Button("\(HotKeyAction.window.title)  \(environment.settings.combo(for: .window).displayString)") { environment.capture(.window) }
        Button("\(HotKeyAction.screen.title)  \(environment.settings.combo(for: .screen).displayString)") { environment.capture(.screen) }
        Button("\(HotKeyAction.repeatLastArea.title)  \(environment.settings.combo(for: .repeatLastArea).displayString)") { environment.repeatLastArea() }
        Divider()
        Button("Apri…") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            NSDocumentController.shared.openDocument(nil)
        }
        Button("Preferenze…") {
            NSApp.activate()
            openSettings()
        }
            .keyboardShortcut(",")
        Divider()
        Button("Esci da Pinxel") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
