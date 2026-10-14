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
}
