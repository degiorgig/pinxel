import Foundation
import DocumentModel

public enum TestDocuments {
    public static let background = ImageAssetRef(name: "background.png")
    public static let placedImage = ImageAssetRef(name: "assets/00000000-0000-0000-0000-000000000001.png")

    public static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    /// Una annotazione per ogni tipo, disposte su un'immagine 400×300.
    public static func allKindsAnnotations() -> [Annotation] {
        [
            Annotation(id: id(1), kind: .arrow(ArrowData(
                line: LineGeometry(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 140, y: 80)),
                heads: ArrowHeads(start: .none, end: .triangle)))),
            Annotation(id: id(2), kind: .line(LineData(
                line: LineGeometry(start: CGPoint(x: 20, y: 120), end: CGPoint(x: 140, y: 120)))),
                style: Style(stroke: .black, lineWidth: 2, dash: .dashed)),
            Annotation(id: id(3), kind: .shape(ShapeData(
                rect: CGRect(x: 180, y: 20, width: 100, height: 60), shape: .roundedRectangle(cornerRadius: 10)))),
            Annotation(id: id(4), kind: .shape(ShapeData(
                rect: CGRect(x: 300, y: 20, width: 80, height: 60), shape: .ellipse)),
                style: Style(stroke: .black, fill: .highlightYellow, lineWidth: 3)),
            Annotation(id: id(5), kind: .text(TextData(
                rect: CGRect(x: 20, y: 150, width: 160, height: 40), text: RichText("Ciao Pinxel"))),
                style: Style(stroke: nil)),
            Annotation(id: id(6), kind: .callout(CalloutData(
                rect: CGRect(x: 200, y: 110, width: 160, height: 60),
                text: RichText("Clicca qui", fontSize: 18),
                tail: CalloutTail(tip: CGPoint(x: 180, y: 220)))),
                style: Style(stroke: .accentRed, fill: .white, lineWidth: 2)),
            Annotation(id: id(7), kind: .step(StepData(center: CGPoint(x: 40, y: 230), diameter: 36, label: StepLabel())),
                style: Style(stroke: nil, fill: .accentRed)),
            Annotation(id: id(8), kind: .step(StepData(center: CGPoint(x: 90, y: 230), diameter: 36, label: StepLabel())),
                style: Style(stroke: nil, fill: .accentRed)),
            Annotation(id: id(9), kind: .highlight(HighlightData(
                path: PathGeometry(points: [CGPoint(x: 120, y: 270), CGPoint(x: 260, y: 270)]))),
                style: Style(stroke: .highlightYellow, lineWidth: 16, opacity: 0.5)),
            Annotation(id: id(10), kind: .pen(PenData(
                path: PathGeometry(points: [CGPoint(x: 280, y: 200), CGPoint(x: 300, y: 240), CGPoint(x: 330, y: 210), CGPoint(x: 360, y: 250)]),
                smoothing: 1))),
            Annotation(id: id(11), kind: .blur(BlurData(rect: CGRect(x: 150, y: 190, width: 50, height: 40), radius: 8))),
            Annotation(id: id(12), kind: .pixelate(PixelateData(rect: CGRect(x: 210, y: 190, width: 50, height: 40), blockSize: 10))),
            Annotation(id: id(13), kind: .magnifier(MagnifierData(
                source: CGRect(x: 190, y: 140, width: 20, height: 20),
                target: CGRect(x: 320, y: 90, width: 60, height: 60),
                shape: .ellipse, showsConnector: true)),
                style: Style(stroke: .black, lineWidth: 2)),
            Annotation(id: id(14), kind: .image(PlacedImageData(
                rect: CGRect(x: 330, y: 250, width: 40, height: 30), asset: placedImage))),
        ]
    }

    public static func document(
        annotations: [Annotation] = allKindsAnnotations(),
        size: PixelSize = PixelSize(width: 400, height: 300),
        scale: Double = 2
    ) -> PinxelDocument {
        PinxelDocument(
            background: background,
            canvasSize: size,
            scale: scale,
            annotations: annotations,
            metadata: CaptureMetadata(
                captureDate: Date(timeIntervalSinceReferenceDate: 800_000_000),
                appName: "Finder",
                bundleIdentifier: "com.apple.finder",
                windowTitle: "Documenti"
            )
        )
    }
}
