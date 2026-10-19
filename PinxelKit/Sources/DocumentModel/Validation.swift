import Foundation

extension PinxelDocument {
    /// Lato massimo accettato per la tela.
    public static let maxImageSide = 32_768

    /// Motivo per cui il documento non è utilizzabile, o `nil` se è valido.
    /// Da chiamare su ogni documento letto da file prima di disegnarlo.
    public func validationError() -> String? {
        let limit = Self.maxImageSide
        guard (0...limit).contains(canvasSize.width), (0...limit).contains(canvasSize.height),
              (canvasSize.width == 0) == (canvasSize.height == 0) else {
            return "dimensioni della tela fuori dai limiti: \(canvasSize.width)×\(canvasSize.height)"
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
