import DocumentModel
import Foundation

/// Il documento della versione 1 del formato: cattura come sfondo fisso più operazioni sull'immagine.
/// Si legge solo per convertirlo; Pinxel salva sempre la versione 2.
struct LegacyDocumentV1: Codable, Equatable {
    var background: ImageAssetRef
    var canvasSize: PixelSize
    var scale: Double
    var colorSpace: ColorSpaceID
    var imageOperations: [ImageOperation]
    var canvasStyle: CanvasStyle
    var annotations: [Annotation]
    var metadata: CaptureMetadata

    /// Dimensioni dello sfondo dopo le operazioni.
    var imageSize: PixelSize {
        imageOperations.reduce(canvasSize) { size, operation in operation.resultSize(from: size) }
    }

    /// Le regole della versione 1: sfondo e ogni risultato intermedio dentro i limiti.
    func validationError() -> String? {
        let limit = PinxelDocument.maxImageSide
        func sizeError(_ size: PixelSize, _ what: String) -> String? {
            guard (1...limit).contains(size.width), (1...limit).contains(size.height) else {
                return "\(what) fuori dai limiti: \(size.width)×\(size.height)"
            }
            return nil
        }
        if let error = sizeError(canvasSize, "dimensioni immagine") { return error }
        var size = canvasSize
        for operation in imageOperations {
            size = operation.resultSize(from: size)
            if let error = sizeError(size, "risultato di \(operation.name)") { return error }
        }
        return nil
    }

    /// Documento della versione 2: lo sfondo elaborato (`capture`) diventa l'immagine in fondo, le annotazioni restano
    /// dove sono (erano già nello spazio dopo le operazioni), poi la tela si adatta al contenuto.
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
