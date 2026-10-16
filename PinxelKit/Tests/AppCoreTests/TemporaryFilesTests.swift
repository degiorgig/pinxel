import Foundation
import Testing
@testable import AppCore

struct TemporaryFilesTests {
    @Test func sameNameGivesDifferentURLsInExistingFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PinxelTemp-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try TemporaryFiles.uniqueURL(fileName: "Pinxel.png", root: root)
        let second = try TemporaryFiles.uniqueURL(fileName: "Pinxel.png", root: root)
        #expect(first != second)
        #expect(first.lastPathComponent == "Pinxel.png" && second.lastPathComponent == "Pinxel.png")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: first.deletingLastPathComponent().path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(first.path.hasPrefix(root.path))
    }
}
