import CoreGraphics
import DocumentModel
import Foundation
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
final class TestClock {
    var date = Date(timeIntervalSinceReferenceDate: 0)
}

@MainActor
struct EditorSessionTests {
    private func shape(_ n: Int, x: Double = 10, locked: Bool = false) -> Annotation {
        Annotation(id: TestDocuments.id(n), kind: .shape(ShapeData(rect: CGRect(x: x, y: 10, width: 50, height: 50), shape: .rectangle)), isLocked: locked)
    }

    private func makeSession(_ annotations: [Annotation] = [], readOnly: Bool = false, clock: TestClock? = nil) -> EditorSession {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(
            document: TestDocuments.document(annotations: annotations),
            assets: DictionaryAssetProvider([:]),
            undoManager: undo,
            isReadOnly: readOnly
        )
        if let clock { session.now = { clock.date } }
        return session
    }

    private func minX(_ n: Int, _ session: EditorSession) -> Double? {
        session.document.annotations.first { $0.id == TestDocuments.id(n) }.map { Double($0.bounds.minX) }
    }

    @Test func performAppliesAndUndoRedoRestore() {
        let session = makeSession()
        session.perform(AddAnnotations([shape(1)]))
        #expect(session.document.annotations == [shape(1)])
        session.undoManager.undo()
        #expect(session.document.annotations.isEmpty)
        session.undoManager.redo()
        #expect(session.document.annotations == [shape(1)])
    }

    @Test func undoMenuUsesTheCommandName() {
        let session = makeSession()
        session.perform(AddAnnotations([shape(1)], name: "Aggiungi forma"))
        #expect(session.undoManager.undoActionName == "Aggiungi forma")
    }

    @Test func readOnlySessionIgnoresEdits() {
        let session = makeSession([shape(1)], readOnly: true)
        session.selection = [TestDocuments.id(1)]
        session.perform(DeleteAnnotations(ids: [TestDocuments.id(1)], in: session.document))
        session.nudge(by: CGSize(width: 5, height: 0))
        #expect(session.document.annotations == [shape(1)])
        #expect(!session.undoManager.canUndo)
    }

    @Test func nudgesWithinOneSecondUndoTogether() {
        let clock = TestClock()
        let session = makeSession([shape(1)], clock: clock)
        session.selection = [TestDocuments.id(1)]
        for _ in 0..<3 {
            session.nudge(by: CGSize(width: 1, height: 0))
            clock.date += 0.4
        }
        #expect(minX(1, session) == 13)
        session.undoManager.undo()
        #expect(minX(1, session) == 10)
        #expect(!session.undoManager.canUndo)
    }

    @Test func nudgesFurtherApartUndoSeparately() {
        let clock = TestClock()
        let session = makeSession([shape(1)], clock: clock)
        session.selection = [TestDocuments.id(1)]
        session.nudge(by: CGSize(width: 1, height: 0))
        clock.date += 1.5
        session.nudge(by: CGSize(width: 1, height: 0))
        session.undoManager.undo()
        #expect(minX(1, session) == 11)
        session.undoManager.undo()
        #expect(minX(1, session) == 10)
    }

    @Test func anotherCommandBreaksCoalescing() {
        let clock = TestClock()
        let session = makeSession([shape(1)], clock: clock)
        session.selection = [TestDocuments.id(1)]
        session.nudge(by: CGSize(width: 1, height: 0))
        session.perform(AddAnnotations([shape(3, x: 200)]))
        clock.date += 0.1
        session.nudge(by: CGSize(width: 1, height: 0))
        #expect(minX(1, session) == 12)
        session.undoManager.undo()
        #expect(minX(1, session) == 11)
        session.undoManager.undo()
        #expect(session.document.annotations.count == 1)
        session.undoManager.undo()
        #expect(minX(1, session) == 10)
    }

    @Test func nudgeSkipsLockedAnnotations() {
        let session = makeSession([shape(1, locked: true)])
        session.selection = [TestDocuments.id(1)]
        session.nudge(by: CGSize(width: 1, height: 0))
        #expect(minX(1, session) == 10)
        #expect(!session.undoManager.canUndo)
    }

    @Test func selectionIsPrunedWhenAnnotationsDisappear() {
        let session = makeSession([shape(1)])
        session.selection = [TestDocuments.id(1)]
        session.perform(DeleteAnnotations(ids: [TestDocuments.id(1)], in: session.document))
        #expect(session.selection.isEmpty)
    }

    @Test func performClearsThePreview() {
        let session = makeSession()
        session.preview = [shape(9)]
        #expect(session.displayedAnnotations == [shape(9)])
        session.perform(AddAnnotations([shape(1)]))
        #expect(session.preview == nil)
        #expect(session.displayedAnnotations == [shape(1)])
    }

    @Test func undoingEverythingRestoresTheOriginalDocument() {
        let clock = TestClock()
        let session = makeSession([shape(1), shape(2, x: 100)], clock: clock)
        let original = session.document
        session.selection = [TestDocuments.id(1)]
        session.nudge(by: CGSize(width: 1, height: 0))
        session.nudge(by: CGSize(width: 0, height: 10))
        session.perform(ReorderAnnotations.bringToFront([TestDocuments.id(1)], in: session.document))
        session.perform(AddAnnotations([shape(3, x: 300)]))
        session.nudge(by: CGSize(width: -4, height: 0))
        while session.undoManager.canUndo { session.undoManager.undo() }
        #expect(session.document == original)
    }
}
