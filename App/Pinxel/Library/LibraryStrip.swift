import AppCore
import AppKit
import Library
import Persistence
import Rendering
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class LibraryStripState {
    var filter = LibraryFilter()
    var selection: Set<String> = []
    /// Ultima miniatura cliccata senza ⇧: punto di partenza per ⇧-clic.
    var anchor: String?
}

/// Carosello in fondo all'editor: filtri sopra, miniature dalla più nuova (spec §2).
struct LibraryStrip: View {
    let library: LibraryModel
    @Bindable var state: LibraryStripState
    /// File della cattura aperta in questa finestra, se è nell'archivio.
    let currentFile: String?
    let open: (Library.LibraryItem, _ newWindow: Bool) -> Void
    @FocusState private var focused: Bool

    private var items: [Library.LibraryItem] { library.items(for: state.filter) }

    var body: some View {
        VStack(spacing: 6) {
            filterBar
            if items.isEmpty {
                Text(library.index.items.isEmpty ? "Le tue catture compariranno qui." : "Nessuna cattura corrisponde al filtro.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(items) { item in thumbnail(item) }
                        }
                        .padding(.horizontal, 12)
                    }
                    .scrollIndicators(.automatic)
                    // Finestra nuova o cattura sostituita: la striscia mostra quella aperta, anche se è vecchia di mesi.
                    .onAppear { if let currentFile { proxy.scrollTo(currentFile, anchor: .center) } }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(height: 110)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onDeleteCommand { library.delete(state.selection) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            importDropped(providers)
            return true
        }
        .accessibilityIdentifier("pinxel.library.strip")
    }

    private func thumbnail(_ item: Library.LibraryItem) -> some View {
        let url = library.url(for: item)
        return LibraryThumbnailView(item: item, url: url, revision: library.thumbnailRevision[item.file] ?? .distantPast,
                                    isCurrent: item.file == currentFile, isSelected: state.selection.contains(item.file))
            .onTapGesture { click(item) }
            .onDrag { dragProvider(for: item, url: url) }
            .contextMenu { contextMenu(for: item) }
    }

    // MARK: Selezione e clic

    private func click(_ item: Library.LibraryItem) {
        focused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if state.selection.contains(item.file) { state.selection.remove(item.file) } else { state.selection.insert(item.file) }
            state.anchor = item.file
        } else if flags.contains(.shift), let anchor = state.anchor,
                  let a = items.firstIndex(where: { $0.file == anchor }), let b = items.firstIndex(where: { $0.file == item.file }) {
            state.selection = Set(items[min(a, b)...max(a, b)].map(\.file))
        } else {
            state.selection = [item.file]
            state.anchor = item.file
            open(item, false)
        }
    }

    /// Il menu agisce sulla selezione se la contiene, altrimenti solo sulla miniatura.
    private func targets(_ item: Library.LibraryItem) -> Set<String> {
        state.selection.contains(item.file) ? state.selection : [item.file]
    }

    // MARK: Barra dei filtri

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu(folderTitle) {
                Picker("Cartella", selection: $state.filter.folder) {
                    Text("Tutte").tag(FolderScope.all)
                    Text("Senza cartella").tag(FolderScope.unfiled)
                    ForEach(sortedFolders) { folder in Text(folder.name).tag(FolderScope.folder(folder.id)) }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Nuova cartella…") {
                    if let name = askName(title: "Nuova cartella", initial: ""), let folder = library.createFolder(named: name) {
                        state.filter.folder = .folder(folder.id)
                    }
                }
                if case .folder(let id) = state.filter.folder, let folder = library.index.folder(id) {
                    Button("Rinomina cartella…") {
                        if let name = askName(title: "Rinomina cartella", initial: folder.name) { _ = library.renameFolder(id, to: name) }
                    }
                    Button("Elimina cartella") {
                        library.deleteFolder(id)
                        state.filter.folder = .all
                    }
                }
            }
            .fixedSize()
            .accessibilityIdentifier("pinxel.library.folderMenu")
            Menu(state.filter.tag.map { "#\($0)" } ?? "Etichetta") {
                Picker("Etichetta", selection: $state.filter.tag) {
                    Text("Tutte").tag(String?.none)
                    ForEach(library.allTags, id: \.self) { tag in Text(tag).tag(Optional(tag)) }
                }
                .pickerStyle(.inline)
            }
            .fixedSize()
            TextField("Cerca", text: $state.filter.text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Spacer()
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
    }

