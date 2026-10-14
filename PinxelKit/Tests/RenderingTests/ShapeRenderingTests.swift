import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

struct ShapeRenderingTests {
    let whiteBackground = TestImages.solid(width: 400, height: 300, red: 1, green: 1, blue: 1)

    func render(_ annotations: [Annotation], background: CGImage? = nil) throws -> CGImage {
        try DocumentRenderer().renderImage(TestDocuments.document(annotations: annotations), assets: assets(background ?? whiteBackground))
    }

    @Test func shapesSnapshot() throws {
        let annotations: [Annotation] = [
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 20, y: 30), end: CGPoint(x: 160, y: 30)), heads: ArrowHeads(start: .none, end: .triangle)))),
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 20, y: 70), end: CGPoint(x: 160, y: 70)), heads: ArrowHeads(start: .circle, end: .open))), style: Style(stroke: .black, lineWidth: 3)),
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 20, y: 140), end: CGPoint(x: 160, y: 100)), heads: ArrowHeads(start: .triangle, end: .triangle))), style: Style(lineWidth: 8)),
            Annotation(kind: .line(LineData(line: LineGeometry(start: CGPoint(x: 20, y: 170), end: CGPoint(x: 160, y: 170)))), style: Style(stroke: .black, lineWidth: 2)),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 200, y: 20, width: 80, height: 50), shape: .rectangle))),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 300, y: 20, width: 80, height: 50), shape: .roundedRectangle(cornerRadius: 12))), style: Style(stroke: .black, fill: .highlightYellow, lineWidth: 2)),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 200, y: 90, width: 80, height: 50), shape: .ellipse)), style: Style(stroke: nil, fill: .accentRed)),
            Annotation(kind: .pen(PenData(path: PathGeometry(points: [CGPoint(x: 300, y: 100), CGPoint(x: 320, y: 140), CGPoint(x: 340, y: 100), CGPoint(x: 360, y: 140), CGPoint(x: 380, y: 100)]), smoothing: 1)), style: Style(stroke: .black, lineWidth: 3)),
            Annotation(kind: .highlight(HighlightData(path: PathGeometry(points: [CGPoint(x: 20, y: 220), CGPoint(x: 380, y: 220)]))), style: Style(stroke: .highlightYellow, lineWidth: 20)),
        ]
        Snapshot.assertMatches(try render(annotations), named: "shapes")
    }

    @Test func stylesSnapshot() throws {
        let rect = CGRect(x: 40, y: 40, width: 100, height: 60)
        let annotations: [Annotation] = [
            Annotation(kind: .shape(ShapeData(rect: rect, shape: .rectangle)), style: Style(lineWidth: 4, dash: .dashed)),
            Annotation(kind: .shape(ShapeData(rect: rect.offsetBy(dx: 160, dy: 0), shape: .rectangle)), style: Style(stroke: .black, lineWidth: 4, dash: .dotted)),
            Annotation(kind: .shape(ShapeData(rect: rect.offsetBy(dx: 0, dy: 120), shape: .rectangle)), style: Style(stroke: .accentRed, fill: .accentRed), rotation: .pi / 6),
            Annotation(kind: .shape(ShapeData(rect: rect.offsetBy(dx: 160, dy: 120), shape: .ellipse)),
                       style: Style(stroke: .black, fill: .highlightYellow, lineWidth: 3, opacity: 0.5, shadow: Shadow(offset: CGSize(width: 4, height: 6), blur: 6, color: .black))),
        ]
        Snapshot.assertMatches(try render(annotations), named: "styles")
    }

    @Test func highlighterMultipliesWithBackground() throws {
        // Giallo in multiply sul quadrante blu (in basso a sinistra) dà quasi nero.
        let highlight = Annotation(kind: .highlight(HighlightData(path: PathGeometry(points: [CGPoint(x: 20, y: 250), CGPoint(x: 180, y: 250)]))),
                                   style: Style(stroke: RGBA(red: 1, green: 1, blue: 0), lineWidth: 20))
        let pixels = PixelBuffer(try render([highlight], background: TestImages.quadrants()))
        let p = pixels.pixel(x: 100, y: 250)
        #expect(p.r < 30 && p.g < 30 && p.b < 30, "got \(p)")
    }

    @Test func degenerateAnnotationsDoNotCrash() throws {
        let nothing: [Annotation] = [
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 50, y: 50, width: 0, height: 0), shape: .roundedRectangle(cornerRadius: 30)))),
            Annotation(kind: .pen(PenData(path: PathGeometry(points: [])))),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: CGFloat.nan, y: 10, width: 10, height: 10), shape: .rectangle))),
            Annotation(kind: .line(LineData(line: LineGeometry(start: CGPoint(x: CGFloat.infinity, y: 0), end: CGPoint(x: 1, y: 1))))),
        ]
        let image = try render(nothing)
        #expect(PixelBuffer(image).differingPixelFraction(from: PixelBuffer(whiteBackground), channelTolerance: 1) == 0)

        // Freccia lunga zero e penna con un solo punto: un punto è accettabile, un crash no.
        let dots: [Annotation] = [
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 80, y: 80), end: CGPoint(x: 80, y: 80))))),
            Annotation(kind: .pen(PenData(path: PathGeometry(points: [CGPoint(x: 120, y: 120)])))),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 1e300, y: 1e300, width: 5, height: 5), shape: .ellipse))),
        ]
        let dotted = try render(dots)
        #expect(dotted.width == 400 && dotted.height == 300)
    }
}
