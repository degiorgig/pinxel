import AppKit
import DocumentModel
import Foundation
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct EditorModelTests {
    // Inside the capture, away from the edges: none of these tests' commands changes the canvas.
    private let rect = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 30, y: 30, width: 50, height: 50), shape: .rectangle)))
    private let arrow = Annotation(id: TestDocuments.id(2), kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 30, y: 30), end: CGPoint(x: 80, y: 30)))))
    private let blur = Annotation(id: TestDocuments.id(3), kind: .blur(BlurData(rect: CGRect(x: 30, y: 30, width: 40, height: 40), radius: 12)))

    private func makeModel(_ annotations: [Annotation], clock: TestClock? = nil) -> EditorModel {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: annotations), assets: DictionaryAssetProvider([:]), undoManager: undo)
        if let clock { session.now = { clock.date } }
        return EditorModel(session: session)
    }

    private func annotation(_ id: UUID, in model: EditorModel) -> Annotation? {
        model.session.document.userAnnotations.first { $0.id == id }
    }

    @Test func inspectedStyleComesFromTheSelectionOrTheTool() {
        var thick = rect
        thick.style.lineWidth = 9
        let model = makeModel([thick])
        model.tool = .highlight
        #expect(model.inspectedStyle == ToolStyles.defaultStyle(for: .highlight))
        model.session.selection = [thick.id]
        #expect(model.inspectedStyle.lineWidth == 9)
    }

    @Test func inspectedKindFollowsTheSelectionThenTheTool() {
        let model = makeModel([rect, blur])
        model.tool = .arrow
        #expect(model.inspectedKind == .arrow)
        model.session.selection = [blur.id]
        #expect(model.inspectedKind == .effect)
        #expect(!model.inspectedKind.showsStroke)
        #expect(InspectedKind.shape.showsFill && InspectedKind.shape.showsDash)
    }

    @Test func setStyleOnTheSelectionIsOneUndoableCommand() {
        let model = makeModel([rect])
        model.session.selection = [rect.id]
        model.setStyle(\.lineWidth, 10)
        #expect(annotation(rect.id, in: model)?.style.lineWidth == 10)
        #expect(model.session.undoManager.undoActionName == CommandName.style)
        model.session.undoManager.undo()
        #expect(annotation(rect.id, in: model)?.style.lineWidth == 4)
    }

    @Test func setStyleWithoutSelectionChangesTheToolDefaults() {
        let model = makeModel([rect])
        model.tool = .arrow
        model.setStyle(\.stroke, .black)
        #expect(model.toolStyles.style(for: .arrow).stroke == .black)
        #expect(annotation(rect.id, in: model) == rect)
        #expect(!model.session.undoManager.canUndo)
    }

    @Test func styleChangesSkipLockedAnnotations() {
        var locked = rect
        locked.isLocked = true
        let model = makeModel([locked])
        model.session.selection = [locked.id]
        model.setStyle(\.lineWidth, 20)
        #expect(annotation(locked.id, in: model) == locked)
        #expect(!model.session.undoManager.canUndo)
    }

    @Test func previewStyleShowsWithoutChangingTheDocument() {
        let model = makeModel([rect])
        model.session.selection = [rect.id]
        model.previewStyle(\.opacity, 0.5)
        #expect(model.session.preview?.first { $0.id == rect.id }?.style.opacity == 0.5)
        #expect(annotation(rect.id, in: model)?.style.opacity == 1)
        model.setStyle(\.opacity, 0.5)
        #expect(model.session.preview == nil)
        #expect(annotation(rect.id, in: model)?.style.opacity == 0.5)
        model.session.undoManager.undo()
        #expect(annotation(rect.id, in: model)?.style.opacity == 1)
    }

    @Test func colorDragCoalescesIntoOneUndo() {
        let clock = TestClock()
        let model = makeModel([rect], clock: clock)
        model.session.selection = [rect.id]
        for shade in [0.2, 0.4, 0.6] {
            model.setStyle(\.stroke, RGBA(red: shade, green: 0, blue: 0), coalescing: true)
            clock.date += 0.2
        }
        #expect(annotation(rect.id, in: model)?.style.stroke == RGBA(red: 0.6, green: 0, blue: 0))
        model.session.undoManager.undo()
        #expect(annotation(rect.id, in: model)?.style.stroke == .accentRed)
        #expect(!model.session.undoManager.canUndo)
    }

    @Test func kindPropertiesUpdateTheSelectionOrTheTool() {
        let heads = ArrowHeads(start: .open, end: .circle)
        let model = makeModel([arrow])
        model.session.selection = [arrow.id]
        model.update(name: "Punte", selection: { $0.arrowHeads = heads }, tool: { $0.arrowHeads = heads })
        #expect(annotation(arrow.id, in: model)?.arrowHeads == heads)
        #expect(model.toolStyles.arrowHeads == ArrowHeads())
        model.session.selection = []
        model.update(name: "Punte", selection: { $0.arrowHeads = heads }, tool: { $0.arrowHeads = heads })
        #expect(model.toolStyles.arrowHeads == heads)
    }

    @Test func effectModeConvertsBlurAndPixelate() {
        let model = makeModel([blur])
        model.session.selection = [blur.id]
        model.setEffectMode(.pixelate)
        guard case .pixelate(let data) = annotation(blur.id, in: model)?.kind else { Issue.record("not pixelate"); return }
        #expect(data.blockSize == 12)
        #expect(annotation(blur.id, in: model)?.effectMode == .pixelate)
    }

    @Test func lockAndUnlockCommands() {
        let doc = TestDocuments.document(annotations: [rect])
        let lock = AnnotationEditing.setLocked(true, ids: [rect.id], in: doc)
        #expect(lock?.name == CommandName.lock)
        var locked = doc
        lock?.apply(to: &locked)
        #expect(locked.userAnnotations.first?.isLocked == true)
        #expect(AnnotationEditing.setLocked(true, ids: [rect.id], in: locked) == nil)
        #expect(AnnotationEditing.setLocked(false, ids: [rect.id], in: locked)?.name == CommandName.unlock)
    }

    @Test func duplicatesGetNewIDsAndAnOffset() {
        let copies = AnnotationEditing.duplicates(of: [rect], offset: CGSize(width: 10, height: 10), makeID: { TestDocuments.id(50) })
        #expect(copies.first?.id == TestDocuments.id(50))
        #expect(copies.first?.bounds.origin == CGPoint(x: 40, y: 40))
    }

    @Test func toolShortcutKeysSelectTools() {
        let model = makeModel([])
        #expect(model.selectTool(forKey: "r"))
        #expect(model.tool == .shape)
        #expect(!model.selectTool(forKey: "z"))
        #expect(!model.selectTool(forKey: "rr"))
        #expect(model.tool == .shape)
    }

    @Test func colorConversionRoundTrips() {
        let color = RGBA(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let back = RGBA(nsColor: color.nsColor)
        #expect(abs(back.red - 0.2) < 1e-6 && abs(back.green - 0.4) < 1e-6 && abs(back.blue - 0.6) < 1e-6 && abs(back.alpha - 0.8) < 1e-6)
    }
}
