import CoreGraphics
import Foundation
import DocumentModel
import Persistence

public enum CaptureDocumentBuilder {
    /// Nuovo documento con la cattura come immagine in fondo alla pila, grande quanto la tela.
    public static func make(image: CGImage, scale: Double, metadata: CaptureMetadata) throws -> PinxelFileContents {
        let (ref, data) = try ImageCodec.encodeBackground(image)
        let size = PixelSize(width: image.width, height: image.height)
        let capture = Annotation(kind: .image(PlacedImageData(rect: CGRect(origin: .zero, size: size.cgSize), asset: ref)),
                                 style: Style(stroke: nil, lineWidth: 0))
        let document = PinxelDocument(canvasSize: size, scale: scale, annotations: [capture], metadata: metadata)
        return PinxelFileContents(document: document, images: [ref: data])
    }

    /// Documento vuoto, per cominciare senza cattura (Nuovo): poi si incolla, si trascina o si disegna.
    public static func blank(scale: Double) throws -> PinxelFileContents {
        PinxelFileContents(document: PinxelDocument(canvasSize: PixelSize(width: 0, height: 0), scale: scale, metadata: CaptureMetadata()), images: [:])
    }

    /// Scala di un'immagine incollata: pixel per punto, arrotondata e limitata a 1...3.
    /// Uno screenshot Retina negli appunti (144 dpi) risulta 2x.
    public static func pastedScale(pixelWidth: Int, pointWidth: Double) -> Double {
        PixelDensity.scale(pixelWidth: pixelWidth, pointWidth: pointWidth)
    }
}
