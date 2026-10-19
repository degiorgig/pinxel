import AppKit
import DocumentModel
import EditorUI
import SwiftUI

/// Finestra dell'editor: vista SwiftUI con toolbar nativa (via `sceneBridgingOptions`) e pannello proprietà.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private(set) var model: EditorModel
    /// Filtro e selezione del carosello di questa finestra: restano quando cambia la cattura mostrata.
    let stripState = LibraryStripState()
    private let hosting: NSHostingController<EditorView>
    private let reference = WeakReference()

    init(model: EditorModel) {
        self.model = model
        hosting = NSHostingController(rootView: Self.view(model: model, stripState: stripState, reference: reference))
        hosting.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 640, height: 420)
        window.setContentSize(Self.initialContentSize(for: model.session.document))
        window.center()
        if model.session.isReadOnly { window.subtitle = String(localized: "Read Only") }
        super.init(window: window)
        reference.controller = self
        // Il documento entra nella catena dei responder (Salva, Esporta…) tramite il delegato della finestra.
        window.delegate = self
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func view(model: EditorModel, stripState: LibraryStripState, reference: WeakReference) -> EditorView {
        EditorView(model: model, stripState: stripState,
                   currentURL: { (reference.controller?.document as? NSDocument)?.fileURL },
                   window: { reference.controller?.window })
    }

    /// Un'altra cattura nella stessa finestra (clic sul carosello): stessa cornice, stesso carosello, tela nuova.
    func show(_ model: EditorModel) {
        EditorFocus.shared.resign(self.model)
        self.model = model
        hosting.rootView = Self.view(model: model, stripState: stripState, reference: reference)
        window?.subtitle = model.session.isReadOnly ? String(localized: "Read Only") : ""
        if window?.isMainWindow ?? false { EditorFocus.shared.focus(model, isKey: window?.isKeyWindow ?? true) }
    }

    @MainActor
    private final class WeakReference {
        weak var controller: EditorWindowController?
    }

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
