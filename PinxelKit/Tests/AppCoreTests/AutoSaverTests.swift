import Foundation
import Testing
import DocumentModel
import Persistence
@testable import AppCore
import PinxelTestSupport

struct AutoSaverTests {
    let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-autosave-\(UUID().uuidString)")
    }

    func contents() throws -> PinxelFileContents {
        try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 2, metadata: CaptureMetadata(captureDate: date))
    }

    func settings(folder: URL, format: SaveFormat) -> CaptureSettings {
        var settings = CaptureSettings()
        settings.autoSave = true
        settings.saveFolderPath = folder.path
        settings.saveFormat = format
        settings.fileNameTemplate = "'Test' yyyy"
        return settings
    }

    @Test func savesPinxel() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try AutoSaver().save(contents(), settings: settings(folder: folder, format: .pinxel), date: date)
        #expect(url.pathExtension == "pinxel")
        #expect(url.lastPathComponent.hasPrefix("Test "))
        let reread = try PinxelArchive.read(Data(contentsOf: url))
        #expect(reread.document.canvasSize == PixelSize(width: 400, height: 300))
    }

    @Test func savesPNGAtNativePixels() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try AutoSaver().save(contents(), settings: settings(folder: folder, format: .png), date: date)
        let image = try ImageCodec.decode(Data(contentsOf: url))
        #expect(image.width == 400 && image.height == 300)
    }

    @Test func createsMissingFolder() throws {
        let folder = temporaryFolder().appendingPathComponent("nested/deeper")
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent().deletingLastPathComponent()) }
        let url = try AutoSaver().save(contents(), settings: settings(folder: folder, format: .png), date: date)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func unwritableFolderThrows() throws {
        let folder = temporaryFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        #expect(throws: AutoSaveError.folderNotWritable(folder.path)) {
            try AutoSaver().save(contents(), settings: settings(folder: folder, format: .png), date: date)
        }
    }

    @Test func neverOverwrites() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let saver = AutoSaver()
        let first = try saver.save(contents(), settings: settings(folder: folder, format: .png), date: date)
        let second = try saver.save(contents(), settings: settings(folder: folder, format: .png), date: date)
        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    /// The folder chosen in Settings keeps its bookmark: renamed in the Finder, the captures still go into it.
    @Test func followsTheChosenFolderWhenRenamed() throws {
        let parent = temporaryFolder()
        let folder = parent.appendingPathComponent("Captures")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        var settings = settings(folder: folder, format: .png)
        settings.chooseSaveFolder(folder)
        let renamed = parent.appendingPathComponent("Renamed")
        try FileManager.default.moveItem(at: folder, to: renamed)
        let url = try AutoSaver().save(contents(), settings: settings, date: date)
        #expect(url.deletingLastPathComponent().resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path)
    }

    /// A bookmark that no longer resolves falls back to the path.
    @Test func unreadableBookmarkFallsBackToThePath() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = settings(folder: folder, format: .png)
        settings.saveFolderBookmark = Data("not a bookmark".utf8)
        let url = try AutoSaver().save(contents(), settings: settings, date: date)
        #expect(url.deletingLastPathComponent().resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path)
    }
}
