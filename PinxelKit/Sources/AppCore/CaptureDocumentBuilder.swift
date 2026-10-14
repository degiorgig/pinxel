import CoreGraphics
import DocumentModel
import Persistence

public enum CaptureDocumentBuilder {
    /// Nuovo documento senza annotazioni con la cattura come sfondo.
    public static func make(image: CGImage, scale: Double, metadata: CaptureMetadata) throws -> PinxelFileContents {
        let (ref, data) = try ImageCodec.encodeBackground(image)
        let document = PinxelDocument(
            background: ref,
            canvasSize: PixelSize(width: image.width, height: image.height),
            scale: scale,
            metadata: metadata
        )
        return PinxelFileContents(document: document, images: [ref: data])
    }
}
