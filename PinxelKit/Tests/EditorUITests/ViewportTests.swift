import CoreGraphics
import Testing
@testable import EditorUI

struct ViewportTests {
    private func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    @Test func retinaHundredPercentIsHalfAPointPerPixel() {
        #expect(Viewport(documentScale: 2).pointsPerPixel == 0.5)
        #expect(Viewport(documentScale: 1).pointsPerPixel == 1)
    }

    @Test func viewAndCanvasPointsRoundTrip() {
        let viewport = Viewport(documentScale: 2, zoom: 1.5, origin: CGPoint(x: 30, y: -12))
        let point = CGPoint(x: 123, y: 45)
        #expect(close(viewport.canvasPoint(fromView: viewport.viewPoint(fromCanvas: point)), point))
        #expect(viewport.viewRect(fromCanvas: CGRect(x: 0, y: 0, width: 100, height: 40))
            == CGRect(x: 30, y: -12, width: 75, height: 30))
    }

    @Test func zoomKeepsTheAnchorFixed() {
        var viewport = Viewport(documentScale: 1, origin: CGPoint(x: 10, y: 20))
        let anchor = CGPoint(x: 200, y: 150)
        let before = viewport.canvasPoint(fromView: anchor)
        viewport.setZoom(3, anchor: anchor)
        #expect(viewport.zoom == 3)
        #expect(close(viewport.canvasPoint(fromView: anchor), before))
    }

    @Test func zoomIsClamped() {
        var viewport = Viewport(documentScale: 1)
        viewport.setZoom(100, anchor: .zero)
        #expect(viewport.zoom == 8)
        viewport.setZoom(0.001, anchor: .zero)
        #expect(viewport.zoom == 0.1)
        viewport.setZoom(.nan, anchor: .zero)
        #expect(viewport.zoom == 1)
    }

    @Test func zoomStepsFollowTheLevels() {
        var viewport = Viewport(documentScale: 1)
        viewport.zoomIn(anchor: .zero)
        #expect(viewport.zoom == 1.5)
        viewport.zoomOut(anchor: .zero)
        viewport.zoomOut(anchor: .zero)
        #expect(viewport.zoom == 0.75)
        viewport.setZoom(8, anchor: .zero)
        viewport.zoomIn(anchor: .zero)
        #expect(viewport.zoom == 8)
        viewport.setZoom(0.1, anchor: .zero)
        viewport.zoomOut(anchor: .zero)
        #expect(viewport.zoom == 0.1)
    }

    @Test func fitNeverUpscalesAndCenters() {
        var viewport = Viewport(documentScale: 1)
        viewport.fit(canvasSize: CGSize(width: 200, height: 100), in: CGSize(width: 800, height: 600))
        #expect(viewport.zoom == 1)
        #expect(viewport.origin == CGPoint(x: 300, y: 250))
    }

    @Test func fitShrinksALargeCanvas() {
        var viewport = Viewport(documentScale: 1)
        viewport.fit(canvasSize: CGSize(width: 2000, height: 1000), in: CGSize(width: 1040, height: 540))
        #expect(viewport.zoom == 0.5)
        #expect(viewport.origin == CGPoint(x: 20, y: 20))
    }

    @Test func fitUsesRetinaPointSize() {
        var viewport = Viewport(documentScale: 2)
        viewport.fit(canvasSize: CGSize(width: 800, height: 600), in: CGSize(width: 1000, height: 800))
        #expect(viewport.zoom == 1)
        #expect(viewport.origin == CGPoint(x: 300, y: 250))
    }

    @Test func fitIgnoresAnEmptyCanvas() {
        var viewport = Viewport(documentScale: 1, zoom: 2)
        viewport.fit(canvasSize: .zero, in: CGSize(width: 800, height: 600))
        #expect(viewport.zoom == 2)
    }

    @Test func actualSizeCentersAtHundredPercent() {
        var viewport = Viewport(documentScale: 2, zoom: 0.25)
        viewport.actualSize(canvasSize: CGSize(width: 400, height: 200), in: CGSize(width: 600, height: 300))
        #expect(viewport.zoom == 1)
        #expect(viewport.origin == CGPoint(x: 200, y: 100))
    }

    @Test func checkerSquaresAreEightPointsWhenFitted() {
        var viewport = Viewport(documentScale: 1)
        viewport.fit(canvasSize: CGSize(width: 4000, height: 3000), in: CGSize(width: 1000, height: 800))
        #expect(viewport.checkerSquare == 8)
    }

    @Test func checkerSquaresFollowTheZoom() {
        var viewport = Viewport(documentScale: 1)
        viewport.fit(canvasSize: CGSize(width: 4000, height: 3000), in: CGSize(width: 1000, height: 800))
        let fitted = viewport.zoom
        viewport.setZoom(fitted * 2, anchor: .zero)
        #expect(abs(viewport.checkerSquare - 16) < 1e-9)
        viewport.setZoom(fitted / 2, anchor: .zero)
        #expect(abs(viewport.checkerSquare - 4) < 1e-9)
    }

    @Test func checkerSquaresStayVisibleAndBounded() {
        var large = Viewport(documentScale: 1)
        large.fit(canvasSize: CGSize(width: 4000, height: 3000), in: CGSize(width: 1000, height: 800))
        large.setZoom(8, anchor: .zero)
        #expect(large.checkerSquare == Viewport.checkerSquareRange.upperBound)
        var viewport = Viewport(documentScale: 1)
        viewport.fit(canvasSize: CGSize(width: 100, height: 100), in: CGSize(width: 1000, height: 800))
        viewport.setZoom(0.1, anchor: .zero)
        #expect(viewport.checkerSquare == Viewport.checkerSquareRange.lowerBound)
    }
}
