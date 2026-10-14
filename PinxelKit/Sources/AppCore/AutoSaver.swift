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

    /// Scrive la cattura nella cartella delle impostazioni senza mai sovrascrivere file esistenti.
    public func save(_ contents: PinxelFileContents, settings: CaptureSettings, date: Date) throws -> URL {
        let folder = settings.saveFolderURL
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw AutoSaveError.folderNotWritable(folder.path)
        }
        guard fileManager.isWritableFile(atPath: folder.path) else { throw AutoSaveError.folderNotWritable(folder.path) }

        let baseName = FileNamer.baseName(template: settings.fileNameTemplate, date: date)
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
            // `.withoutOverwriting`: se nel frattempo il file è comparso, fallisce invece di sovrascrivere.
            // (Foundation non permette di combinarlo con `.atomic`.)
            try data.write(to: url, options: .withoutOverwriting)
        } catch {
            throw AutoSaveError.writeFailed(url.path)
        }
        return url
    }
}
