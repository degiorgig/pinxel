import CoreGraphics
import Foundation

extension CGPoint {
    /// Il punto ruotato di `angle` radianti attorno a `center`, nello spazio con l'asse y verso il basso
    /// (stessa convenzione di `AnnotationRenderer`).
    public func rotated(around center: CGPoint, by angle: Double) -> CGPoint {
        guard angle != 0 else { return self }
        let dx = x - center.x, dy = y - center.y
        let cosine = cos(angle), sine = sin(angle)
        return CGPoint(x: center.x + dx * cosine - dy * sine, y: center.y + dx * sine + dy * cosine)
    }

    func distance(to other: CGPoint) -> Double {
        hypot(x - other.x, y - other.y)
    }

    func distance(toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(to: a) }
        let t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / lengthSquared))
        return distance(to: CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
