import DocumentModel
import Foundation
import Rendering

public enum Thumbnailer {
    public static let maxSide: Double = 512

    /// PNG con il lato lungo al massimo di 512 px; le immagini più piccole non vengono ingrandite.
    public static func make(_ document: PinxelDocument, assets: any AssetProvider, renderer: DocumentRenderer = DocumentRenderer()) throws -> Data {
        let canvas = renderer.canvasSize(for: document)
        let scale = min(1, maxSide / max(canvas.width, canvas.height, 1))
        let image = try renderer.renderImage(document, assets: assets, options: RenderOptions(outputScale: scale))
        return try ImageCodec.encode(image, type: .png)
    }
}
