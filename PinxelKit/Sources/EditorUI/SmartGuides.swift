import CoreGraphics

/// Guide line to draw during a move, in document coordinates.
public struct GuideLine: Equatable, Sendable {
    public enum Orientation: Sendable {
        case vertical, horizontal
    }

    public var orientation: Orientation
    /// x for verticals, y for horizontals.
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

/// Smart guides (spec §6.3): edges and centers of the moving item snap to edges and centers of the others.
public enum SmartGuides {
    /// Correction to add to the move so that `moving` aligns to the nearest line within
    /// `tolerance`, for each axis, and the guides that show the alignment.
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

    /// One guide for each line of `rect` that coincides with a line of some target, long enough
    /// to touch them all.
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
