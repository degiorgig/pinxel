import CoreGraphics
import Foundation
import Testing
import DocumentModel
@testable import Rendering
import PinxelTestSupport

struct TextRenderingTests {
    let whiteBackground = TestImages.solid(width: 400, height: 300, red: 1, green: 1, blue: 1)

    func render(_ annotations: [Annotation]) throws -> CGImage {
        try DocumentRenderer().renderImage(TestDocuments.document(annotations: annotations), assets: assets(whiteBackground))
    }

    func nonWhitePixels(in image: CGImage, rect: CGRect) -> Int {
        let pixels = PixelBuffer(image)
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) where pixels.pixel(x: x, y: y) != white {
                count += 1
            }
        }
        return count
    }

    @Test func textSnapshot() throws {
        let styled = RichText(runs: [
            TextRun(text: "Grassetto ", bold: true),
            TextRun(text: "corsivo ", italic: true),
            TextRun(text: "sottolineato ", underline: true),
            TextRun(text: "rosso", color: .accentRed),
        ], fontSize: 18)
        let noBox = Style(stroke: nil)
        let annotations: [Annotation] = [
            Annotation(kind: .text(TextData(rect: CGRect(x: 10, y: 10, width: 380, height: 30), text: styled)), style: noBox),
            Annotation(kind: .text(TextData(rect: CGRect(x: 10, y: 45, width: 380, height: 30), text: RichText("Centrato", fontSize: 18, alignment: .center))), style: noBox),
            Annotation(kind: .text(TextData(rect: CGRect(x: 10, y: 80, width: 380, height: 30), text: RichText("A destra", fontSize: 18, alignment: .right))), style: Style(stroke: .black, fill: .highlightYellow, lineWidth: 1)),
            Annotation(kind: .callout(CalloutData(rect: CGRect(x: 150, y: 130, width: 200, height: 60), text: RichText("Clicca qui per salvare", fontSize: 16), tail: CalloutTail(tip: CGPoint(x: 90, y: 230)))),
                       style: Style(stroke: .accentRed, fill: .white, lineWidth: 2)),
            Annotation(kind: .step(StepData(center: CGPoint(x: 40, y: 260), diameter: 36)), style: Style(stroke: nil, fill: .accentRed)),
            Annotation(kind: .step(StepData(center: CGPoint(x: 90, y: 260), diameter: 36)), style: Style(stroke: nil, fill: .accentRed)),
            Annotation(kind: .step(StepData(center: CGPoint(x: 140, y: 260), diameter: 36, label: StepLabel(sequence: .uppercaseLetters))), style: Style(stroke: .white, fill: .black, lineWidth: 2)),
        ]
        Snapshot.assertMatches(try render(annotations), named: "text", tolerance: 0.02)
    }

    @Test func unicodeTextRenders() throws {
        let rect = CGRect(x: 20, y: 20, width: 360, height: 60)
        let annotation = Annotation(kind: .text(TextData(rect: rect, text: RichText("👋🏽 مرحبا 日本語 Ciao", fontSize: 28))), style: Style(stroke: nil))
        #expect(nonWhitePixels(in: try render([annotation]), rect: rect) > 100)
    }

    @Test func emptyTextDrawsNothing() throws {
        let annotations = [
            Annotation(kind: .text(TextData(rect: CGRect(x: 20, y: 20, width: 100, height: 40), text: RichText(""))), style: Style(stroke: nil)),
            Annotation(kind: .text(TextData(rect: CGRect(x: 20, y: 80, width: 0, height: 0), text: RichText("x"))), style: Style(stroke: nil)),
        ]
        let image = try render(annotations)
        #expect(PixelBuffer(image).differingPixelFraction(from: PixelBuffer(whiteBackground), channelTolerance: 1) == 0)
    }

    @Test func stepUsesComputedLabel() throws {
        // A single step "1" and the same with override "1": they must be identical.
        let automatic = Annotation(kind: .step(StepData(center: CGPoint(x: 50, y: 50), diameter: 40)), style: Style(stroke: nil, fill: .accentRed))
        let manual = Annotation(kind: .step(StepData(center: CGPoint(x: 50, y: 50), diameter: 40, label: StepLabel(override: "1"))), style: Style(stroke: nil, fill: .accentRed))
        let a = PixelBuffer(try render([automatic]))
        let b = PixelBuffer(try render([manual]))
        #expect(a.differingPixelFraction(from: b, channelTolerance: 0) == 0)
        #expect(a.pixel(x: 50, y: 34) != white) // inside the circle
    }
}
