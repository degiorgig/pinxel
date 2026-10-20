import Foundation
import Testing
@testable import Library

struct LibraryFilterTests {
    let utc = TimeZone(identifier: "UTC")!

    func makeIndex() throws -> (LibraryIndex, LibraryFolder) {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "Lavoro Città")
        // 2026-10-19 08:00 UTC e 2026-10-18 08:00 UTC
        index.add(LibraryItem(file: "new.pinxel", added: Date(timeIntervalSince1970: 1_792_396_800), captureDate: Date(timeIntervalSince1970: 1_792_396_800),
                              appName: "Safari", windowTitle: "Café — Menu", pixelWidth: 1, pixelHeight: 1, folder: work.id, tags: ["Bug"]))
        index.add(LibraryItem(file: "old.pinxel", added: Date(timeIntervalSince1970: 1_792_310_400), captureDate: Date(timeIntervalSince1970: 1_792_310_400),
                              appName: "Mail", windowTitle: nil, pixelWidth: 1, pixelHeight: 1))
        return (index, work)
    }

    @Test func allIsNewestFirst() throws {
        let (index, _) = try makeIndex()
        #expect(LibraryFilter().apply(to: index, timeZone: utc).map(\.file) == ["new.pinxel", "old.pinxel"])
    }

    @Test func folderScopes() throws {
        let (index, work) = try makeIndex()
        var filter = LibraryFilter()
        filter.folder = .folder(work.id)
        #expect(filter.apply(to: index, timeZone: utc).map(\.file) == ["new.pinxel"])
        filter.folder = .unfiled
        #expect(filter.apply(to: index, timeZone: utc).map(\.file) == ["old.pinxel"])
    }

    @Test func tagIgnoresCase() throws {
        let (index, _) = try makeIndex()
        var filter = LibraryFilter()
        filter.tag = "bug"
        #expect(filter.apply(to: index, timeZone: utc).map(\.file) == ["new.pinxel"])
    }

    @Test func textFoldsCaseAndAccents() throws {
        let (index, _) = try makeIndex()
        var filter = LibraryFilter()
        for text in ["cafe", "SAFARI", "citta", "bug", "2026-10-19"] {
            filter.text = text
            #expect(filter.apply(to: index, timeZone: utc).map(\.file) == ["new.pinxel"], "\(text)")
        }
        filter.text = "2026-10-18"
        #expect(filter.apply(to: index, timeZone: utc).map(\.file) == ["old.pinxel"])
    }

    @Test func everyWordMustMatchAndFiltersCombine() throws {
        let (index, work) = try makeIndex()
        var filter = LibraryFilter()
        filter.text = "safari menu"
        #expect(filter.apply(to: index, timeZone: utc).count == 1)
        filter.text = "safari mail"
        #expect(filter.apply(to: index, timeZone: utc).isEmpty)
        filter.text = "mail"
        filter.folder = .folder(work.id)
        #expect(filter.apply(to: index, timeZone: utc).isEmpty)
    }

    /// Spec §1 criterion 4: the strip recalculates filter and labels at every change; with 2000 captures it must stay fast.
    @Test func twoThousandCapturesFilterQuickly() {
        var index = LibraryIndex()
        for i in 0..<2000 {
            index.add(LibraryItem(file: "c\(i).pinxel", added: Date(timeIntervalSince1970: Double(i)), captureDate: Date(timeIntervalSince1970: Double(i)),
                                  appName: "App \(i % 20)", windowTitle: "Titolo \(i)", pixelWidth: 1, pixelHeight: 1, tags: ["tag\(i % 50)", "comune"]))
        }
        var filter = LibraryFilter()
        filter.text = "app 7 titolo"
        let start = Date()
        for _ in 0..<5 {
            _ = filter.apply(to: index, timeZone: utc)
            _ = index.allTags
        }
        // Shared CI runners are a few times slower than a Mac and their timing varies.
        let limit = ProcessInfo.processInfo.environment["CI"] == nil ? 0.05 : 0.2
        #expect(Date().timeIntervalSince(start) / 5 < limit)
    }
}
