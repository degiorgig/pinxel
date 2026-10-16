import AppKit
import DocumentModel
import EditorUI
import SwiftUI

/// Finestra dell'editor: vista SwiftUI con toolbar nativa (via `sceneBridgingOptions`) e pannello proprietà.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let model: EditorModel

    init(model: EditorModel) {
        self.model = model
        let hosting = NSHostingController(rootView: EditorView(model: model))
        hosting.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 640, height: 420)
        window.setContentSize(Self.initialContentSize(for: model.session.document))
        window.center()
        if model.session.isReadOnly { window.subtitle = "Sola lettura" }
        super.init(window: window)
        // Il documento entra nella catena dei responder (Salva, Esporta…) tramite il delegato della finestra.
        window.delegate = self
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // I menu seguono l'editor della finestra principale (un foglio come Esporta lascia la finestra principale).
    func windowDidBecomeMain(_ notification: Notification) {
        EditorFocus.shared.focus(model, isKey: window?.isKeyWindow ?? true)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        EditorFocus.shared.keyChanged(model, isKey: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        EditorFocus.shared.keyChanged(model, isKey: false)
    }

    func windowDidResignMain(_ notification: Notification) {
        EditorFocus.shared.resign(model)
    }

    func windowWillClose(_ notification: Notification) {
        EditorFocus.shared.resign(model)
    }

    /// Immagine al 100% più il pannello, entro il 90% dello schermo; almeno 1100 punti, perché sotto
    /// quella larghezza la toolbar finisce tutta nel menu di overflow e gli strumenti spariscono.
    static func initialContentSize(for document: PinxelDocument) -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let imageWidth = Double(document.imageSize.width) / document.scale
        let imageHeight = Double(document.imageSize.height) / document.scale
        return NSSize(
            width: min(max(imageWidth + 260 + 80, 1100), visible.width * 0.9),
            height: min(max(imageHeight + 80, 520), visible.height * 0.9)
        )
    }
}
