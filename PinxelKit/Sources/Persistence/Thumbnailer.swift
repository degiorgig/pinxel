import CoreGraphics
import DocumentModel
import Foundation
import Rendering

public enum Thumbnailer {
    public static let maxSide: Double = 512

    /// PNG with the long side at most 512 px; smaller images are not enlarged.
    public static func make(_ document: PinxelDocument, assets: any AssetProvider, renderer: DocumentRenderer = DocumentRenderer()) throws -> Data {
        // Empty canvas (everything deleted): a transparent 1-pixel thumbnail, so that saving succeeds.
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
