import CoreGraphics
import DocumentModel
import Foundation

/// Maniglie di modifica di un'annotazione selezionata.
public enum Handle: Hashable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case lineStart, lineEnd
    case rotation
    /// Punta della coda di un callout.
    case calloutTail
    /// Angoli della sorgente di una lente (le otto maniglie del riquadro stanno sulla destinazione).
    case sourceTopLeft, sourceTopRight, sourceBottomRight, sourceBottomLeft

    /// Le otto maniglie del riquadro, in senso orario dall'angolo in alto a sinistra.
    public static let boxHandles: [Handle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]

    public var isCorner: Bool { [.topLeft, .topRight, .bottomRight, .bottomLeft].contains(self) }

    /// La maniglia che resta ferma mentre si trascina questa.
    public var opposite: Handle {
        switch self {
        case .topLeft: .bottomRight
        case .top: .bottom
        case .topRight: .bottomLeft
        case .right: .left
        case .bottomRight: .topLeft
        case .bottom: .top
        case .bottomLeft: .topRight
        case .left: .right
        case .lineStart: .lineEnd
        case .lineEnd: .lineStart
        case .rotation: .rotation
        case .calloutTail: .calloutTail
        case .sourceTopLeft: .sourceBottomRight
        case .sourceTopRight: .sourceBottomLeft
        case .sourceBottomRight: .sourceTopLeft
        case .sourceBottomLeft: .sourceTopRight
        }
    }

    /// La maniglia del riquadro che corrisponde a un angolo della sorgente; le altre restano se stesse.
    public var boxEquivalent: Handle {
        switch self {
        case .sourceTopLeft: .topLeft
        case .sourceTopRight: .topRight
        case .sourceBottomRight: .bottomRight
        case .sourceBottomLeft: .bottomLeft
        default: self
        }
    }

    public var isSourceHandle: Bool { boxEquivalent != self }

    public var movesX: Bool { [.topLeft, .topRight, .bottomRight, .bottomLeft, .left, .right].contains(self) }
    public var movesY: Bool { [.topLeft, .topRight, .bottomRight, .bottomLeft, .top, .bottom].contains(self) }
}

/// Le due parti di una lente, che si spostano separatamente.
public enum MagnifierPart: Sendable {
    case source, target
}

public enum HitTesting {
    /// L'annotazione più in alto sotto `point` (coordinate del documento). `tolerance` è in pixel del documento.
    public static func annotation(at point: CGPoint, in annotations: [Annotation], tolerance: Double) -> Annotation? {
        annotations.last { contains($0, point: point, tolerance: tolerance) }
    }

    public static func contains(_ annotation: Annotation, point: CGPoint, tolerance: Double) -> Bool {
        let bounds = annotation.bounds
        guard !bounds.isNull else { return false }
        let local = point.rotated(around: bounds.center, by: -annotation.rotation)
        let reach = tolerance + annotation.style.lineWidth / 2
        switch annotation.kind {
        case .arrow(let data):
            return local.distance(toSegment: data.line.start, data.line.end) <= reach
        case .line(let data):
            return local.distance(toSegment: data.line.start, data.line.end) <= reach
        case .pen(let data):
            return polylineDistance(from: local, to: data.path.points) <= reach
        case .highlight(let data):
            return polylineDistance(from: local, to: data.path.points) <= reach
        case .shape(let data):
            let rect = data.rect.standardized
            if annotation.style.fill != nil {
                return shapeContains(data.shape, rect: rect, point: local, tolerance: tolerance)
            }
            return outlineDistance(data.shape, rect: rect, point: local) <= reach
        case .magnifier(let data):
            return data.source.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
                || data.target.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
        case .callout(let data):
            // Il fumetto o la coda, non lo spazio vuoto fra i due.
            let rect = data.rect.standardized
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
                || local.distance(toSegment: rect.center, data.tail.tip) <= tolerance + 6
        case .text, .step, .blur, .pixelate, .image:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
        case .unknown:
            return false
        }
    }

    /// ID delle annotazioni il cui riquadro (ruotato) interseca `rect`.
    public static func ids(intersecting rect: CGRect, in annotations: [Annotation]) -> Set<UUID> {
        let area = rect.standardized
        return Set(annotations.filter { annotation in
            let bounds = worldBounds(annotation)
            return !bounds.isNull && bounds.intersects(area)
        }.map(\.id))
    }

    /// Riquadro allineato agli assi che contiene l'annotazione ruotata.
    public static func worldBounds(_ annotation: Annotation) -> CGRect {
        let bounds = annotation.bounds
        guard !bounds.isNull, annotation.rotation != 0 else { return bounds }
        return .bounding(corners(of: bounds).map { $0.rotated(around: bounds.center, by: annotation.rotation) })
    }

