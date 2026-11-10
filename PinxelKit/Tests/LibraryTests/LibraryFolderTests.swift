import Foundation
import Testing
@testable import Library

struct LibraryFolderTests {
    @Test func theOfficialFolderIsLibrary() {
        // `Library` in all languages; the old `Libreria` is neither moved nor read.
        let folder = LibraryStore.defaultFolder(sandboxed: false)
        #expect(folder.lastPathComponent == "Library")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Pinxel")
        #expect(folder.deletingLastPathComponent().deletingLastPathComponent()
            == FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0])
    }

    @Test func inTheSandboxTheLibraryStaysInTheAppContainer() {
        // The App Store build has no access to Pictures: the library lives in Application Support.
        let folder = LibraryStore.defaultFolder(sandboxed: true)
        #expect(folder.lastPathComponent == "Library")
        #expect(folder.deletingLastPathComponent().lastPathComponent == "Pinxel")
        #expect(folder.deletingLastPathComponent().deletingLastPathComponent()
            == FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
    }

    @Test func theDamagedIndexCopyHasAnEnglishName() {
        #expect(LibraryStore.corruptName == "library.json.corrupt")
    }
}
