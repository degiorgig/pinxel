import Foundation

extension PinxelDocument {
    /// Lato massimo accettato per l'immagine e per ogni risultato intermedio delle operazioni.
    public static let maxImageSide = 32_768

    /// Motivo per cui il documento non è utilizzabile, o `nil` se è valido.
    /// Da chiamare su ogni documento letto da file prima di disegnarlo.
    public func validationError() -> String? {
        let limit = Self.maxImageSide
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
        guard scale.isFinite, scale > 0, scale <= 16 else { return "scala non valida: \(scale)" }
        guard canvasStyle.padding.isFinite, (0...4096).contains(canvasStyle.padding) else {
            return "margine non valido: \(canvasStyle.padding)"
        }
        if let border = canvasStyle.border, !(border.width.isFinite && (0...4096).contains(border.width)) {
            return "bordo non valido: \(border.width)"
        }
        var ids = Set<UUID>()
        for annotation in annotations where !ids.insert(annotation.id).inserted {
            return "annotazione duplicata: \(annotation.id)"
        }
        return nil
    }
}
