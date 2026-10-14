import Foundation
import Testing
@testable import AppCore

struct FileNamerTests {
    let date: Date = {
        var components = DateComponents(year: 2026, month: 10, day: 14, hour: 15, minute: 42, second: 10)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    @Test func defaultTemplate() {
        #expect(FileNamer.baseName(template: FileNamer.defaultTemplate, date: date, timeZone: TimeZone(identifier: "UTC")!)
            == "Pinxel 2026-10-14 at 15.42.10")
    }

    @Test func unsafeCharactersAreReplaced() {
        #expect(FileNamer.baseName(template: "yyyy/MM/dd HH:mm", date: date, timeZone: TimeZone(identifier: "UTC")!)
            == "2026-10-14 15-42")
        #expect(FileNamer.baseName(template: "", date: date, timeZone: TimeZone(identifier: "UTC")!) == "Pinxel")
    }

    @Test func uniqueURLAppendsCounter() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = FileNamer.uniqueURL(in: folder, baseName: "Cattura", fileExtension: "png")
        #expect(first.lastPathComponent == "Cattura.png")
        try Data().write(to: first)
        let second = FileNamer.uniqueURL(in: folder, baseName: "Cattura", fileExtension: "png")
        #expect(second.lastPathComponent == "Cattura 2.png")
        try Data().write(to: second)
        #expect(FileNamer.uniqueURL(in: folder, baseName: "Cattura", fileExtension: "png").lastPathComponent == "Cattura 3.png")
    }
}
