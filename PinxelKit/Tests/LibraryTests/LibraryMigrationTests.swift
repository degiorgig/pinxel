import Foundation
import Testing
@testable import Library

struct LibraryMigrationTests {
    func parent() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pinxel-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func legacyFolderIsRenamedWithItsFiles() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("Libreria")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: legacy.appendingPathComponent("library.json"))
        let folder = LibraryStore.prepareFolder(in: root)
        #expect(folder.lastPathComponent == "Library")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("library.json").path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test func migrationKeepsBothWhenLibraryExists() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Libreria", "Library"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        #expect(LibraryStore.prepareFolder(in: root).lastPathComponent == "Library")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Libreria").path))
    }

    @Test func noFolderGivesLibrary() throws {
        let root = try parent()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(LibraryStore.prepareFolder(in: root).lastPathComponent == "Library")
    }

    @Test func migrationFailureKeepsUsingLibreria() throws {
        let root = try parent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Libreria"), withIntermediateDirectories: true)
        // Cartella genitore in sola lettura: lo spostamento non riesce.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        #expect(LibraryStore.prepareFolder(in: root).lastPathComponent == "Libreria")
    }
}
