import CoreGraphics
import Foundation

/// Zoom e scorrimento del canvas. Le coordinate della vista sono in punti con origine in alto a sinistra
/// (vista capovolta); quelle della tela in pixel del documento, padding incluso.
public struct Viewport: Equatable, Sendable {
    public static let zoomLevels: [Double] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]
    public static let zoomRange: ClosedRange<Double> = 0.1...8

    /// 1 = 100%: un pixel dell'immagine occupa un pixel dello schermo (1/scale punti).
    public private(set) var zoom: Double
    /// Posizione nella vista dell'origine della tela.
    public var origin: CGPoint
    public let documentScale: Double

    public init(documentScale: Double, zoom: Double = 1, origin: CGPoint = .zero) {
        self.documentScale = documentScale > 0 && documentScale.isFinite ? documentScale : 1
        self.zoom = Self.clamp(zoom)
        self.origin = origin
    }

    /// Punti della vista per pixel del documento.
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

    /// Cambia lo zoom tenendo fermo sotto `anchor` (punto della vista) il punto della tela che c'era.
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

    /// Adatta la tela alla vista, centrata, senza ingrandire oltre il 100%.
    public mutating func fit(canvasSize: CGSize, in viewSize: CGSize, margin: Double = 20) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let availableWidth = max(viewSize.width - 2 * margin, 1)
        let availableHeight = max(viewSize.height - 2 * margin, 1)
        let fitting = min(availableWidth / canvasSize.width, availableHeight / canvasSize.height) * documentScale
        zoom = Self.clamp(min(1, fitting))
        center(canvasSize: canvasSize, in: viewSize)
    }

    public mutating func actualSize(canvasSize: CGSize, in viewSize: CGSize) {
        zoom = 1
        center(canvasSize: canvasSize, in: viewSize)
    }

    public mutating func pan(by delta: CGSize) {
        origin.x += delta.width
        origin.y += delta.height
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
