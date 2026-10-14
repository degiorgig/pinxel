import AppCore
import AppKit
import CoreTransferable
import EditorUI
import Rendering

/// L'immagine composita come file PNG temporaneo, per trascinarla dalla toolbar in altre app (spec §9).
struct DraggedCapture: Transferable {
    let model: EditorModel

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { capture in
            SentTransferredFile(try await capture.writePNG())
        }
    }

    @MainActor
    func writePNG() throws -> URL {
        let session = model.session
        let image = try DocumentRenderer().renderImage(session.document, assets: session.assets)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = FileNamer.baseName(template: FileNamer.defaultTemplate, date: session.document.metadata.captureDate)
        let url = try TemporaryFiles.uniqueURL(fileName: "\(name).png")
        try data.write(to: url)
        return url
    }
}
