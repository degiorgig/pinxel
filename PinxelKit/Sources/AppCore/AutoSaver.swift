import DocumentModel
import Foundation
import Persistence
import Rendering
import UniformTypeIdentifiers

public enum AutoSaveError: Error, Equatable {
    case folderNotWritable(String)
    case writeFailed(String)
}

/// Runs off the main thread. `FileManager` is not marked `Sendable`, but its methods are thread safe as long as it has no
/// delegate, which this one never gets.
public struct AutoSaver: @unchecked Sendable {
    private let fileManager: FileManager
    private let appVersion: String

    public init(fileManager: FileManager = .default, appVersion: String = "0.1.0") {
        self.fileManager = fileManager
        self.appVersion = appVersion
    }

    /// Writes the capture into the settings folder without ever overwriting existing files.
    public func save(_ contents: PinxelFileContents, settings: CaptureSettings, date: Date) throws -> URL {
        let (folder, stopAccessing) = settings.accessSaveFolder()
        defer { stopAccessing() }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw AutoSaveError.folderNotWritable(folder.path)
        }
        guard fileManager.isWritableFile(atPath: folder.path) else { throw AutoSaveError.folderNotWritable(folder.path) }

        let baseName = FileNamer.baseName(template: settings.effectiveFileNameTemplate, date: date)
        let fileExtension = settings.saveFormat.fileExtension
        var url = FileNamer.uniqueURL(in: folder, baseName: baseName, fileExtension: fileExtension, fileManager: fileManager)
        let data: Data
        do {
            let assets = try contents.assetProvider()
            switch settings.saveFormat {
            case .pinxel:
                let thumbnail = try Thumbnailer.make(contents.document, assets: assets)
                data = try PinxelArchive.write(document: contents.document, images: contents.images, thumbnail: thumbnail, appVersion: appVersion)
            case .png:
                let image = try DocumentRenderer().renderImage(contents.document, assets: assets)
                data = try ImageCodec.encode(image, type: .png)
            }
            // Atomic write to a hidden file, then an exclusive rename: a full disk does not leave a half-written file,
            // and a name taken in the meantime (another capture saving at the same moment) is never overwritten:
            // the next free name is tried instead.
            let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
            try data.write(to: temporary, options: .atomic)
            defer { try? fileManager.removeItem(at: temporary) }
            var attempts = 0
            while !Self.renameExclusively(temporary, to: url) {
                attempts += 1
                guard errno == EEXIST, attempts < 1000 else { throw CocoaError(.fileWriteFileExists) }
                url = FileNamer.uniqueURL(in: folder, baseName: baseName, fileExtension: fileExtension, fileManager: fileManager)
            }
        } catch {
            throw AutoSaveError.writeFailed(url.path)
        }
        return url
    }

    /// `rename` that fails with `EEXIST` instead of replacing an existing file; one system call, so no race.
    private static func renameExclusively(_ source: URL, to destination: URL) -> Bool {
        renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0
    }
}
