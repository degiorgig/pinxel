import Foundation

public enum TemporaryFiles {
    public static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Pinxel", isDirectory: true)
    }

    /// URL di `fileName` in una cartella nuova: due file con lo stesso nome non si sovrascrivono mai,
    /// e chi li riceve (Finder, Mail, Messaggi) vede il nome pulito.
    public static func uniqueURL(fileName: String, root: URL = TemporaryFiles.root, fileManager: FileManager = .default) throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }
}
