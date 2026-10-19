import Foundation
import Testing
import DocumentModel
import Persistence
import AppCore
@testable import Library
import PinxelTestSupport

/// FileManager con Cestino non disponibile, per il ripiego della cancellazione definitiva.
final class NoTrashFileManager: FileManager, @unchecked Sendable {
    override func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        throw CocoaError(.featureUnsupported)
    }
}

/// FileManager che non può spostare nel Cestino per un motivo diverso dal Cestino assente (permessi).
final class DeniedTrashFileManager: FileManager, @unchecked Sendable {
    override func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

struct LibraryStoreTests {
    let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-library-\(UUID().uuidString)")
    }

    func contents(app: String? = "Safari") throws -> PinxelFileContents {
        try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2,
                                        metadata: CaptureMetadata(captureDate: date, appName: app, windowTitle: "Pagina"))
    }

    func files(in folder: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
    }

    @Test func addWritesAPinxelAndAnEntry() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder, now: { self.date })
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        #expect(item.file.hasSuffix(".pinxel"))
        #expect(item.appName == "Safari" && item.windowTitle == "Pagina")
        #expect(item.pixelWidth == 400 && item.pixelHeight == 300)
        #expect(index.item(item.file) == item)
        let reread = try PinxelArchive.read(Data(contentsOf: store.url(for: item)))
        #expect(reread.document.canvasSize == PixelSize(width: 400, height: 300))
        #expect(LibraryStore.thumbnail(at: store.url(for: item)) != nil)
        #expect(try files(in: folder) == [item.file])
    }

    @Test func twoCapturesInTheSameSecondGetDistinctFiles() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder, now: { self.date })
        var index = LibraryIndex()
        let first = try store.add(contents(), to: &index)
        let second = try store.add(contents(), to: &index)
        #expect(first.file != second.file)
        #expect(second.file.hasSuffix(" 2.pinxel"))
    }

    @Test func saveAndLoadRoundTrip() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        index.addTag("bug", to: [item.file])
        try store.save(index)
        let load = store.load()
        #expect(load.index == index)
        #expect(load.problem == nil)
    }

    @Test func loadReconcilesWithTheFolder() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let kept = try store.add(contents(), to: &index)
        let gone = try store.add(contents(), to: &index)
        try store.save(index)
        try FileManager.default.removeItem(at: store.url(for: gone))
        // Un .pinxel copiato a mano nella cartella.
        try FileManager.default.copyItem(at: store.url(for: kept), to: folder.appendingPathComponent("A mano.pinxel"))
        let load = store.load()
        #expect(Set(load.index.items.map(\.file)) == [kept.file, "A mano.pinxel"])
        #expect(load.index.item("A mano.pinxel")?.appName == "Safari")
    }

    @Test func missingIndexIsBuiltFromTheFiles() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        let load = store.load()
        #expect(load.index.items.map(\.file) == [item.file])
        #expect(load.problem == nil)
    }

    @Test func corruptIndexIsSetAsideAndRebuilt() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        try Data("{ rotto".utf8).write(to: folder.appendingPathComponent(LibraryStore.indexName))
        let load = store.load()
        #expect(load.problem == .corrupt)
        #expect(load.index.items.map(\.file) == [item.file])
        #expect(try Data(contentsOf: folder.appendingPathComponent(LibraryStore.corruptName)) == Data("{ rotto".utf8))
    }

    @Test func futureIndexIsSetAsideAndRebuilt() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let future = Data(#"{"version":2,"folders":[],"items":[]}"#.utf8)
        try future.write(to: folder.appendingPathComponent(LibraryStore.indexName))
        let load = store.load()
        #expect(load.problem == .futureVersion)
        #expect(try Data(contentsOf: folder.appendingPathComponent(LibraryStore.corruptName)) == future)
    }

    @Test func unreadablePinxelStillHasAnEntry() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("non è uno zip".utf8).write(to: folder.appendingPathComponent("Rotto.pinxel"))
        let load = LibraryStore(folder: folder).load()
        #expect(load.index.item("Rotto.pinxel")?.pixelWidth == 0)
    }

    @Test func ignoresOtherFilesInTheFolder() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("note.txt"))
        try Data().write(to: folder.appendingPathComponent(".abc.tmp"))
        #expect(LibraryStore(folder: folder).load().index.items.isEmpty)
    }

    @Test func importCopiesImagesAndPinxelFiles() throws {
        let folder = temporaryFolder()
        let outside = temporaryFolder()
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: outside) }
        let png = outside.appendingPathComponent("foto.png")
        try ImageCodec.encode(TestImages.quadrants(), type: .png).write(to: png)
        let store = LibraryStore(folder: folder, now: { self.date })
        var index = LibraryIndex()
        let fromPNG = try store.importFile(at: png, into: &index)
        #expect(fromPNG.pixelWidth == 400)
        #expect(FileManager.default.fileExists(atPath: png.path))
        let fromPinxel = try store.importFile(at: store.url(for: fromPNG), into: &index)
        #expect(fromPinxel.file != fromPNG.file)
        let text = outside.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: text)
        #expect(throws: LibraryError.unsupportedFile("a.txt")) { try store.importFile(at: text, into: &index) }
        #expect(index.items.count == 2)
    }

    @Test func refreshedItemReadsNewSize() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        // Il documento salvato dall'editor ora è più piccolo (ritaglio).
        let smaller = try CaptureDocumentBuilder.make(image: TestImages.quadrants(width: 100, height: 50), scale: 2, metadata: CaptureMetadata())
        let data = try PinxelArchive.write(document: smaller.document, images: smaller.images, thumbnail: Data([1]), appVersion: "0.1.0")
        try data.write(to: store.url(for: item))
        store.refreshed(item.file, in: &index)
        #expect(index.item(item.file)?.pixelWidth == 100)
        #expect(index.item(item.file)?.pixelHeight == 50)
    }

    /// L'editor ritaglia aggiungendo un'operazione: `canvasSize` resta quello della cattura.
    func cropped(_ contents: PinxelFileContents) throws -> Data {
        var document = contents.document
        document.imageOperations.append(.crop(PixelRect(x: 0, y: 0, width: 120, height: 80)))
        return try PinxelArchive.write(document: document, images: contents.images, thumbnail: Data([1]), appVersion: "0.1.0")
    }

    @Test func refreshedItemReadsCroppedSize() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        try cropped(contents()).write(to: store.url(for: item))
        store.refreshed(item.file, in: &index)
        #expect(index.item(item.file)?.pixelWidth == 120)
        #expect(index.item(item.file)?.pixelHeight == 80)
    }

    @Test func fileFoundInTheFolderUsesCroppedSize() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try cropped(contents()).write(to: folder.appendingPathComponent("Ritagliata.pinxel"))
        let load = LibraryStore(folder: folder).load()
        #expect(load.index.item("Ritagliata.pinxel")?.pixelWidth == 120)
        #expect(load.index.item("Ritagliata.pinxel")?.pixelHeight == 80)
    }

    @Test func trashRemovesFilesAndEntries() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        try store.trash([item.file], in: &index)
        #expect(index.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: item).path))
    }

    @Test func trashUnavailableThrowsAndKeepsEverything() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder, fileManager: NoTrashFileManager())
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        #expect(throws: LibraryError.trashUnavailable) { try store.trash([item.file], in: &index) }
        #expect(index.items.count == 1)
        try store.deletePermanently([item.file], in: &index)
        #expect(index.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: item).path))
    }

    @Test func unwritableFolderThrows() throws {
        let parent = temporaryFolder()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            try? FileManager.default.removeItem(at: parent)
        }
        let store = LibraryStore(folder: parent.appendingPathComponent("Libreria"))
        var index = LibraryIndex()
        #expect(throws: LibraryError.notWritable(parent.appendingPathComponent("Libreria").path)) { try store.add(contents(), to: &index) }
        #expect(index.items.isEmpty)
    }

    @Test func fileForURLOnlyAcceptsDirectChildren() throws {
        let folder = temporaryFolder()
        let store = LibraryStore(folder: folder)
        #expect(store.file(for: folder.appendingPathComponent("a.pinxel")) == "a.pinxel")
        #expect(store.file(for: folder.appendingPathComponent("sub/a.pinxel")) == nil)
        #expect(store.file(for: URL(fileURLWithPath: "/tmp/a.pinxel")) == nil)
    }

    @Test func unreadableIndexIsNeitherOverwrittenNorSetAside() throws {
        let folder = temporaryFolder()
        let indexURL = folder.appendingPathComponent(LibraryStore.indexName)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        _ = try index.createFolder(named: "Lavoro")
        try store.save(index)
        let saved = try Data(contentsOf: indexURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: indexURL.path)
        let load = store.load()
        #expect(load.problem == .unreadable)
        #expect(load.index.items.map(\.file) == [item.file])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: indexURL.path)
        #expect(try Data(contentsOf: indexURL) == saved)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent(LibraryStore.corruptName).path))
    }

    @Test func otherTrashErrorsAreNotReportedAsMissingTrash() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder, fileManager: DeniedTrashFileManager())
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        #expect(throws: LibraryError.writeFailed(store.url(for: item).path)) { try store.trash([item.file], in: &index) }
        #expect(index.items.count == 1)
    }

    @Test func newURLIsFreeAndInsideTheFolder() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(folder: folder)
        var index = LibraryIndex()
        let item = try store.add(contents(), to: &index)
        let url = try store.newURL(for: date)
        #expect(store.file(for: url) != nil)
        #expect(url.lastPathComponent != item.file)
        #expect(url.pathExtension == "pinxel")
    }
}
