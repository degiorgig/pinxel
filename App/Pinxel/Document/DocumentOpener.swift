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

    /// Apre un file (per esempio una cattura della libreria): si salva da solo dove sta.
    static func open(url: URL, completion: ((NSDocument?) -> Void)? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error { NSApp.presentError(error) }
            NSApp.activate()
            completion?(document)
        }
    }
}
