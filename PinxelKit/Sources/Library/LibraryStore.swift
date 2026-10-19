import AppCore
import DocumentModel
import Foundation
import OSLog
import Persistence
import UniformTypeIdentifiers

public enum LibraryError: Error, Equatable {
    case notWritable(String)
    case writeFailed(String)
    case unsupportedFile(String)
    case trashUnavailable
}

public enum LibraryLoadProblem: Equatable, Sendable {
    /// `library.json` era rovinato: messo da parte e ricostruito dai file.
    case corrupt
    /// `library.json` è di una versione più recente: messo da parte e ricostruito dai file.
    case futureVersion
    /// `library.json` c'è ma non si legge (permessi, disco): non si tocca, l'indice in memoria viene dai file.
    case unreadable
}

public struct LibraryLoad: Sendable {
    public var index: LibraryIndex
    public var problem: LibraryLoadProblem?
}

/// Tutto ciò che tocca la cartella dell'archivio. Si usa dal thread principale; solo `thumbnail(at:)` va bene altrove.
public final class LibraryStore {
    public static let indexName = "library.json"
    public static let corruptName = "library.json.rovinato"

    public static let defaultFolderName = "Library"
    public static let legacyFolderName = "Libreria"
    private static let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "library")

    public static var defaultFolder: URL {
        prepareFolder(in: FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pinxel", isDirectory: true))
    }

    /// La cartella dell'archivio dentro `parent`: `Library`, ricavata spostando `Libreria` la prima volta.
    /// Se lo spostamento non riesce si continua con `Libreria` (niente si perde, si riprova al prossimo avvio).
    public static func prepareFolder(in parent: URL, fileManager: FileManager = .default) -> URL {
        let folder = parent.appendingPathComponent(defaultFolderName, isDirectory: true)
        let legacy = parent.appendingPathComponent(legacyFolderName, isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path), !fileManager.fileExists(atPath: folder.path) else { return folder }
        do {
            try fileManager.moveItem(at: legacy, to: folder)
            return folder
        } catch {
            logger.notice("Libreria non spostata in Library: \(error.localizedDescription, privacy: .public)")
            return legacy
        }
    }

    public let folder: URL
    private let fileManager: FileManager
    private let appVersion: String
    private let now: () -> Date

    public init(folder: URL, fileManager: FileManager = .default, appVersion: String = "0.1.0", now: @escaping () -> Date = Date.init) {
        self.folder = folder.standardizedFileURL
        self.fileManager = fileManager
        self.appVersion = appVersion
        self.now = now
    }

    private var indexURL: URL { folder.appendingPathComponent(Self.indexName) }

    public func url(for item: LibraryItem) -> URL {
        folder.appendingPathComponent(item.file)
    }

    public func file(for url: URL) -> String? {
        let standardized = url.standardizedFileURL
        guard standardized.deletingLastPathComponent().path == folder.path else { return nil }
        return standardized.lastPathComponent
    }

    // MARK: Indice

    public func load() -> LibraryLoad {
        var index = LibraryIndex()
        var problem: LibraryLoadProblem?
        if fileManager.fileExists(atPath: indexURL.path) {
            do {
                let data = try Data(contentsOf: indexURL)
                do {
                    index = try Self.decoder.decode(LibraryIndex.self, from: data)
                } catch {
                    problem = error as? LibraryIndexError == nil ? .corrupt : .futureVersion
                    // Senza la copia messa da parte l'indice non si riscrive: cartelle ed etichette restano recuperabili.
                    let corrupt = folder.appendingPathComponent(Self.corruptName)
                    try? fileManager.removeItem(at: corrupt)
                    do { try fileManager.moveItem(at: indexURL, to: corrupt) } catch { problem = .unreadable }
                }
            } catch {
                problem = .unreadable
            }
        }
        let reconciled = index.reconciled(withFiles: pinxelFiles()) { makeItem(file: $0) }
        if problem != .unreadable, reconciled != index || problem != nil { try? save(reconciled) }
        return LibraryLoad(index: reconciled, problem: problem)
    }

    public func save(_ index: LibraryIndex) throws {
        try ensureFolder()
        do {
            try Self.encoder.encode(index).write(to: indexURL, options: .atomic)
        } catch {
            throw LibraryError.writeFailed(indexURL.path)
        }
    }

    // MARK: Catture

    public func add(_ contents: PinxelFileContents, to index: inout LibraryIndex) throws -> LibraryItem {
        try ensureFolder()
        let baseName = FileNamer.baseName(template: FileNamer.defaultTemplate, date: contents.document.metadata.captureDate)
        let url = FileNamer.uniqueURL(in: folder, baseName: baseName, fileExtension: "pinxel", fileManager: fileManager)
        do {
            let assets = try contents.assetProvider()
            let thumbnail = try Thumbnailer.make(contents.document, assets: assets)
            let data = try PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: thumbnail, appVersion: appVersion)
            try write(data, to: url)
        } catch {
            throw LibraryError.writeFailed(url.path)
        }
        let item = item(file: url.lastPathComponent, document: contents.document, added: now())
        index.add(item)
        return item
    }

    /// Un nome libero nell'archivio, per salvarci un documento che ancora non c'è (per esempio uno senza titolo).
    public func newURL(for date: Date) throws -> URL {
        try ensureFolder()
        let baseName = FileNamer.baseName(template: FileNamer.defaultTemplate, date: date)
        return FileNamer.uniqueURL(in: folder, baseName: baseName, fileExtension: "pinxel", fileManager: fileManager)
    }

    /// Copia nell'archivio un'immagine o un `.pinxel`; l'originale resta com'è.
    public func importFile(at source: URL, into index: inout LibraryIndex) throws -> LibraryItem {
        let name = source.lastPathComponent
        guard let data = try? Data(contentsOf: source) else { throw LibraryError.unsupportedFile(name) }
        if source.pathExtension.lowercased() == "pinxel" {
            guard let document = try? PinxelArchive.readDocument(data) else { throw LibraryError.unsupportedFile(name) }
            try ensureFolder()
            let url = FileNamer.uniqueURL(in: folder, baseName: source.deletingPathExtension().lastPathComponent, fileExtension: "pinxel", fileManager: fileManager)
            do { try write(data, to: url) } catch { throw LibraryError.writeFailed(url.path) }
            let item = item(file: url.lastPathComponent, document: document, added: now())
            index.add(item)
            return item
        }
        guard let contents = try? ImageImport.contents(fromImageData: data) else { throw LibraryError.unsupportedFile(name) }
        return try add(contents, to: &index)
    }

    /// Dopo un salvataggio dall'editor: dimensioni (ritaglio, ridimensiona) rilette dal file.
    public func refreshed(_ file: String, in index: inout LibraryIndex) {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(file), options: .mappedIfSafe),
              let document = try? PinxelArchive.readDocument(data) else { return }
        index.update(file, pixelWidth: document.imageSize.width, pixelHeight: document.imageSize.height)
    }

    public func trash(_ files: Set<String>, in index: inout LibraryIndex) throws {
        var removed: Set<String> = []
        defer { index.remove(removed) }
        for file in files.sorted() {
            let url = folder.appendingPathComponent(file)
            guard fileManager.fileExists(atPath: url.path) else {
                removed.insert(file)
                continue
            }
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                removed.insert(file)
            } catch let error as CocoaError where error.code == .featureUnsupported || error.code == .fileWriteVolumeReadOnly {
                throw LibraryError.trashUnavailable
            } catch {
                throw LibraryError.writeFailed(url.path)
            }
        }
    }

    public func deletePermanently(_ files: Set<String>, in index: inout LibraryIndex) throws {
        var removed: Set<String> = []
        defer { index.remove(removed) }
        for file in files.sorted() {
            let url = folder.appendingPathComponent(file)
            if fileManager.fileExists(atPath: url.path) {
                do { try fileManager.removeItem(at: url) } catch { throw LibraryError.writeFailed(url.path) }
            }
            removed.insert(file)
        }
    }

    /// Miniatura PNG salvata nel file; legge senza decodificare le immagini.
    public static func thumbnail(at url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return PinxelArchive.readThumbnail(data)
    }

    // MARK: Interni

    private func ensureFolder() throws {
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.notWritable(folder.path)
        }
        guard fileManager.isWritableFile(atPath: folder.path) else { throw LibraryError.notWritable(folder.path) }
    }

    /// File nascosto e poi spostamento: niente file a metà, e `moveItem` non sovrascrive.
    private func write(_ data: Data, to url: URL) throws {
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        do {
            try fileManager.moveItem(at: temporary, to: url)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func pinxelFiles() -> Set<String> {
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names.filter { !$0.hasPrefix(".") && ($0 as NSString).pathExtension.lowercased() == "pinxel" })
    }

    /// Voce per un file trovato nella cartella; se il file è illeggibile, dimensioni 0 (miniatura di errore).
    private func makeItem(file: String) -> LibraryItem {
        let url = folder.appendingPathComponent(file)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let created = (attributes?[.creationDate] as? Date) ?? now()
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe), let document = try? PinxelArchive.readDocument(data) {
            return item(file: file, document: document, added: created)
        }
        return LibraryItem(file: file, added: Self.whole(created), captureDate: Self.whole(created), appName: nil, windowTitle: nil,
                           pixelWidth: 0, pixelHeight: 0)
    }

    private func item(file: String, document: PinxelDocument, added: Date) -> LibraryItem {
        LibraryItem(file: file, added: Self.whole(added), captureDate: Self.whole(document.metadata.captureDate),
                    appName: document.metadata.appName, windowTitle: document.metadata.windowTitle,
                    pixelWidth: document.imageSize.width, pixelHeight: document.imageSize.height)
    }

    /// `library.json` tiene le date al secondo (ISO 8601): l'indice in memoria deve essere uguale a quello riletto.
    private static func whole(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
