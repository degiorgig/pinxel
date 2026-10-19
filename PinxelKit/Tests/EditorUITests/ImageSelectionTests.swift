import DocumentModel
import Foundation
import PinxelTestSupport
import Testing
@testable import EditorUI

struct ImageSelectionTests {
    let step = Annotation(id: TestDocuments.id(1), kind: .step(StepData(center: CGPoint(x: 100, y: 100), diameter: 20, label: StepLabel())),
                          style: Style(stroke: nil, fill: .accentRed))
    var document: PinxelDocument { TestDocuments.document(annotations: [step], size: PixelSize(width: 400, height: 300)) }

    func controller() -> ToolController {
        let controller = ToolController()
        controller.tool = .select
        return controller
    }

    @Test func clickOnTheCaptureSelectsIt() {
        let tool = controller()
        _ = tool.handle(.down(CGPoint(x: 300, y: 200), [], clickCount: 1), document: document, selection: [])
        let up = tool.handle(.up(CGPoint(x: 300, y: 200), []), document: document, selection: [])
        #expect(up.selection == [TestDocuments.captureID])
    }

    @Test func dragFromAnUnselectedCaptureDrawsTheMarquee() {
        let tool = controller()
        _ = tool.handle(.down(CGPoint(x: 80, y: 80), [], clickCount: 1), document: document, selection: [])
        let drag = tool.handle(.drag(CGPoint(x: 130, y: 130), []), document: document, selection: [])
        #expect(drag.marquee != nil)
        #expect(drag.preview == nil)
        let up = tool.handle(.up(CGPoint(x: 130, y: 130), []), document: document, selection: [])
        #expect(up.selection == [step.id])
        #expect(up.command == nil)
    }

    @Test func dragFromTheSelectedCaptureMovesIt() throws {
        let tool = controller()
        _ = tool.handle(.down(CGPoint(x: 300, y: 200), [], clickCount: 1), document: document, selection: [TestDocuments.captureID])
        _ = tool.handle(.drag(CGPoint(x: 320, y: 200), []), document: document, selection: [TestDocuments.captureID])
        let up = tool.handle(.up(CGPoint(x: 320, y: 200), []), document: document, selection: [TestDocuments.captureID])
        let update = try #require(up.command as? UpdateAnnotations)
        #expect(update.after.map(\.id) == [TestDocuments.captureID])
    }

    @Test func shiftClickAddsTheCapture() {
        let tool = controller()
        _ = tool.handle(.down(CGPoint(x: 300, y: 200), [.shift], clickCount: 1), document: document, selection: [step.id])
        let up = tool.handle(.up(CGPoint(x: 300, y: 200), [.shift]), document: document, selection: [step.id])
        #expect(up.selection == [step.id, TestDocuments.captureID])
    }

    @Test func annotationsStillMoveImmediately() throws {
        let tool = controller()
        _ = tool.handle(.down(CGPoint(x: 100, y: 100), [], clickCount: 1), document: document, selection: [])
        _ = tool.handle(.drag(CGPoint(x: 120, y: 100), []), document: document, selection: [step.id])
        let up = tool.handle(.up(CGPoint(x: 120, y: 100), []), document: document, selection: [step.id])
        #expect(up.command is UpdateAnnotations)
    }

    @Test func marqueeSelectsImagesOnlyWhenWhollyInside() {
        let annotations = document.annotations
        #expect(HitTesting.ids(intersecting: CGRect(x: 50, y: 50, width: 100, height: 100), in: annotations) == [step.id])
        #expect(HitTesting.ids(intersecting: CGRect(x: -10, y: -10, width: 420, height: 320), in: annotations) == [step.id, TestDocuments.captureID])
    }
}
