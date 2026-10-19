import Foundation

extension Annotation {
    /// Rettangolo allineato agli assi che contiene tutto ciò che l'annotazione disegna: rotazione, tratto,
    /// punte delle frecce e ombra compresi. `.null` per i tipi sconosciuti o le geometrie non finite.
    public var visualBounds: CGRect {
        let base = bounds
        guard !base.isNull, base.minX.isFinite, base.minY.isFinite, base.width.isFinite, base.height.isFinite else { return .null }
        var outset = 0.0
        if style.stroke != nil { outset += max(style.lineWidth, 0) / 2 }
        if case .arrow = kind { outset += max(style.lineWidth * 3, 10) * 0.6 }
        var rect = base.insetBy(dx: -outset, dy: -outset)
        if rotation != 0, rotation.isFinite {
            let center = CGPoint(x: base.midX, y: base.midY)
            let cosine = cos(rotation), sine = sin(rotation)
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)].map { point in
                let dx = point.x - center.x, dy = point.y - center.y
                // Stessa convenzione di `AnnotationRenderer`: asse y verso il basso.
                return CGPoint(x: center.x + dx * cosine - dy * sine, y: center.y + dx * sine + dy * cosine)
            }
            rect = .bounding(corners)
        }
        if let shadow = style.shadow {
            let blur = max(shadow.blur, 0) * 1.5
            rect = rect.union(rect.offsetBy(dx: shadow.offset.width, dy: shadow.offset.height).insetBy(dx: -blur, dy: -blur))
        }
        return rect
    }
}

/// La tela segue il contenuto: il rettangolo che racchiude tutti gli oggetti.
public enum ContentFit {
    /// Rettangolo in pixel interi, arrotondato verso l'esterno; `nil` se non c'è niente da disegnare.
    public static func bounds(of annotations: [Annotation]) -> PixelRect? {
        let union = annotations.map(\.visualBounds).filter { !$0.isNull }.reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return nil }
        let minX = whole(union.minX.rounded(.down)), minY = whole(union.minY.rounded(.down))
        let maxX = whole(union.maxX.rounded(.up)), maxY = whole(union.maxY.rounded(.up))
        return PixelRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    /// Coordinate da file ostili: niente overflow nella conversione a `Int`.
    private static func whole(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value, -1_000_000_000), 1_000_000_000))
    }
}
