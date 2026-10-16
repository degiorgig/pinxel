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

    /// File delle immagini incollate che accompagnano le annotazioni, per incollarle in un altro documento.
    public static let imagesTypeIdentifier = "com.degiorgi.pinxel.annotation-images"

    public static func imageAssets(of annotations: [Annotation]) -> [ImageAssetRef] {
        annotations.compactMap { annotation in
            if case .image(let data) = annotation.kind { return data.asset }
            return nil
        }
    }

    public static func encodeImages(_ images: [ImageAssetRef: Data]) throws -> Data {
        try JSONEncoder().encode(Dictionary(uniqueKeysWithValues: images.map { ($0.key.name, $0.value) }))
    }

    public static func decodeImages(_ data: Data) throws -> [ImageAssetRef: Data] {
        let names = try JSONDecoder().decode([String: Data].self, from: data)
        return Dictionary(uniqueKeysWithValues: names.map { (ImageAssetRef(name: $0.key), $0.value) })
    }

    /// Copie da incollare: ID nuovi, spostate di `pasteOffset`, sbloccate. Le immagini il cui file non è
    /// disponibile restano fuori.
    /// `times`: quante volte si è incollato lo stesso contenuto; ogni copia si sposta di un passo in più.
    /// `keepImage`: le immagini il cui file è disponibile qui (stesso documento, o arrivato con gli appunti) restano.
    public static func prepareForPaste(_ annotations: [Annotation], times: Int = 1, keepImage: (ImageAssetRef) -> Bool = { _ in false },
                                       makeID: () -> UUID = { UUID() }) -> [Annotation] {
        let offset = CGSize(width: pasteOffset.width * Double(max(times, 1)), height: pasteOffset.height * Double(max(times, 1)))
        return annotations.compactMap { annotation in
            if case .image(let data) = annotation.kind, !keepImage(data.asset) { return nil }
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
