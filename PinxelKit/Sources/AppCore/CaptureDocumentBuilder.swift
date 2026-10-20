import CoreGraphics
import Foundation
import DocumentModel
import Persistence

public enum CaptureDocumentBuilder {
    /// New document with the capture as the bottom image of the stack, as large as the canvas.
    public static func make(image: CGImage, scale: Double, metadata: CaptureMetadata) throws -> PinxelFileContents {
        let (ref, data) = try ImageCodec.encodeBackground(image)
        let size = PixelSize(width: image.width, height: image.height)
        let capture = Annotation(kind: .image(PlacedImageData(rect: CGRect(origin: .zero, size: size.cgSize), asset: ref)),
                                 style: Style(stroke: nil, lineWidth: 0))
        let document = PinxelDocument(canvasSize: size, scale: scale, annotations: [capture], metadata: metadata)
        return PinxelFileContents(document: document, images: [ref: data])
    }

    /// Empty document, to start without a capture (New): then you paste, drag or draw.
    public static func blank(scale: Double) throws -> PinxelFileContents {
        PinxelFileContents(document: PinxelDocument(canvasSize: PixelSize(width: 0, height: 0), scale: scale, metadata: CaptureMetadata()), images: [:])
    }

    /// Scale of a pasted image: pixels per point, rounded and limited to 1...3.
    /// A Retina screenshot on the pasteboard (144 dpi) comes out 2x.
    public static func pastedScale(pixelWidth: Int, pointWidth: Double) -> Double {
        PixelDensity.scale(pixelWidth: pixelWidth, pointWidth: pointWidth)
    }
}
