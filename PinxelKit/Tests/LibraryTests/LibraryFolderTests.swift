import Foundation
import Testing
@testable import Library

struct LibraryFolderTests {
    @Test func theOfficialFolderIsLibrary() {
        // `Library` in tutte le lingue; la vecchia `Libreria` non si sposta né si legge.
        let folder = LibraryStore.defaultFolder
        #expect(folder.lastPathComponent == "Library")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Pinxel")
    }

    @Test func theDamagedIndexCopyHasAnEnglishName() {
        #expect(LibraryStore.corruptName == "library.json.corrupt")
    }
}
