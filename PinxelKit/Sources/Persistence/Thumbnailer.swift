import CoreGraphics
import DocumentModel
import Foundation
import Rendering

public enum Thumbnailer {
    public static let maxSide: Double = 512

    /// PNG con il lato lungo al massimo di 512 px; le immagini più piccole non vengono ingrandite.
    public static func make(_ document: PinxelDocument, assets: any AssetProvider, renderer: DocumentRenderer = DocumentRenderer()) throws -> Data {
        // Tela vuota (tutto eliminato): una miniatura trasparente di 1 pixel, così il salvataggio riesce.
        guard document.imageSize.width > 0, document.imageSize.height > 0 else {
            guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let empty = ctx.makeImage() else { throw RenderError.contextCreationFailed }
            return try ImageCodec.encode(empty, type: .png)
        }
        let canvas = renderer.canvasSize(for: document)
        let scale = min(1, maxSide / max(canvas.width, canvas.height, 1))
        let image = try renderer.renderImage(document, assets: assets, options: RenderOptions(outputScale: scale))
        return try ImageCodec.encode(image, type: .png)
    }
}
