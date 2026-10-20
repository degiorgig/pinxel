import CoreGraphics
import DocumentModel
import Foundation
import Rendering
import UniformTypeIdentifiers

public enum ExportFormat: Equatable, Sendable {
    case png
    case jpeg(quality: Double)
    case heic(quality: Double)
    case pdf
}

public enum ExportScale: Sendable {
    /// Logical points (half the pixels of a Retina capture).
    case oneX
    /// Retina pixels.
    case twoX

    public func outputScale(documentScale: Double) -> Double {
        let target: Double = self == .oneX ? 1 : 2
        return target / max(documentScale, 0.0001)
    }
}

public enum Exporter {
    public static func export(
        _ document: PinxelDocument,
        assets: any AssetProvider,
        format: ExportFormat,
        scale: ExportScale,
        renderer: DocumentRenderer = DocumentRenderer()
    ) throws -> Data {
        let outputScale = scale.outputScale(documentScale: document.scale)
        switch format {
        case .png:
            let image = try renderer.renderImage(document, assets: assets, options: RenderOptions(outputScale: outputScale))
            return try ImageCodec.encode(image, type: .png)
        case .jpeg(let quality):
            let image = try renderer.renderImage(document, assets: assets, options: RenderOptions(outputScale: outputScale, matte: .white))
            return try ImageCodec.encode(image, type: .jpeg, quality: quality)
        case .heic(let quality):
            let image = try renderer.renderImage(document, assets: assets, options: RenderOptions(outputScale: outputScale))
            return try ImageCodec.encode(image, type: .heic, quality: quality)
        case .pdf:
            return try pdf(document, assets: assets, outputScale: outputScale, renderer: renderer)
        }
    }

    private static func pdf(_ document: PinxelDocument, assets: any AssetProvider, outputScale: Double, renderer: DocumentRenderer) throws -> Data {
        let canvas = renderer.canvasSize(for: document)
        // Empty canvas: the same error as the other formats.
        guard canvas.width > 0, canvas.height > 0 else { throw RenderError.invalidSize }
        var mediaBox = CGRect(x: 0, y: 0, width: canvas.width * outputScale, height: canvas.height * outputScale)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw RenderError.contextCreationFailed
        }
        ctx.beginPDFPage(nil)
        try renderer.render(document, assets: assets, in: ctx, options: RenderOptions(outputScale: outputScale))
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
}
