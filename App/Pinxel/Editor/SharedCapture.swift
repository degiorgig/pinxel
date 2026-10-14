import AppKit
import CoreTransferable
import EditorUI
import Rendering

/// Immagine composita per `ShareLink`, calcolata solo quando si condivide.
struct SharedCapture: Transferable {
    let model: EditorModel

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { capture in
            try await capture.pngData()
        }
        .suggestedFileName("Pinxel.png")
    }

    @MainActor
    func pngData() throws -> Data {
        model.commitTextEditing()
        let session = model.session
        let image = try DocumentRenderer().renderImage(session.document, assets: session.assets)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
