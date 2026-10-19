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
            guard let current, let controller = window?.windowController as? EditorWindowController else {
                return DocumentOpener.open(url: url)
            }
            // Il documento è nell'archivio: si salva dove sta, poi la nuova cattura entra nella stessa finestra (cornice,
            // toolbar e carosello restano). Se il salvataggio non riesce la finestra resta com'è: niente modifiche perse.
            current.autosave(withImplicitCancellability: false) { error in
                MainActor.assumeIsolated {
                    if let error {
                        current.presentError(error)
                        return
                    }
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { document, _, error in
                        if let error {
                            NSApp.presentError(error)
                            return
                        }
                        guard let next = document as? PinxelFileDocument, let model = next.makeEditorModel() else { return }
                        current.removeWindowController(controller)
                        current.close()
                        next.addWindowController(controller)
                        controller.show(model)
                        controller.stripState.selection = [item.file]
                        controller.synchronizeWindowTitleWithDocumentName()
                    }
                }
            }
        }
    }
}
