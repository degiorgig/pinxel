import CoreGraphics
import Foundation
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

    /// Documento vuoto e trasparente, per cominciare senza cattura (Nuovo): poi si incolla o si disegna.
    public static func blank(pointSize: CGSize, scale: Double) throws -> PinxelFileContents {
        let width = max(1, Int((pointSize.width * scale).rounded()))
        let height = max(1, Int((pointSize.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return try make(image: image, scale: scale, metadata: CaptureMetadata())
    }

    /// Scala di un'immagine incollata: pixel per punto, arrotondata e limitata a 1...3.
    /// Uno screenshot Retina negli appunti (144 dpi) risulta 2x.
    public static func pastedScale(pixelWidth: Int, pointWidth: Double) -> Double {
        PixelDensity.scale(pixelWidth: pixelWidth, pointWidth: pointWidth)
    }
}
