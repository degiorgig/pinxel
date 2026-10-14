import CoreGraphics
import DocumentModel
import Foundation

/// Trasformazioni geometriche dei gesti dell'editor. Tutte le coordinate sono del documento.
public enum AnnotationGeometry {
    /// Lato minimo di un riquadro ridimensionato, in pixel del documento.
    public static let minimumSize: Double = 1

    public static func moved(_ annotation: Annotation, by delta: CGSize) -> Annotation {
        let dx = delta.width, dy = delta.height
        guard dx != 0 || dy != 0 else { return annotation }
        return annotation.transformed(by: PointMapping { CGPoint(x: $0.x + dx, y: $0.y + dy) })
    }

    /// Ridimensiona trascinando `handle` fino a `point`. Per le annotazioni ruotate il punto opposto
    /// resta fermo sullo schermo.
    public static func resized(_ annotation: Annotation, handle: Handle, to point: CGPoint, keepAspect: Bool) -> Annotation {
        switch handle {
        case .lineStart, .lineEnd: return movingEndpoint(annotation, handle, to: point, constrain: keepAspect)
        case .rotation: return annotation
        default: break
        }
        let old = annotation.bounds
        guard !old.isNull else { return annotation }
        let local = point.rotated(around: old.center, by: -annotation.rotation)
        let anchor = HitTesting.boxPoint(handle.opposite, of: old)
        var isStep = false
        if case .step = annotation.kind { isStep = true }
        let target = frame(anchor: anchor, dragged: local, handle: handle, old: old,
                           keepAspect: (keepAspect || isStep) && handle.isCorner)

        let scaleX = old.width > 0 ? target.width / old.width : 1
        let scaleY = old.height > 0 ? target.height / old.height : 1
        let oldMinX = old.minX, oldMinY = old.minY, newMinX = target.minX, newMinY = target.minY
        let mapping = PointMapping(lengthScale: (scaleX * scaleY).squareRoot()) { p in
            CGPoint(x: newMinX + (p.x - oldMinX) * scaleX, y: newMinY + (p.y - oldMinY) * scaleY)
        }
        var result = annotation.transformed(by: mapping)
        if annotation.rotation != 0 {
            // Il centro di rotazione si è spostato: trasla perché il punto fermo resti dov'era sullo schermo.
            let before = anchor.rotated(around: old.center, by: annotation.rotation)
            let after = anchor.rotated(around: result.bounds.center, by: annotation.rotation)
            result = moved(result, by: CGSize(width: before.x - after.x, height: before.y - after.y))
        }
        return result
    }

    /// Ruota attorno al centro verso il puntatore; con `snap` a passi di 15°.
    public static func rotated(_ annotation: Annotation, pointer: CGPoint, snap: Bool) -> Annotation {
        let bounds = annotation.bounds
        guard !bounds.isNull else { return annotation }
        // La maniglia sta sopra il centro: puntatore in alto = rotazione zero.
        var angle = atan2(pointer.y - bounds.midY, pointer.x - bounds.midX) + .pi / 2
        if snap {
            let step = Double.pi / 12
            angle = (angle / step).rounded() * step
        }
        var copy = annotation
        copy.rotation = normalized(angle)
        return copy
    }

    /// `point` portato sulla direzione multipla di 45° più vicina, alla stessa distanza da `origin`.
    public static func constrained45(from origin: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - origin.x, dy = point.y - origin.y
        let length = hypot(dx, dy)
        guard length > 0 else { return point }
        let step = Double.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: origin.x + length * cos(angle), y: origin.y + length * sin(angle))
    }

    /// Angolo opposto di un quadrato con un vertice in `origin`, verso `point`.
    public static func squared(from origin: CGPoint, to point: CGPoint) -> CGPoint {
        let dx = point.x - origin.x, dy = point.y - origin.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: origin.x + (dx < 0 ? -side : side), y: origin.y + (dy < 0 ? -side : side))
    }

    static func frame(anchor: CGPoint, dragged: CGPoint, handle: Handle, old: CGRect, keepAspect: Bool) -> CGRect {
        var minX = old.minX, maxX = old.maxX, minY = old.minY, maxY = old.maxY
        if handle.movesX {
            minX = min(anchor.x, dragged.x)
            maxX = max(anchor.x, dragged.x)
            if maxX - minX < minimumSize {
                if dragged.x >= anchor.x { minX = anchor.x; maxX = anchor.x + minimumSize } else { maxX = anchor.x; minX = anchor.x - minimumSize }
            }
        }
        if handle.movesY {
            minY = min(anchor.y, dragged.y)
            maxY = max(anchor.y, dragged.y)
            if maxY - minY < minimumSize {
                if dragged.y >= anchor.y { minY = anchor.y; maxY = anchor.y + minimumSize } else { maxY = anchor.y; minY = anchor.y - minimumSize }
            }
        }
        if keepAspect, old.width > 0, old.height > 0 {
            let scale = max((maxX - minX) / old.width, (maxY - minY) / old.height)
            let width = old.width * scale, height = old.height * scale
            if dragged.x >= anchor.x { minX = anchor.x; maxX = anchor.x + width } else { maxX = anchor.x; minX = anchor.x - width }
            if dragged.y >= anchor.y { minY = anchor.y; maxY = anchor.y + height } else { maxY = anchor.y; minY = anchor.y - height }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func movingEndpoint(_ annotation: Annotation, _ handle: Handle, to point: CGPoint, constrain: Bool) -> Annotation {
        func update(_ line: LineGeometry) -> LineGeometry {
            var line = line
            if handle == .lineStart {
                line.start = constrain ? constrained45(from: line.end, to: point) : point
            } else {
                line.end = constrain ? constrained45(from: line.start, to: point) : point
            }
            return line
        }
        var copy = annotation
        switch annotation.kind {
        case .arrow(var data):
            data.line = update(data.line)
            copy.kind = .arrow(data)
        case .line(var data):
            data.line = update(data.line)
            copy.kind = .line(data)
        default:
            break
        }
        return copy
    }

    private static func normalized(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi { value -= 2 * .pi } else if value <= -.pi { value += 2 * .pi }
        return value
    }
}
