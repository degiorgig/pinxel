import DocumentModel
import Foundation
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct SessionFitTests {
    func makeSession() -> EditorSession {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return EditorSession(document: TestDocuments.document(annotations: [], size: PixelSize(width: 400, height: 300), scale: 1),
                             assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), undoManager: undo)
    }

    func captureRect(_ session: EditorSession) -> CGRect? {
        guard case .image(let data) = session.document.annotations.first(where: { $0.id == TestDocuments.captureID })?.kind else { return nil }
        return data.rect
    }

    @Test func movingTheCaptureLeftGrowsTheCanvasAndKeepsOriginZero() throws {
        let session = makeSession()
        let step = Annotation(kind: .step(StepData(center: CGPoint(x: 390, y: 290), diameter: 20, label: StepLabel())), style: Style(stroke: nil, fill: .accentRed))
        session.perform(AddAnnotations([step]))
        let capture = try #require(session.document.annotations.first { $0.id == TestDocuments.captureID })
        var shifts: [CGVector] = []
        session.onCanvasShift = { shifts.append($0) }
        session.perform(UpdateAnnotations(name: "Sposta", before: [capture], after: [AnnotationGeometry.moved(capture, by: CGSize(width: -100, height: 0))]))
        #expect(captureRect(session) == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(session.document.canvasSize == PixelSize(width: 500, height: 300))
        #expect(shifts == [CGVector(dx: 100, dy: 0)])
        session.undoManager.undo()
        #expect(session.document.canvasSize == PixelSize(width: 400, height: 300))
        #expect(captureRect(session) == CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(shifts.last == CGVector(dx: -100, dy: 0))
    }

    @Test func deletingEverythingLeavesAnEmptyCanvas() {
        let session = makeSession()
        session.perform(DeleteAnnotations(ids: Set(session.document.annotations.map(\.id)), in: session.document))
        #expect(session.document.canvasSize == PixelSize(width: 0, height: 0))
        session.undoManager.undo()
        #expect(session.document.canvasSize == PixelSize(width: 400, height: 300))
    }

    @Test func oneActionIsOneUndoStep() throws {
        let session = makeSession()
        let capture = try #require(session.document.annotations.first)
        session.perform(UpdateAnnotations(name: "Sposta", before: [capture], after: [AnnotationGeometry.moved(capture, by: CGSize(width: 50, height: 50))]))
        #expect(session.undoManager.undoActionName == "Sposta")
        session.undoManager.undo()
        #expect(!session.undoManager.canUndo)
    }

    @Test func nudgesAcrossAFitUndoExactly() throws {
        let session = makeSession()
        let original = session.document
        session.selection = [TestDocuments.captureID]
        session.nudge(by: CGSize(width: -1, height: 0))
        session.nudge(by: CGSize(width: -1, height: 0))
        session.nudge(by: CGSize(width: 0, height: 5))
        while session.undoManager.canUndo { session.undoManager.undo() }
        #expect(session.document == original)
    }

    @Test func nudgesThatDoNotChangeTheCanvasStillMerge() throws {
        let session = makeSession()
        let step = Annotation(kind: .step(StepData(center: CGPoint(x: 100, y: 100), diameter: 20, label: StepLabel())), style: Style(stroke: nil, fill: .accentRed))
        session.perform(AddAnnotations([step]))
        session.selection = [step.id]
        session.nudge(by: CGSize(width: 1, height: 0))
        session.nudge(by: CGSize(width: 1, height: 0))
        session.undoManager.undo()
        guard case .step(let data) = session.document.annotations.last?.kind else { Issue.record("no step"); return }
        #expect(data.center == CGPoint(x: 100, y: 100))
    }
}
