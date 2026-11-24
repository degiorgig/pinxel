import DocumentModel
import Foundation
import PinxelTestSupport
import Testing
@testable import AppCore

struct AutoSaverAtomicTests {
    @Test func savingLeavesNoTemporaryFilesAndNeverOverwrites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PinxelAutoSave-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = CaptureSettings()
        settings.saveFolderPath = folder.path
        settings.saveFormat = .png
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 1, metadata: CaptureMetadata())
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let first = try AutoSaver().save(contents, settings: settings, date: date)
        let second = try AutoSaver().save(contents, settings: settings, date: date)
        #expect(first != second)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.count == 2)
        #expect(!names.contains { $0.hasPrefix(".") })
    }

    /// Captures saved at the same moment with the same name template: each gets its own file, none is lost.
    @Test func concurrentSavesNeverShareAFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PinxelAutoSave-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = CaptureSettings()
        settings.saveFolderPath = folder.path
        settings.saveFormat = .png
        let contents = try CaptureDocumentBuilder.make(image: TestImages.quadrants(), scale: 1, metadata: CaptureMetadata())
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let saver = AutoSaver()
        let results = Results()
        let fixed = settings
        DispatchQueue.concurrentPerform(iterations: 6) { _ in
            results.append(Result { try saver.save(contents, settings: fixed, date: date) })
        }
        let urls = try results.all.map { try $0.get() }
        #expect(Set(urls).count == 6)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.filter { $0.hasSuffix(".png") }.count == 6)
        #expect(!names.contains { $0.hasPrefix(".") })
    }

    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Result<URL, Error>] = []
        func append(_ value: Result<URL, Error>) { lock.withLock { values.append(value) } }
        var all: [Result<URL, Error>] { lock.withLock { values } }
    }
}
