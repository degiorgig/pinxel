import CoreGraphics
import DocumentModel
import PinxelTestSupport
import Testing
@testable import EditorUI

struct CreationToolTests {
    private let empty = TestDocuments.document(annotations: [])

    private func controller(_ tool: EditorTool) -> ToolController {
        let controller = ToolController()
        controller.tool = tool
        controller.dragThreshold = 3
        var next = 100
        controller.makeID = {
            next += 1
            return TestDocuments.id(next)
        }
        return controller
    }

    private func drag(_ controller: ToolController, from start: CGPoint, through points: [CGPoint] = [], to end: CGPoint,
                      modifiers: ToolModifiers = [], document: PinxelDocument? = nil) -> ToolResult {
        let doc = document ?? empty
        _ = controller.handle(.down(start, modifiers, clickCount: 1), document: doc, selection: [])
        for point in points { _ = controller.handle(.drag(point, modifiers), document: doc, selection: []) }
        return controller.handle(.up(end, modifiers), document: doc, selection: [])
    }

    private func created(_ result: ToolResult, in document: PinxelDocument? = nil) -> Annotation? {
        var doc = document ?? empty
        result.command?.apply(to: &doc)
        return doc.annotations.last
    }

    @Test func arrowDragCreatesAnArrowWithTheToolStyle() {
        let tool = controller(.arrow)
        tool.styles.arrowHeads = ArrowHeads(start: .circle, end: .triangle)
        let result = drag(tool, from: CGPoint(x: 10, y: 10), through: [CGPoint(x: 50, y: 10)], to: CGPoint(x: 100, y: 10))
        #expect(result.command?.name == "Aggiungi freccia")
        #expect(result.selection == [TestDocuments.id(101)])
        guard let arrow = created(result), case .arrow(let data) = arrow.kind else { Issue.record("no arrow"); return }
        #expect(data.line.start == CGPoint(x: 10, y: 10) && data.line.end == CGPoint(x: 100, y: 10))
        #expect(data.heads.start == .circle)
        #expect(arrow.style == tool.styles.style(for: .arrow))
    }

    @Test func shiftConstrainsLinesTo45Degrees() {
        let result = drag(controller(.line), from: .zero, to: CGPoint(x: 100, y: 90), modifiers: .shift)
        guard let line = created(result), case .line(let data) = line.kind else { Issue.record("no line"); return }
        #expect(abs(data.line.end.x - data.line.end.y) < 1e-9)
    }

    @Test func shapeDragUsesTheShapeTypeAndShiftMakesASquare() {
        let tool = controller(.shape)
        tool.styles.shapeType = .ellipse
        let result = drag(tool, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 30), modifiers: .shift)
        guard let shape = created(result), case .shape(let data) = shape.kind else { Issue.record("no shape"); return }
        #expect(data.rect == CGRect(x: 10, y: 10, width: 50, height: 50))
        #expect(data.shape == .ellipse)
    }

    @Test func tinyDragsCreateNothing() {
        #expect(drag(controller(.shape), from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 11)).command == nil)
        #expect(drag(controller(.shape), from: CGPoint(x: 10, y: 10), to: CGPoint(x: 80, y: 11)).command == nil)
        #expect(drag(controller(.arrow), from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10)).command == nil)
        #expect(drag(controller(.pen), from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10)).command == nil)
        #expect(drag(controller(.blur), from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 40)).command == nil)
    }

    @Test func penCollectsThePath() {
        let result = drag(controller(.pen), from: .zero,
                          through: [CGPoint(x: 0.5, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 5)],
                          to: CGPoint(x: 10, y: 5))
        guard let pen = created(result), case .pen(let data) = pen.kind else { Issue.record("no pen"); return }
        #expect(data.path.points == [.zero, CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 5)])
    }

    @Test func highlighterUsesItsOwnStyle() {
        let result = drag(controller(.highlight), from: .zero, through: [CGPoint(x: 50, y: 0)], to: CGPoint(x: 100, y: 0))
        guard let highlight = created(result), case .highlight = highlight.kind else { Issue.record("no highlight"); return }
        #expect(highlight.style.stroke == .highlightYellow)
        #expect(highlight.style.lineWidth == 24)
    }

    @Test func stepClicksPlaceNumberedSteps() {
        let tool = controller(.step)
        let down = tool.handle(.down(CGPoint(x: 40, y: 40), [], clickCount: 1), document: empty, selection: [])
        #expect(down.preview?.count == 1)
        var doc = empty
        tool.handle(.up(CGPoint(x: 40, y: 40), []), document: doc, selection: []).command?.apply(to: &doc)
        _ = tool.handle(.down(CGPoint(x: 80, y: 40), [], clickCount: 1), document: doc, selection: [])
        tool.handle(.up(CGPoint(x: 80, y: 40), []), document: doc, selection: []).command?.apply(to: &doc)
        let labels = StepNumbering.labels(for: doc.annotations)
        #expect(labels[TestDocuments.id(101)] == "1")
        #expect(labels[TestDocuments.id(102)] == "2")
        guard case .step(let data) = doc.annotations.first?.kind else { Issue.record("no step"); return }
        #expect(data.diameter == tool.styles.stepDiameter)
        #expect(data.center == CGPoint(x: 40, y: 40))
    }

    @Test func blurToolHonorsTheEffectMode() {
        guard let blur = created(drag(controller(.blur), from: .zero, to: CGPoint(x: 40, y: 40))),
              case .blur(let blurData) = blur.kind else { Issue.record("no blur"); return }
        #expect(blurData.radius == 12)
        let pixelTool = controller(.blur)
        pixelTool.styles.effectMode = .pixelate
        pixelTool.styles.effectAmount = 20
        guard let pixel = created(drag(pixelTool, from: .zero, to: CGPoint(x: 40, y: 40))),
              case .pixelate(let pixelData) = pixel.kind else { Issue.record("no pixelate"); return }
        #expect(pixelData.blockSize == 20)
    }

    @Test func creationPreviewShowsTheNewAnnotationOnTopOfTheDocument() {
        let existing = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 0, y: 0, width: 10, height: 10), shape: .rectangle)))
        let doc = TestDocuments.document(annotations: [existing])
        let tool = controller(.shape)
        _ = tool.handle(.down(CGPoint(x: 20, y: 20), [], clickCount: 1), document: doc, selection: [])
        let drag = tool.handle(.drag(CGPoint(x: 60, y: 60), []), document: doc, selection: [])
        #expect(drag.preview?.count == 2)
        #expect(drag.preview?.first == existing)
        #expect(drag.preview?.last?.id == TestDocuments.id(101))
    }

    @Test func changingToolCancelsTheGesture() {
        let tool = controller(.shape)
        _ = tool.handle(.down(CGPoint(x: 20, y: 20), [], clickCount: 1), document: empty, selection: [])
        tool.tool = .arrow
        #expect(tool.handle(.up(CGPoint(x: 80, y: 80), []), document: empty, selection: []).command == nil)
    }
}
