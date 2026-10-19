import AppKit
import Library

@MainActor
enum LibraryOpener {
    /// Clic su una miniatura: porta avanti la finestra che la mostra già, la sostituisce nella finestra se questa mostra una
    /// cattura dell'archivio (già salvata), altrimenti apre una finestra nuova.
    static func open(_ item: Library.LibraryItem, from window: NSWindow?, newWindow: Bool = false) {
        let library = AppEnvironment.shared.library
        let url = library.url(for: item).standardizedFileURL
        let existing = NSDocumentController.shared.documents.first { $0.fileURL?.standardizedFileURL == url }
        let current = window.flatMap { NSDocumentController.shared.document(for: $0) }
        let showsLibraryItem = current?.fileURL.flatMap { library.file(for: $0) } != nil
        let decision = newWindow && existing == nil ? .openNewWindow
            : LibraryOpenDecision.decide(targetAlreadyOpen: existing != nil, windowShowsLibraryItem: showsLibraryItem)
        switch decision {
        case .focusExisting:
            existing?.showWindows()
        case .openNewWindow:
            DocumentOpener.open(url: url)
        case .replaceInWindow:
            guard let current, let window else { return DocumentOpener.open(url: url) }
            let frame = window.frame
            let strip = (window.windowController as? EditorWindowController)?.stripState
            // Il documento è nell'archivio: si salva dove sta, poi la nuova cattura prende la stessa cornice e lo stesso
            // filtro del carosello. Se il salvataggio non riesce la finestra resta com'è: niente modifiche perse.
            current.autosave(withImplicitCancellability: false) { error in
                MainActor.assumeIsolated {
                    if let error {
                        current.presentError(error)
                        return
                    }
                    current.close()
                    DocumentOpener.open(url: url) { document in
                        let controller = document?.windowControllers.first as? EditorWindowController
                        if let strip, let next = controller?.stripState {
                            next.filter = strip.filter
                            next.anchor = strip.anchor
                            next.selection = [item.file]
                        }
                        controller?.window?.setFrame(frame, display: true)
                    }
                }
            }
        }
    }
}
