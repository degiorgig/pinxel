import Foundation
import Testing
@testable import Library

struct LibraryFolderTests {
    @Test func theOfficialFolderIsLibrary() {
        // `Library` in all languages; the old `Libreria` is neither moved nor read.
        let folder = LibraryStore.defaultFolder
        #expect(folder.lastPathComponent == "Library")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Pinxel")
    }

    @Test func theDamagedIndexCopyHasAnEnglishName() {
        #expect(LibraryStore.corruptName == "library.json.corrupt")
    }
}
