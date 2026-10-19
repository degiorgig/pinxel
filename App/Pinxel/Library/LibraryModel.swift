import AppKit
import Library
import Observation
import Persistence

/// L'archivio condiviso da tutte le finestre. Ogni modifica si salva subito in `library.json`.
@MainActor
@Observable
final class LibraryModel {
    private(set) var index = LibraryIndex() {
        didSet {
            guard index != oldValue else { return }
            allTags = index.allTags
            filtered = nil
        }
    }
    /// Le etichette in uso, ricalcolate solo quando cambia l'indice (la striscia le chiede a ogni disegno).
    private(set) var allTags: [String] = []
    @ObservationIgnored private var filtered: (filter: LibraryFilter, items: [Library.LibraryItem])?
    /// Data di modifica dei file noti: quando cambia, la miniatura si rilegge.
    private(set) var thumbnailRevision: [String: Date] = [:]

    @ObservationIgnored let store: LibraryStore
    @ObservationIgnored private let notifier: Notifier
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// `library.json` c'è ma non si legge: finché è così non si riscrive, o cartelle ed etichette andrebbero perse.
    @ObservationIgnored private var indexUnreadable = false
    /// Date di modifica di cartella e indice all'ultimo caricamento: al ritorno su Pinxel si ricarica solo se cambiano.
    @ObservationIgnored private var loadedStamp: [Date?] = []

    init(store: LibraryStore, notifier: Notifier) {
        self.store = store
        self.notifier = notifier
        reload()
        observers.append(NotificationCenter.default.addObserver(forName: .pinxelDocumentDidSave, object: nil, queue: .main) { [weak self] note in
            guard let url = note.object as? URL else { return }
            MainActor.assumeIsolated { self?.documentSaved(at: url) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfChanged() }
        })
    }

    func reload() {
        let load = store.load()
        indexUnreadable = load.problem == .unreadable
        switch load.problem {
        case .corrupt:
            notifier.info(String(localized: "The library index was damaged and has been rebuilt from the files. Folders and tags were lost; a copy is in \(LibraryStore.corruptName)."))
        case .futureVersion:
            notifier.info(String(localized: "The library index comes from a newer version of Pinxel: it was set aside in \(LibraryStore.corruptName) and rebuilt from the files."))
        case .unreadable:
            notifier.info(String(localized: "Can't read the library index: folders and tags won't be saved until it is readable again."))
        case nil:
            break
        }
        // Indice illeggibile: le catture si vedono lo stesso, ma senza perdere cartelle ed etichette già in memoria.
        if load.problem == .unreadable, !index.items.isEmpty {
            index = index.reconciled(withFiles: Set(load.index.items.map(\.file))) { file in load.index.item(file)! }
        } else if load.index != index {
            index = load.index
        }
        loadedStamp = stamp()
        refreshRevisions()
    }

    /// Al ritorno su Pinxel: qualcosa è cambiato nella cartella (file aggiunti o tolti dal Finder) o nell'indice?
    private func reloadIfChanged() {
        if stamp() != loadedStamp { reload() }
    }

    private func stamp() -> [Date?] {
        [store.folder, store.folder.appendingPathComponent(LibraryStore.indexName)].map {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    }

    func add(_ contents: PinxelFileContents) throws -> URL {
        let item = try store.add(contents, to: &index)
        persist()
        refreshRevisions([item.file])
        return store.url(for: item)
    }

    func importFiles(_ urls: [URL]) {
        var added: [String] = []
        for url in urls {
            do { added.append(try store.importFile(at: url, into: &index).file) } catch { notifier.failure(error) }
        }
        persist()
        refreshRevisions(added)
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

    /// Sposta le catture nel Cestino (o, se non c'è, chiede e cancella), poi chiude le finestre di quelle eliminate.
    /// Le finestre si chiudono solo dopo: se l'eliminazione non riesce o si annulla, le modifiche restano.
    func delete(_ files: Set<String>) {
        guard !files.isEmpty else { return }
        let open = NSDocumentController.shared.documents.compactMap { document -> (NSDocument, String)? in
            guard let url = document.fileURL, let file = store.file(for: url), files.contains(file) else { return nil }
            return (document, file)
        }
        defer {
            for (document, file) in open where index.item(file) == nil { document.close() }
        }
        do {
            try store.trash(files, in: &index)
        } catch LibraryError.trashUnavailable {
            let alert = NSAlert()
            alert.messageText = files.count == 1 ? String(localized: "Delete the capture permanently?") : String(localized: "Delete \(files.count) captures permanently?")
            alert.informativeText = String(localized: "The Trash isn't available: they can't be recovered.")
            alert.addButton(withTitle: String(localized: "Delete"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                do { try store.deletePermanently(files, in: &index) } catch { notifier.failure(error) }
            }
        } catch {
            notifier.failure(error)
        }
        persist()
        thumbnailRevision = thumbnailRevision.filter { index.item($0.key) != nil }
    }

    /// Le catture che il filtro mostra; ricalcolate solo quando cambiano indice o filtro.
    func items(for filter: LibraryFilter) -> [Library.LibraryItem] {
        if let filtered, filtered.filter == filter { return filtered.items }
        let items = filter.apply(to: index)
        filtered = (filter, items)
        return items
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
            refreshRevisions([file])
        }
    }

    private func persist() {
        guard !indexUnreadable else { return }
        do {
            try store.save(index)
            loadedStamp = stamp()
        } catch {
            notifier.failure(error)
        }
    }

    /// Rilegge le date di modifica: di tutti i file dopo un caricamento, altrimenti solo di quelli indicati.
    private func refreshRevisions(_ files: [String]? = nil) {
        var next = files == nil ? [:] : thumbnailRevision
        for file in files ?? index.items.map(\.file) {
            let url = store.folder.appendingPathComponent(file)
            next[file] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        if next != thumbnailRevision { thumbnailRevision = next }
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        switch error {
        case LibraryIndexError.emptyName: alert.messageText = String(localized: "The folder name can't be empty.")
        case LibraryIndexError.duplicateName: alert.messageText = String(localized: "A folder with this name already exists.")
        default: alert.messageText = Notifier.message(for: error)
        }
        alert.runModal()
    }
}
