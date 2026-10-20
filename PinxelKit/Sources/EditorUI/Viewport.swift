import CoreGraphics
import Foundation

/// Canvas zoom and scrolling. View coordinates are in points with the origin at the top left
/// (flipped view); canvas ones in document pixels, padding included.
public struct Viewport: Equatable, Sendable {
    public static let zoomLevels: [Double] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]
    public static let zoomRange: ClosedRange<Double> = 0.1...8

    /// 1 = 100%: one image pixel takes up one screen pixel (1/scale points).
    public private(set) var zoom: Double
    /// Position of the canvas origin in the view.
    public var origin: CGPoint
    public let documentScale: Double
    /// Zoom of the last fit to the window: the background squares measure 8 points at it.
    public private(set) var fitZoom: Double = 1

    public static let checkerSquareRange: ClosedRange<Double> = 3...128

    /// Side of the background squares, in points: they grow and shrink with the zoom, as if they were under the image.
    public var checkerSquare: Double {
        min(max(8 * zoom / fitZoom, Self.checkerSquareRange.lowerBound), Self.checkerSquareRange.upperBound)
    }

    public init(documentScale: Double, zoom: Double = 1, origin: CGPoint = .zero) {
        self.documentScale = documentScale > 0 && documentScale.isFinite ? documentScale : 1
        self.zoom = Self.clamp(zoom)
        self.origin = origin
    }

    /// View points per document pixel.
    public var pointsPerPixel: Double { zoom / documentScale }

    public func viewPoint(fromCanvas point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x * pointsPerPixel, y: origin.y + point.y * pointsPerPixel)
    }

    public func canvasPoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / pointsPerPixel, y: (point.y - origin.y) / pointsPerPixel)
    }

    public func viewRect(fromCanvas rect: CGRect) -> CGRect {
        let topLeft = viewPoint(fromCanvas: rect.origin)
        return CGRect(x: topLeft.x, y: topLeft.y, width: rect.width * pointsPerPixel, height: rect.height * pointsPerPixel)
    }

    /// Changes the zoom keeping fixed under `anchor` (a view point) the canvas point that was there.
    public mutating func setZoom(_ newZoom: Double, anchor: CGPoint) {
        let fixed = canvasPoint(fromView: anchor)
        zoom = Self.clamp(newZoom)
        origin = CGPoint(x: anchor.x - fixed.x * pointsPerPixel, y: anchor.y - fixed.y * pointsPerPixel)
    }

    public mutating func zoomIn(anchor: CGPoint) {
        setZoom(Self.zoomLevels.first { $0 > zoom + 1e-9 } ?? Self.zoomRange.upperBound, anchor: anchor)
    }

    public mutating func zoomOut(anchor: CGPoint) {
        setZoom(Self.zoomLevels.last { $0 < zoom - 1e-9 } ?? Self.zoomRange.lowerBound, anchor: anchor)
    }

    /// Fits the canvas to the view, centered, without enlarging beyond 100%.
    public mutating func fit(canvasSize: CGSize, in viewSize: CGSize, margin: Double = 20) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let availableWidth = max(viewSize.width - 2 * margin, 1)
        let availableHeight = max(viewSize.height - 2 * margin, 1)
        let fitting = min(availableWidth / canvasSize.width, availableHeight / canvasSize.height) * documentScale
        zoom = Self.clamp(min(1, fitting))
        fitZoom = zoom
        center(canvasSize: canvasSize, in: viewSize)
    }

    public mutating func actualSize(canvasSize: CGSize, in viewSize: CGSize) {
        zoom = 1
        center(canvasSize: canvasSize, in: viewSize)
    }

    /// Moves the canvas, but only within its edges. Along a side that fits in the view there is no scrolling: the canvas stays
    /// where it is (even off-center after a fit, without jumping), just kept inside the view.
    public mutating func pan(by delta: CGSize, canvasSize: CGSize, in viewSize: CGSize, margin: Double = 20) {
        let content = CGSize(width: canvasSize.width * pointsPerPixel, height: canvasSize.height * pointsPerPixel)
        if content.width + 2 * margin > viewSize.width { origin.x += delta.width }
        if content.height + 2 * margin > viewSize.height { origin.y += delta.height }
        keepInView(canvasSize: canvasSize, in: viewSize, margin: margin)
    }

    /// Like a scrolling view: in each direction a canvas that fits in the view stays centered; a larger one
    /// moves only until its edges stay `margin` points from those of the view.
    public mutating func constrain(canvasSize: CGSize, in viewSize: CGSize, margin: Double = 20) {
        func axis(_ origin: Double, content: Double, view: Double) -> Double {
            if content + 2 * margin <= view { return (view - content) / 2 }
            return min(margin, max(view - content - margin, origin))
        }
        origin = CGPoint(x: axis(origin.x, content: canvasSize.width * pointsPerPixel, view: viewSize.width),
                         y: axis(origin.y, content: canvasSize.height * pointsPerPixel, view: viewSize.height))
    }

    /// The objects have been translated by `offset` (document pixels) to fit the canvas: it is moved the opposite way,
    /// so on screen they stay where they were.
    public mutating func shift(byCanvas offset: CGVector) {
        origin.x -= offset.dx * pointsPerPixel
        origin.y -= offset.dy * pointsPerPixel
    }

    /// After an edit: the canvas stays where it is as long as enough of it is visible; it is not recentered (objects would jump).
    /// A canvas smaller than the view stays entirely inside, a larger one leaves no gaps beyond `margin`.
    public mutating func keepInView(canvasSize: CGSize, in viewSize: CGSize, margin: Double = 20) {
        func axis(_ origin: Double, content: Double, view: Double) -> Double {
            if content + 2 * margin <= view { return min(max(origin, margin), view - content - margin) }
            return min(margin, max(view - content - margin, origin))
        }
        origin = CGPoint(x: axis(origin.x, content: canvasSize.width * pointsPerPixel, view: viewSize.width),
                         y: axis(origin.y, content: canvasSize.height * pointsPerPixel, view: viewSize.height))
    }

    private mutating func center(canvasSize: CGSize, in viewSize: CGSize) {
        origin = CGPoint(
            x: (viewSize.width - canvasSize.width * pointsPerPixel) / 2,
            y: (viewSize.height - canvasSize.height * pointsPerPixel) / 2
        )
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }
}
