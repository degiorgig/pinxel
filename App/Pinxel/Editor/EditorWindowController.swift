import AppKit
import DocumentModel
import EditorUI
import SwiftUI

/// Finestra dell'editor: vista SwiftUI con toolbar nativa (via `sceneBridgingOptions`) e pannello proprietà.
@MainActor
final class EditorWindowController: NSWindowController {
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
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Immagine al 100% più il pannello, entro il 90% dello schermo.
    static func initialContentSize(for document: PinxelDocument) -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let imageWidth = Double(document.imageSize.width) / document.scale
        let imageHeight = Double(document.imageSize.height) / document.scale
        return NSSize(
            width: min(max(imageWidth + 260 + 80, 800), visible.width * 0.9),
            height: min(max(imageHeight + 80, 520), visible.height * 0.9)
        )
    }
}
