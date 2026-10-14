import CoreGraphics
import DocumentModel
import Foundation

/// Contenuto degli appunti per copiare annotazioni tra documenti (tipo privato, spec §6.3).
public enum AnnotationClipboard {
    public static let typeIdentifier = "com.degiorgi.pinxel.annotations"
    public static let pasteOffset = CGSize(width: 10, height: 10)

    public static func encode(_ annotations: [Annotation]) throws -> Data {
        try JSONEncoder().encode(annotations)
    }

    public static func decode(_ data: Data) throws -> [Annotation] {
        try JSONDecoder().decode([Annotation].self, from: data)
    }

    /// Copie da incollare: ID nuovi, spostate di `pasteOffset`, sbloccate. Le immagini incollate restano
    /// fuori perché i loro file non viaggiano negli appunti.
    /// `times`: quante volte si è incollato lo stesso contenuto; ogni copia si sposta di un passo in più.
    public static func prepareForPaste(_ annotations: [Annotation], times: Int = 1, makeID: () -> UUID = { UUID() }) -> [Annotation] {
        let offset = CGSize(width: pasteOffset.width * Double(max(times, 1)), height: pasteOffset.height * Double(max(times, 1)))
        return annotations.compactMap { annotation in
            if case .image = annotation.kind { return nil }
            let moved = AnnotationGeometry.moved(annotation, by: offset)
            return Annotation(id: makeID(), kind: moved.kind, style: moved.style, rotation: moved.rotation, isLocked: false)
        }
    }

    /// Riquadro della tela (pixel, padding incluso) da ritagliare per il PNG che accompagna le annotazioni.
    public static func cropRect(for annotations: [Annotation], padding: Double, canvasSize: CGSize, margin: Double = 8) -> CGRect? {
        let union = annotations.map(HitTesting.worldBounds).filter { !$0.isNull }.reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return nil }
        let rect = union.offsetBy(dx: padding, dy: padding)
            .insetBy(dx: -margin, dy: -margin)
            .integral
            .intersection(CGRect(origin: .zero, size: canvasSize))
        return rect.isNull || rect.isEmpty ? nil : rect
    }
}
