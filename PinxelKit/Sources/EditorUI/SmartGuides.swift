import CoreGraphics

/// Linea guida da disegnare durante uno spostamento, in coordinate del documento.
public struct GuideLine: Equatable, Sendable {
    public enum Orientation: Sendable {
        case vertical, horizontal
    }

    public var orientation: Orientation
    /// x per le verticali, y per le orizzontali.
    public var position: Double
    public var from: Double
    public var to: Double

    public init(orientation: Orientation, position: Double, from: Double, to: Double) {
        self.orientation = orientation
        self.position = position
        self.from = from
        self.to = to
    }
}

/// Guide magnetiche (spec §6.3): bordi e centri di chi si sposta si agganciano a bordi e centri degli altri.
public enum SmartGuides {
    /// Correzione da aggiungere allo spostamento perché `moving` si allinei alla linea più vicina entro
    /// `tolerance`, per ciascun asse, e le guide che mostrano l'allineamento.
    public static func snap(_ moving: CGRect, to targets: [CGRect], tolerance: Double) -> (offset: CGSize, guides: [GuideLine]) {
        let dx = bestOffset(lines(moving, .vertical), targets.flatMap { lines($0, .vertical) }, tolerance)
        let dy = bestOffset(lines(moving, .horizontal), targets.flatMap { lines($0, .horizontal) }, tolerance)
        let snapped = moving.offsetBy(dx: dx ?? 0, dy: dy ?? 0)
        var guides: [GuideLine] = []
        if dx != nil { guides += self.guides(snapped, targets, .vertical) }
        if dy != nil { guides += self.guides(snapped, targets, .horizontal) }
        return (CGSize(width: dx ?? 0, height: dy ?? 0), guides)
    }

    private static func lines(_ rect: CGRect, _ orientation: GuideLine.Orientation) -> [Double] {
        orientation == .vertical ? [rect.minX, rect.midX, rect.maxX] : [rect.minY, rect.midY, rect.maxY]
    }

    private static func bestOffset(_ values: [Double], _ lines: [Double], _ tolerance: Double) -> Double? {
        var best: Double?
        for value in values {
            for line in lines {
                let distance = line - value
                if abs(distance) <= tolerance, abs(distance) < abs(best ?? .infinity) { best = distance }
            }
        }
        return best
    }

    /// Una guida per ogni linea di `rect` che coincide con una linea di qualche bersaglio, lunga quanto basta
    /// a toccarli tutti.
    private static func guides(_ rect: CGRect, _ targets: [CGRect], _ orientation: GuideLine.Orientation) -> [GuideLine] {
        var result: [GuideLine] = []
        for position in lines(rect, orientation) where !result.contains(where: { abs($0.position - position) < 0.5 }) {
            let matching = targets.filter { target in lines(target, orientation).contains { abs($0 - position) < 0.5 } }
            guard !matching.isEmpty else { continue }
            let all = matching + [rect]
            let from = orientation == .vertical ? all.map(\.minY).min() ?? 0 : all.map(\.minX).min() ?? 0
            let to = orientation == .vertical ? all.map(\.maxY).max() ?? 0 : all.map(\.maxX).max() ?? 0
            result.append(GuideLine(orientation: orientation, position: position, from: from, to: to))
        }
        return result
    }
}
