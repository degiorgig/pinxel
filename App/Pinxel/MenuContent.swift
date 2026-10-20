import AppCore
import CaptureKit
import SwiftUI

struct MenuContent: View {
    let environment: AppEnvironment
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ForEach(HotKeyAction.allCases, id: \.self) { action in
            Button(action.title) { perform(action) }
                .globalShortcut(environment.settings.combo(for: action))
        }
        Divider()
        Button("Edit Last Capture") { environment.openLastCapture() }
            .disabled(environment.lastCapture == nil)
        Button("New") { environment.openBlank() }
        Button("New from Clipboard") { environment.openClipboard() }
        Button("Open…") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            NSDocumentController.shared.openDocument(nil)
        }
        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Pinxel") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .area: environment.capture(.area, fromMenu: true)
        case .window: environment.capture(.window, fromMenu: true)
        case .screen: environment.capture(.screen, fromMenu: true)
        case .scrolling: environment.captureScrolling(fromMenu: true)
        case .repeatLastArea: environment.repeatLastArea(fromMenu: true)
        }
    }
}

private extension View {
    /// Shows the global shortcut in the native column to the right of the menu.
    @ViewBuilder func globalShortcut(_ combo: KeyCombo) -> some View {
        if let key = combo.menuKeyEquivalent?.first {
            keyboardShortcut(KeyEquivalent(key), modifiers: eventModifiers(combo))
        } else {
            self
        }
    }

    private func eventModifiers(_ combo: KeyCombo) -> EventModifiers {
        var modifiers: EventModifiers = []
        if combo.modifiers & KeyCombo.control != 0 { modifiers.insert(.control) }
        if combo.modifiers & KeyCombo.option != 0 { modifiers.insert(.option) }
        if combo.modifiers & KeyCombo.shift != 0 { modifiers.insert(.shift) }
        if combo.modifiers & KeyCombo.command != 0 { modifiers.insert(.command) }
        return modifiers
    }
}
