import Foundation

public enum TemporaryFiles {
    public static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Pinxel", isDirectory: true)
    }

    /// URL of `fileName` in a new folder: two files with the same name never overwrite each other,
    /// and whoever receives them (Finder, Mail, Messages) sees the clean name.
    public static func uniqueURL(fileName: String, root: URL = TemporaryFiles.root, fileManager: FileManager = .default) throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }
}
