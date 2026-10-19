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
            guard let current, let frame = window?.frame else { return DocumentOpener.open(url: url) }
            // Il documento è nell'archivio: si salva dove sta, poi la nuova cattura prende la stessa cornice.
            current.autosave(withImplicitCancellability: false) { _ in
                MainActor.assumeIsolated {
                    current.close()
                    DocumentOpener.open(url: url) { document in
                        document?.windowControllers.first?.window?.setFrame(frame, display: true)
                    }
                }
            }
        }
    }
}
