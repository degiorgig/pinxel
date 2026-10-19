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
    /// Zoom dell'ultimo adattamento alla finestra: i quadretti dello sfondo vi misurano 8 punti.
    public private(set) var fitZoom: Double = 1

    public static let checkerSquareRange: ClosedRange<Double> = 3...128

    /// Lato dei quadretti dello sfondo, in punti: crescono e calano con lo zoom, come se fossero sotto l'immagine.
    public var checkerSquare: Double {
        min(max(8 * zoom / fitZoom, Self.checkerSquareRange.lowerBound), Self.checkerSquareRange.upperBound)
    }

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
        fitZoom = zoom
        center(canvasSize: canvasSize, in: viewSize)
    }

    public mutating func actualSize(canvasSize: CGSize, in viewSize: CGSize) {
        zoom = 1
        center(canvasSize: canvasSize, in: viewSize)
    }

    /// Sposta la tela, ma solo entro i suoi bordi. Lungo un lato che entra nella vista non si scorre: la tela resta
    /// dov'è (anche fuori centro dopo un adattamento, senza saltare), solo tenuta dentro la vista.
    public mutating func pan(by delta: CGSize, canvasSize: CGSize, in viewSize: CGSize, margin: Double = 20) {
        let content = CGSize(width: canvasSize.width * pointsPerPixel, height: canvasSize.height * pointsPerPixel)
        if content.width + 2 * margin > viewSize.width { origin.x += delta.width }
        if content.height + 2 * margin > viewSize.height { origin.y += delta.height }
        keepInView(canvasSize: canvasSize, in: viewSize, margin: margin)
    }

    /// Come una vista che scorre: in ogni direzione la tela che entra nella vista resta centrata; quella più grande
    /// si sposta solo finché i suoi bordi restano a `margin` punti da quelli della vista.
    public mutating func constrain(canvasSize: CGSize, in viewSize: CGSize, margin: Double = 20) {
        func axis(_ origin: Double, content: Double, view: Double) -> Double {
            if content + 2 * margin <= view { return (view - content) / 2 }
            return min(margin, max(view - content - margin, origin))
        }
        origin = CGPoint(x: axis(origin.x, content: canvasSize.width * pointsPerPixel, view: viewSize.width),
                         y: axis(origin.y, content: canvasSize.height * pointsPerPixel, view: viewSize.height))
    }

    /// Gli oggetti sono stati traslati di `offset` (pixel del documento) per adattare la tela: la si sposta al contrario,
    /// così sullo schermo restano dove erano.
    public mutating func shift(byCanvas offset: CGVector) {
        origin.x -= offset.dx * pointsPerPixel
        origin.y -= offset.dy * pointsPerPixel
    }

    /// Dopo una modifica: la tela resta dov'è finché se ne vede abbastanza; non si ricentra (gli oggetti salterebbero).
    /// Una tela più piccola della vista resta tutta dentro, una più grande non lascia vuoti oltre `margin`.
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