    /// Contorni da disegnare attorno a un'annotazione selezionata (prima della rotazione).
    /// Linee e frecce non ne hanno: bastano le maniglie agli estremi.
    public static func selectionFrames(for annotation: Annotation) -> [CGRect] {
        switch annotation.kind {
        case .arrow, .line: return []
        case .callout(let data): return [data.rect.standardized]
        case .magnifier(let data): return [data.source.standardized, data.target.standardized]
        default:
            let bounds = annotation.bounds
            return bounds.isNull ? [] : [bounds]
        }
    }

    /// La parte di una lente sotto `point`; l'ingrandimento, disegnato sopra, vince.
    public static func magnifierPart(at point: CGPoint, in data: MagnifierData, tolerance: Double) -> MagnifierPart? {
        if data.target.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point) { return .target }
        if data.source.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point) { return .source }
        return nil
    }

    /// Maniglie in coordinate del documento. `rotationOffset` è la distanza della maniglia di rotazione
    /// sopra il riquadro. Le annotazioni bloccate non hanno maniglie.
    public static func handles(for annotation: Annotation, rotationOffset: Double) -> [(handle: Handle, point: CGPoint)] {
        guard !annotation.isLocked else { return [] }
        let bounds = annotation.bounds
        guard !bounds.isNull else { return [] }
        var local: [(handle: Handle, point: CGPoint)]
        switch annotation.kind {
        case .arrow(let data):
            local = [(.lineStart, data.line.start), (.lineEnd, data.line.end)]
        case .line(let data):
            local = [(.lineStart, data.line.start), (.lineEnd, data.line.end)]
        case .step:
            local = Handle.boxHandles.filter(\.isCorner).map { ($0, boxPoint($0, of: bounds)) }
        case .magnifier(let data):
            // Otto maniglie sull'ingrandimento, quattro sugli angoli della sorgente, niente rotazione.
            let target = data.target.standardized
            let source = data.source.standardized
            local = Handle.boxHandles.map { ($0, boxPoint($0, of: target)) }
                + [Handle.sourceTopLeft, .sourceTopRight, .sourceBottomRight, .sourceBottomLeft].map { ($0, boxPoint($0, of: source)) }
        case .callout(let data):
            // Niente rotazione: maniglie sul fumetto e sulla punta della coda.
            let rect = data.rect.standardized
            local = Handle.boxHandles.map { ($0, boxPoint($0, of: rect)) } + [(.calloutTail, data.tail.tip)]
        case .unknown:
            return []
        default:
            local = Handle.boxHandles.map { ($0, boxPoint($0, of: bounds)) }
            local.append((.rotation, CGPoint(x: bounds.midX, y: bounds.minY - rotationOffset)))
        }
        return local.map { ($0.handle, $0.point.rotated(around: bounds.center, by: annotation.rotation)) }
    }

    public static func handle(at point: CGPoint, for annotation: Annotation, tolerance: Double, rotationOffset: Double) -> Handle? {
        handles(for: annotation, rotationOffset: rotationOffset)
            .filter { $0.point.distance(to: point) <= tolerance }
            .min { $0.point.distance(to: point) < $1.point.distance(to: point) }?
            .handle
    }

    /// Posizione di una maniglia del riquadro su `rect` (non ruotato).
    public static func boxPoint(_ handle: Handle, of rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .sourceTopLeft, .sourceTopRight, .sourceBottomRight, .sourceBottomLeft: boxPoint(handle.boxEquivalent, of: rect)
        case .lineStart, .lineEnd, .rotation, .calloutTail: rect.center
        }
    }

    static func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    private static func polylineDistance(from point: CGPoint, to points: [CGPoint]) -> Double {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return point.distance(to: first) }
        return zip(points, points.dropFirst()).map { point.distance(toSegment: $0, $1) }.min() ?? .infinity
    }

    private static func shapeContains(_ shape: ShapeType, rect: CGRect, point: CGPoint, tolerance: Double) -> Bool {
        switch shape {
        case .rectangle, .roundedRectangle:
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .ellipse:
            let radiusX = rect.width / 2, radiusY = rect.height / 2
            guard radiusX > 0, radiusY > 0 else { return false }
            let nx = (point.x - rect.midX) / radiusX, ny = (point.y - rect.midY) / radiusY
            return (nx * nx + ny * ny).squareRoot() <= 1 + tolerance / min(radiusX, radiusY)
        }
    }

    private static func outlineDistance(_ shape: ShapeType, rect: CGRect, point: CGPoint) -> Double {
        switch shape {
        case .rectangle, .roundedRectangle:
            if rect.contains(point) {
                return min(point.x - rect.minX, rect.maxX - point.x, point.y - rect.minY, rect.maxY - point.y)
            }
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return hypot(dx, dy)
        case .ellipse:
            let radiusX = rect.width / 2, radiusY = rect.height / 2
            guard radiusX > 0, radiusY > 0 else { return point.distance(to: rect.center) }
            let nx = (point.x - rect.midX) / radiusX, ny = (point.y - rect.midY) / radiusY
            return abs((nx * nx + ny * ny).squareRoot() - 1) * min(radiusX, radiusY)
        }
    }
}
