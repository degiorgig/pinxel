import DocumentModel
import Foundation
import Persistence

public enum DocumentRecovery {
    /// New document with only the background of a damaged `.pinxel` file (spec §10); `nil` if the background is lost too.
    /// `scale` replaces the document's, which can no longer be read.
    public static func contents(fromDamaged data: Data, scale: Double) -> PinxelFileContents? {
        guard let background = PinxelArchive.recoverBackground(data),
              let image = try? ImageCodec.decode(background) else { return nil }
        return try? CaptureDocumentBuilder.make(image: image, scale: scale, metadata: CaptureMetadata())
    }
}
