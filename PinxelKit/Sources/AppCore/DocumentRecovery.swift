import DocumentModel
import Foundation
import Persistence

public enum DocumentRecovery {
    /// Documento nuovo con il solo sfondo di un file `.pinxel` danneggiato (spec §10); `nil` se è perso anche lo sfondo.
    /// `scale` sostituisce quella del documento, che non si può più leggere.
    public static func contents(fromDamaged data: Data, scale: Double) -> PinxelFileContents? {
        guard let background = PinxelArchive.recoverBackground(data),
              let image = try? ImageCodec.decode(background) else { return nil }
        return try? CaptureDocumentBuilder.make(image: image, scale: scale, metadata: CaptureMetadata())
    }
}
