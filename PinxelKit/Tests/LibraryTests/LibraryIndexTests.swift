import Foundation
import Testing
@testable import Library

struct LibraryIndexTests {
    func item(_ file: String, added: TimeInterval = 0, tags: [String] = [], folder: UUID? = nil) -> LibraryItem {
        LibraryItem(file: file, added: Date(timeIntervalSince1970: added), captureDate: Date(timeIntervalSince1970: added),
                    appName: nil, windowTitle: nil, pixelWidth: 10, pixelHeight: 10, folder: folder, tags: tags)
    }

    @Test func addReplacesTheSameFile() {
        var index = LibraryIndex()
        index.add(item("a.pinxel"))
        var changed = item("a.pinxel")
        changed.pixelWidth = 99
        index.add(changed)
        #expect(index.items.count == 1)
        #expect(index.item("a.pinxel")?.pixelWidth == 99)
    }

    @Test func foldersRejectEmptyAndDuplicateNames() throws {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "  Lavoro ")
        #expect(work.name == "Lavoro")
        #expect(throws: LibraryIndexError.emptyName) { try index.createFolder(named: "   ") }
        #expect(throws: LibraryIndexError.duplicateName) { try index.createFolder(named: "lavoro") }
        let home = try index.createFolder(named: "Casa")
        #expect(throws: LibraryIndexError.duplicateName) { try index.renameFolder(home.id, to: "LAVORO") }
        try index.renameFolder(home.id, to: "Casa mia")
        #expect(index.folder(home.id)?.name == "Casa mia")
    }

    @Test func deletingAFolderKeepsItsCaptures() throws {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "Lavoro")
        index.add(item("a.pinxel", folder: work.id))
        index.deleteFolder(work.id)
        #expect(index.folders.isEmpty)
        #expect(index.item("a.pinxel")?.folder == nil)
    }

    @Test func moveSetsAndClearsTheFolder() throws {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "Lavoro")
        index.add(item("a.pinxel"))
        index.add(item("b.pinxel"))
        index.move(["a.pinxel", "b.pinxel"], to: work.id)
        #expect(index.items.allSatisfy { $0.folder == work.id })
        index.move(["a.pinxel"], to: nil)
        #expect(index.item("a.pinxel")?.folder == nil)
    }

    @Test func tagsAreCaseInsensitiveAndKeepTheFirstSpelling() {
        var index = LibraryIndex()
        index.add(item("a.pinxel"))
        index.add(item("b.pinxel"))
        index.addTag("Bug", to: ["a.pinxel"])
        index.addTag("bug ", to: ["a.pinxel", "b.pinxel"])
        #expect(index.item("a.pinxel")?.tags == ["Bug"])
        #expect(index.item("b.pinxel")?.tags == ["Bug"])
        index.addTag("   ", to: ["a.pinxel"])
        #expect(index.item("a.pinxel")?.tags == ["Bug"])
        index.removeTag("BUG", from: ["a.pinxel"])
        #expect(index.item("a.pinxel")?.tags == [])
        #expect(index.allTags == ["Bug"])
        index.removeTag("bug", from: ["b.pinxel"])
        #expect(index.allTags.isEmpty)
    }

    @Test func allTagsAreSortedIgnoringCase() {
        var index = LibraryIndex()
        index.add(item("a.pinxel", tags: ["zeta", "Alfa"]))
        index.add(item("b.pinxel", tags: ["beta"]))
        #expect(index.allTags == ["Alfa", "beta", "zeta"])
    }

    @Test func reconcileAddsNewFilesAndDropsMissingOnes() throws {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "Lavoro")
        index.add(item("kept.pinxel", tags: ["x"], folder: work.id))
        index.add(item("gone.pinxel"))
        var orphan = item("orphan.pinxel")
        orphan.folder = UUID()
        index.add(orphan)
        let result = index.reconciled(withFiles: ["kept.pinxel", "new.pinxel", "orphan.pinxel"]) { self.item($0, added: 5) }
        #expect(Set(result.items.map(\.file)) == ["kept.pinxel", "new.pinxel", "orphan.pinxel"])
        #expect(result.item("kept.pinxel")?.tags == ["x"])
        #expect(result.item("kept.pinxel")?.folder == work.id)
        #expect(result.item("new.pinxel")?.added == Date(timeIntervalSince1970: 5))
        #expect(result.item("orphan.pinxel")?.folder == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        var index = LibraryIndex()
        let work = try index.createFolder(named: "Lavoro")
        index.add(item("a.pinxel", tags: ["bug"], folder: work.id))
        let data = try JSONEncoder().encode(index)
        #expect(try JSONDecoder().decode(LibraryIndex.self, from: data) == index)
    }

    @Test func unreadableItemsAreSkippedAndUnknownFieldsIgnored() throws {
        let json = """
        {"version":1,"folders":[],"items":[
          {"file":"a.pinxel","added":0,"captureDate":0,"pixelWidth":1,"pixelHeight":1,"tags":[],"future":"x"},
          {"file":"broken.pinxel"}
        ]}
        """
        let index = try JSONDecoder().decode(LibraryIndex.self, from: Data(json.utf8))
        #expect(index.items.map(\.file) == ["a.pinxel"])
    }

    @Test func futureVersionIsRejected() {
        let json = #"{"version":2,"folders":[],"items":[]}"#
        #expect(throws: LibraryIndexError.futureVersion(2)) { try JSONDecoder().decode(LibraryIndex.self, from: Data(json.utf8)) }
    }
}
