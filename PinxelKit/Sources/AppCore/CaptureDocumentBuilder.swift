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

    /// Scala di un'immagine incollata: pixel per punto, arrotondata e limitata a 1...3.
    /// Uno screenshot Retina negli appunti (144 dpi) risulta 2x.
    public static func pastedScale(pixelWidth: Int, pointWidth: Double) -> Double {
        PixelDensity.scale(pixelWidth: pixelWidth, pointWidth: pointWidth)
    }
}
