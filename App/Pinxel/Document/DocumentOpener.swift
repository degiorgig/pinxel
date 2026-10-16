import AppKit
import Persistence

@MainActor
enum DocumentOpener {
    /// Apre i contenuti in un documento senza titolo; `name` è il nome proposto (finestra e Salva).
    @discardableResult
    static func open(_ contents: PinxelFileContents, name: String? = nil) -> NSDocument {
        let document = PinxelFileDocument(contents: contents)
        if let name { document.displayName = name }
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        NSApp.setActivationPolicy(.regular)
        document.showWindows()
        NSApp.activate()
        return document
    }
}
