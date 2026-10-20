import Foundation

public enum Axis: String, Codable, Sendable {
    /// Removes a horizontal band (rows), the height decreases.
    case horizontal
    /// Removes a vertical band (columns), the width decreases.
    case vertical
}

public enum CutEdge: String, Codable, Sendable {
    case straight, zigzag
}

public struct CutOut: Codable, Equatable, Sendable {
    public var axis: Axis
    public var start: Int
    public var length: Int
    public var edge: CutEdge

    public init(axis: Axis, start: Int, length: Int, edge: CutEdge = .straight) {
        self.axis = axis
        self.start = start
        self.length = length
        self.edge = edge
    }

    private func extent(of size: PixelSize) -> Int {
        axis == .horizontal ? size.height : size.width
    }

    public func clampedStart(in size: PixelSize) -> Int {
        max(0, min(start, extent(of: size)))
    }

    public func clampedLength(in size: PixelSize) -> Int {
        max(0, min(length, extent(of: size) - clampedStart(in: size)))
    }
}

/// Transformation of document points produced by an image operation.
public struct PointMapping: Sendable {
    public let map: @Sendable (CGPoint) -> CGPoint
    /// Factor for isotropic lengths (e.g. step diameter).
    public let lengthScale: Double

    public init(lengthScale: Double = 1, map: @escaping @Sendable (CGPoint) -> CGPoint) {
        self.lengthScale = lengthScale
        self.map = map
    }
}

public enum ImageOperation: Codable, Equatable, Sendable {
    case crop(PixelRect)
    case resize(PixelSize)
    case cutOut(CutOut)
    /// Only in version 1 files: it used to enlarge the canvas.
    case extend(PixelSize)

    public var name: String {
        switch self {
        case .crop: CommandName.crop
        case .resize: CommandName.resize
        case .cutOut: CommandName.cutOut
        case .extend: CommandName.extendCanvas
        }
    }

    public func resultSize(from size: PixelSize) -> PixelSize {
        switch self {
        case .crop(let rect):
            let clamped = rect.clamped(to: size)
            return PixelSize(width: clamped.width, height: clamped.height)
        case .resize(let target):
            return target
        case .cutOut(let cut):
            let length = cut.clampedLength(in: size)
            switch cut.axis {
            case .horizontal: return PixelSize(width: size.width, height: size.height - length)
            case .vertical: return PixelSize(width: size.width - length, height: size.height)
            }
        case .extend(let target):
            return PixelSize(width: max(size.width, target.width), height: max(size.height, target.height))
        }
    }

    public func mapping(from size: PixelSize) -> PointMapping {
        switch self {
        case .crop(let rect):
            let clamped = rect.clamped(to: size)
            let dx = Double(clamped.x), dy = Double(clamped.y)
            return PointMapping { CGPoint(x: $0.x - dx, y: $0.y - dy) }
        case .resize(let target):
            let sx = Double(target.width) / Double(max(size.width, 1))
            let sy = Double(target.height) / Double(max(size.height, 1))
            return PointMapping(lengthScale: (sx * sy).squareRoot()) { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        case .cutOut(let cut):
            let start = Double(cut.clampedStart(in: size))
            let length = Double(cut.clampedLength(in: size))
            switch cut.axis {
            case .horizontal:
                return PointMapping { CGPoint(x: $0.x, y: collapse($0.y, start: start, length: length)) }
            case .vertical:
                return PointMapping { CGPoint(x: collapse($0.x, start: start, length: length), y: $0.y) }
            }
        case .extend:
            return PointMapping { $0 }
        }
    }
}

/// Coordinates beyond the removed band slide back; those inside the band end up on the edge.
private func collapse(_ value: Double, start: Double, length: Double) -> Double {
    if value >= start + length { return value - length }
    if value > start { return start }
    return value
}
