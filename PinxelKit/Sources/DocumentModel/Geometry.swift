import Foundation

public struct LineGeometry: Codable, Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

public struct PathGeometry: Codable, Equatable, Sendable {
    public var points: [CGPoint]

    public init(points: [CGPoint]) {
        self.points = points
    }
}

public struct PixelSize: Codable, Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
}

public struct PixelRect: Codable, Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// Intersezione con l'immagine `0..<size`; larghezza/altezza 0 se fuori.
    public func clamped(to size: PixelSize) -> PixelRect {
        let minX = max(0, min(x, size.width))
        let minY = max(0, min(y, size.height))
        let maxX = max(minX, min(x + width, size.width))
        let maxY = max(minY, min(y + height, size.height))
        return PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension CGRect {
    /// Il più piccolo rettangolo che contiene tutti i punti; `.null` se non ci sono punti.
    public static func bounding(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
