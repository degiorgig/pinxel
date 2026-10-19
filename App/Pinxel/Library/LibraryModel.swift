import AppKit
import Library
import Observation
import Persistence

/// L'archivio condiviso da tutte le finestre. Ogni modifica si salva subito in `library.json`.
@MainActor
@Observable
final class LibraryModel {
    private(set) var index = LibraryIndex()
    /// Data di modifica dei file noti: quando cambia, la miniatura si rilegge.
    private(set) var thumbnailRevision: [String: Date] = [:]

    @ObservationIgnored let store: LibraryStore
    @ObservationIgnored private let notifier: Notifier
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(store: LibraryStore, notifier: Notifier) {
        self.store = store
        self.notifier = notifier
        reload()
        observers.append(NotificationCenter.default.addObserver(forName: .pinxelDocumentDidSave, object: nil, queue: .main) { [weak self] note in
            guard let url = note.object as? URL else { return }
            MainActor.assumeIsolated { self?.documentSaved(at: url) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
    }

    func reload() {
        let load = store.load()
        if load.setAsideCorruptIndex {
            notifier.info("L'indice della libreria era danneggiato: ricostruito dai file. Cartelle ed etichette sono andate perse; la copia è in \(LibraryStore.corruptName).")
        }
        if load.index != index { index = load.index }
        refreshRevisions()
    }

    func add(_ contents: PinxelFileContents) throws -> URL {
        let item = try store.add(contents, to: &index)
        persist()
        refreshRevisions()
        return store.url(for: item)
    }

    func importFiles(_ urls: [URL]) {
        for url in urls {
            do { _ = try store.importFile(at: url, into: &index) } catch { notifier.failure(error) }
        }
        persist()
        refreshRevisions()
    }

    func move(_ files: Set<String>, to folder: UUID?) { index.move(files, to: folder); persist() }
    func addTag(_ tag: String, to files: Set<String>) { index.addTag(tag, to: files); persist() }
    func removeTag(_ tag: String, from files: Set<String>) { index.removeTag(tag, from: files); persist() }
    func deleteFolder(_ id: UUID) { index.deleteFolder(id); persist() }

    func createFolder(named name: String) -> LibraryFolder? {
        do {
            let folder = try index.createFolder(named: name)
            persist()
            return folder
        } catch {
            present(error)
            return nil
        }
    }

    func renameFolder(_ id: UUID, to name: String) -> Bool {
        do {
            try index.renameFolder(id, to: name)
            persist()
            return true
        } catch {
            present(error)
            return false
        }
    }

    /// Chiude le finestre aperte su queste catture, poi le sposta nel Cestino (o, se non c'è, chiede e cancella).
    func delete(_ files: Set<String>) {
        guard !files.isEmpty else { return }
        for document in NSDocumentController.shared.documents {
            if let url = document.fileURL, let file = store.file(for: url), files.contains(file) { document.close() }
        }
        do {
            try store.trash(files, in: &index)
        } catch LibraryError.trashUnavailable {
            let alert = NSAlert()
            alert.messageText = files.count == 1 ? "Eliminare definitivamente la cattura?" : "Eliminare definitivamente \(files.count) catture?"
            alert.informativeText = "Il Cestino non è disponibile: non si potranno recuperare."
            alert.addButton(withTitle: "Elimina")
            alert.addButton(withTitle: "Annulla")
            if alert.runModal() == .alertFirstButtonReturn {
                do { try store.deletePermanently(files, in: &index) } catch { notifier.failure(error) }
            }
        } catch {
            notifier.failure(error)
        }
        persist()
        refreshRevisions()
    }

    func file(for url: URL) -> String? { store.file(for: url).flatMap { index.item($0) != nil ? $0 : nil } }
    func url(for item: Library.LibraryItem) -> URL { store.url(for: item) }

    private func documentSaved(at url: URL) {
        guard let file = store.file(for: url) else { return }
        if index.item(file) == nil {
            reload()
        } else {
            store.refreshed(file, in: &index)
            persist()
            refreshRevisions()
        }
    }

    private func persist() {
        do { try store.save(index) } catch { notifier.failure(error) }
    }

    private func refreshRevisions() {
        var next: [String: Date] = [:]
        for item in index.items {
            let date = (try? store.url(for: item).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            next[item.file] = date
        }
        if next != thumbnailRevision { thumbnailRevision = next }
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        switch error {
        case LibraryIndexError.emptyName: alert.messageText = "Il nome della cartella non può essere vuoto."
        case LibraryIndexError.duplicateName: alert.messageText = "Esiste già una cartella con questo nome."
        default: alert.messageText = Notifier.message(for: error)
        }
        alert.runModal()
    }
}
