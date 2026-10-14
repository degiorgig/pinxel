import Foundation

extension Annotation {
    /// Copia dell'annotazione con tutta la geometria trasformata da `mapping`.
    /// Stile e rotazione restano invariati.
    public func transformed(by mapping: PointMapping) -> Annotation {
        func rect(_ r: CGRect) -> CGRect {
            let r = r.standardized
            return .bounding([mapping.map(CGPoint(x: r.minX, y: r.minY)), mapping.map(CGPoint(x: r.maxX, y: r.maxY))])
        }
        func line(_ l: LineGeometry) -> LineGeometry {
            LineGeometry(start: mapping.map(l.start), end: mapping.map(l.end))
        }
        func path(_ p: PathGeometry) -> PathGeometry {
            PathGeometry(points: p.points.map { mapping.map($0) })
        }

        var copy = self
        switch kind {
        case .arrow(var data): data.line = line(data.line); copy.kind = .arrow(data)
        case .line(var data): data.line = line(data.line); copy.kind = .line(data)
        case .shape(var data): data.rect = rect(data.rect); copy.kind = .shape(data)
        case .text(var data): data.rect = rect(data.rect); copy.kind = .text(data)
        case .callout(var data):
            data.rect = rect(data.rect)
            data.tail.tip = mapping.map(data.tail.tip)
            copy.kind = .callout(data)
        case .step(var data):
            data.center = mapping.map(data.center)
            data.diameter *= mapping.lengthScale
            copy.kind = .step(data)
        case .magnifier(var data):
            data.source = rect(data.source)
            data.target = rect(data.target)
            copy.kind = .magnifier(data)
        case .blur(var data): data.rect = rect(data.rect); copy.kind = .blur(data)
        case .pixelate(var data): data.rect = rect(data.rect); copy.kind = .pixelate(data)
        case .highlight(var data): data.path = path(data.path); copy.kind = .highlight(data)
        case .pen(var data): data.path = path(data.path); copy.kind = .pen(data)
        case .image(var data): data.rect = rect(data.rect); copy.kind = .image(data)
        case .unknown: break
        }
        return copy
    }
}
