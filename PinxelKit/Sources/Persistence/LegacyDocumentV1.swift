import DocumentModel
import Foundation

/// The version 1 document of the format: capture as a fixed background plus image operations.
/// It is only read to convert it; Pinxel always saves version 2.
struct LegacyDocumentV1: Codable, Equatable {
    var background: ImageAssetRef
    var canvasSize: PixelSize
    var scale: Double
    var colorSpace: ColorSpaceID
    var imageOperations: [ImageOperation]
    var canvasStyle: CanvasStyle
    var annotations: [Annotation]
    var metadata: CaptureMetadata

    /// Size of the background after the operations.
    var imageSize: PixelSize {
        imageOperations.reduce(canvasSize) { size, operation in operation.resultSize(from: size) }
    }

    /// The version 1 rules: background and every intermediate result within the limits.
    func validationError() -> String? {
        let limit = PinxelDocument.maxImageSide
        func sizeError(_ size: PixelSize, _ what: String) -> String? {
            guard (1...limit).contains(size.width), (1...limit).contains(size.height) else {
                return "\(what) out of range: \(size.width)×\(size.height)"
            }
            return nil
        }
        if let error = sizeError(canvasSize, "image size") { return error }
        var size = canvasSize
        for operation in imageOperations {
            size = operation.resultSize(from: size)
            if let error = sizeError(size, "result of \(operation.name)") { return error }
        }
        return nil
    }

    /// Version 2 document: the processed background (`capture`) becomes the bottom image, the annotations stay
    /// where they are (they were already in the post-operation space), then the canvas fits the content.
    func converted(capture: ImageAssetRef) -> PinxelDocument {
        let size = imageSize
        let image = Annotation(kind: .image(PlacedImageData(rect: CGRect(origin: .zero, size: size.cgSize), asset: capture)),
                               style: Style(stroke: nil, lineWidth: 0))
        var document = PinxelDocument(canvasSize: size, scale: scale, colorSpace: colorSpace, canvasStyle: canvasStyle,
                                      annotations: [image] + annotations, metadata: metadata)
        FitCanvas(in: document)?.apply(to: &document)
        return document
    }
}
