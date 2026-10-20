import DocumentModel
import Foundation
import Persistence
import Rendering
import UniformTypeIdentifiers

public enum AutoSaveError: Error, Equatable {
    case folderNotWritable(String)
    case writeFailed(String)
}

public struct AutoSaver {
    private let fileManager: FileManager
    private let appVersion: String

    public init(fileManager: FileManager = .default, appVersion: String = "0.1.0") {
        self.fileManager = fileManager
        self.appVersion = appVersion
    }

    /// Writes the capture into the settings folder without ever overwriting existing files.
    public func save(_ contents: PinxelFileContents, settings: CaptureSettings, date: Date) throws -> URL {
        let folder = settings.saveFolderURL
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw AutoSaveError.folderNotWritable(folder.path)
        }
        guard fileManager.isWritableFile(atPath: folder.path) else { throw AutoSaveError.folderNotWritable(folder.path) }

        let baseName = FileNamer.baseName(template: settings.effectiveFileNameTemplate, date: date)
        let url = FileNamer.uniqueURL(in: folder, baseName: baseName, fileExtension: settings.saveFormat.fileExtension, fileManager: fileManager)
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
            // Atomic write to a hidden file, then move: a full disk does not leave a half-written file,
            // and `moveItem` fails if the file appeared in the meantime, so it never overwrites.
            let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
            try data.write(to: temporary, options: .atomic)
            do {
                try fileManager.moveItem(at: temporary, to: url)
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        } catch {
            throw AutoSaveError.writeFailed(url.path)
        }
        return url
    }
}