    private var sortedFolders: [LibraryFolder] {
        library.index.folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var folderTitle: String {
        switch state.filter.folder {
        case .all: "Tutte le cartelle"
        case .unfiled: "Senza cartella"
        case .folder(let id): library.index.folder(id)?.name ?? "Tutte le cartelle"
        }
    }

    // MARK: Menu contestuale

    @ViewBuilder private func contextMenu(for item: Library.LibraryItem) -> some View {
        let files = targets(item)
        Button("Copia") { copy(files) }
        Button("Apri in una nuova finestra") { for target in items where files.contains(target.file) { open(target, true) } }
        Menu("Sposta in") {
            Button("Senza cartella") { library.move(files, to: nil) }
            ForEach(sortedFolders) { folder in Button(folder.name) { library.move(files, to: folder.id) } }
            Divider()
            Button("Nuova cartella…") {
                if let name = askName(title: "Nuova cartella", initial: ""), let folder = library.createFolder(named: name) {
                    library.move(files, to: folder.id)
                }
            }
        }
        Menu("Etichette") {
            ForEach(library.allTags, id: \.self) { tag in
                let all = files.allSatisfy { file in library.index.item(file)?.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } ?? false }
                Toggle(tag, isOn: Binding(get: { all }, set: { on in on ? library.addTag(tag, to: files) : library.removeTag(tag, from: files) }))
            }
            Divider()
            Button("Nuova etichetta…") {
                if let tag = askName(title: "Nuova etichetta", initial: "") { library.addTag(tag, to: files) }
            }
        }
        Button("Mostra nel Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(items.filter { files.contains($0.file) }.map { library.url(for: $0) })
        }
        Divider()
        Button("Elimina", role: .destructive) { library.delete(files) }
    }

    // MARK: Appunti, trascinamenti

    private func copy(_ files: Set<String>) {
        let images = items.filter { files.contains($0.file) }.compactMap { renderedPNG(library.url(for: $0)) }
        guard !images.isEmpty else { return NSSound.beep() }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(images.compactMap { NSImage(data: $0) })
    }

    /// PNG composito (annotazioni comprese) in un file temporaneo con il nome della cattura: Finder, altre app e tela.
    private func dragProvider(for item: Library.LibraryItem, url: URL) -> NSItemProvider {
        guard let png = renderedPNG(url),
              let file = try? TemporaryFiles.uniqueURL(fileName: (item.file as NSString).deletingPathExtension + ".png"),
              (try? png.write(to: file)) != nil else { return NSItemProvider() }
        return NSItemProvider(contentsOf: file) ?? NSItemProvider()
    }

    private func renderedPNG(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), let contents = try? PinxelArchive.read(data),
              let assets = try? contents.assetProvider(),
              let image = try? DocumentRenderer().renderImage(contents.document, assets: assets) else { return nil }
        return try? ImageCodec.encode(image, type: .png)
    }

    /// Tutti i file trascinati in un'unica importazione (un solo salvataggio dell'indice).
    private func importDropped(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let collected = DroppedURLs()
        let temporary = TemporaryFiles.root.resolvingSymlinksInPath().path
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                // Le miniature trascinate dalla striscia stessa sono PNG temporanei: non si reimportano.
                if let url, !url.resolvingSymlinksInPath().path.hasPrefix(temporary) { collected.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                let urls = collected.urls
                if !urls.isEmpty { library.importFiles(urls) }
            }
        }
    }

    private func askName(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Annulla")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}

/// URL raccolti dalle callback di `NSItemProvider`, che arrivano su thread qualsiasi.
private final class DroppedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL] = []

    func append(_ url: URL) {
        lock.withLock { stored.append(url) }
    }

    var urls: [URL] { lock.withLock { stored } }
}
