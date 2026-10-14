import CoreGraphics
import DocumentModel
import PinxelTestSupport
import Testing
@testable import EditorUI

struct SelectToolTests {
    private let a = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 100, y: 100, width: 100, height: 50), shape: .rectangle)), style: Style(fill: .white))
    private let b = Annotation(id: TestDocuments.id(2), kind: .shape(ShapeData(rect: CGRect(x: 300, y: 100, width: 50, height: 50), shape: .rectangle)), style: Style(fill: .white))

    private func document(_ annotations: [Annotation]) -> PinxelDocument {
        TestDocuments.document(annotations: annotations)
    }

    private func controller() -> ToolController {
        let controller = ToolController()
        controller.hitTolerance = 4
        controller.rotationHandleOffset = 30
        controller.dragThreshold = 3
        var next = 100
        controller.makeID = {
            next += 1
            return TestDocuments.id(next)
        }
        return controller
    }

    private func applied(_ result: ToolResult, to document: PinxelDocument) -> PinxelDocument {
        var copy = document
        result.command?.apply(to: &copy)
        return copy
    }

    @Test func clickSelectsTheTopmostAnnotation() {
        let tool = controller()
        let doc = document([a, b])
        #expect(tool.handle(.down(CGPoint(x: 150, y: 125), [], clickCount: 1), document: doc, selection: []).selection == [a.id])
        let up = tool.handle(.up(CGPoint(x: 150, y: 125), []), document: doc, selection: [a.id])
        #expect(up.command == nil)
    }

    @Test func clickOnEmptySpaceClearsTheSelection() {
        let tool = controller()
        let doc = document([a])
        #expect(tool.handle(.down(CGPoint(x: 20, y: 20), [], clickCount: 1), document: doc, selection: [a.id]).selection == [])
        let up = tool.handle(.up(CGPoint(x: 20, y: 20), []), document: doc, selection: [])
        #expect(up.selection == [])
        #expect(up.marquee == nil)
    }

    @Test func shiftClickTogglesTheSelection() {
        let tool = controller()
        let doc = document([a, b])
        let added = tool.handle(.down(CGPoint(x: 320, y: 120), .shift, clickCount: 1), document: doc, selection: [a.id])
        #expect(added.selection == [a.id, b.id])
        _ = tool.handle(.up(CGPoint(x: 320, y: 120), .shift), document: doc, selection: [a.id, b.id])
        let removed = tool.handle(.down(CGPoint(x: 150, y: 125), .shift, clickCount: 1), document: doc, selection: [a.id, b.id])
        #expect(removed.selection == [b.id])
    }

    @Test func marqueeSelectsAndShiftAdds() {
        let tool = controller()
        let doc = document([a, b])
        _ = tool.handle(.down(.zero, [], clickCount: 1), document: doc, selection: [])
        let drag = tool.handle(.drag(CGPoint(x: 220, y: 160), []), document: doc, selection: [])
        #expect(drag.selection == [a.id])
        #expect(drag.marquee == CGRect(x: 0, y: 0, width: 220, height: 160))
        #expect(tool.handle(.up(CGPoint(x: 220, y: 160), []), document: doc, selection: [a.id]).selection == [a.id])

        _ = tool.handle(.down(.zero, .shift, clickCount: 1), document: doc, selection: [b.id])
        #expect(tool.handle(.up(CGPoint(x: 220, y: 160), .shift), document: doc, selection: [b.id]).selection == [a.id, b.id])
    }

    @Test func dragMovesTheSelectionAsOneCommandOnMouseUp() {
        let tool = controller()
        let doc = document([a, b])
        _ = tool.handle(.down(CGPoint(x: 150, y: 125), [], clickCount: 1), document: doc, selection: [])
        let drag = tool.handle(.drag(CGPoint(x: 160, y: 125), []), document: doc, selection: [a.id])
        #expect(drag.preview?.first { $0.id == a.id }?.bounds.minX == 110)
        #expect(drag.command == nil)
        _ = tool.handle(.drag(CGPoint(x: 170, y: 125), []), document: doc, selection: [a.id])
        let up = tool.handle(.up(CGPoint(x: 170, y: 125), []), document: doc, selection: [a.id])
        #expect(up.command?.name == "Sposta")
        #expect(applied(up, to: doc).annotations.first { $0.id == a.id }?.bounds.minX == 120)
    }

    @Test func smallJitterIsAClickNotAMove() {
        let tool = controller()
        let doc = document([a])
        _ = tool.handle(.down(CGPoint(x: 150, y: 125), [], clickCount: 1), document: doc, selection: [])
        let drag = tool.handle(.drag(CGPoint(x: 151, y: 125), []), document: doc, selection: [a.id])
        #expect(drag.preview == nil)
        #expect(tool.handle(.up(CGPoint(x: 151, y: 125), []), document: doc, selection: [a.id]).command == nil)
    }

    @Test func optionDragDuplicates() {
        let tool = controller()
        let doc = document([a])
        _ = tool.handle(.down(CGPoint(x: 150, y: 125), .option, clickCount: 1), document: doc, selection: [])
        let drag = tool.handle(.drag(CGPoint(x: 150, y: 175), .option), document: doc, selection: [a.id])
        #expect(drag.preview?.count == 2)
        let up = tool.handle(.up(CGPoint(x: 150, y: 175), .option), document: doc, selection: [a.id])
        #expect(up.command?.name == "Duplica")
        #expect(up.selection == [TestDocuments.id(101)])
        let result = applied(up, to: doc)
        #expect(result.annotations.count == 2)
        #expect(result.annotations.first { $0.id == a.id } == a)
        #expect(result.annotations.first { $0.id == TestDocuments.id(101) }?.bounds.minY == 150)
    }

    @Test func shiftDragLocksToTheDominantAxis() {
        let tool = controller()
        let doc = document([a])
        _ = tool.handle(.down(CGPoint(x: 150, y: 125), [], clickCount: 1), document: doc, selection: [])
        let drag = tool.handle(.drag(CGPoint(x: 190, y: 135), .shift), document: doc, selection: [a.id])
        #expect(drag.preview?.first?.bounds.origin == CGPoint(x: 140, y: 100))
    }

    @Test func resizeThroughAHandle() {
        let tool = controller()
        let doc = document([a])
        _ = tool.handle(.down(CGPoint(x: 200, y: 150), [], clickCount: 1), document: doc, selection: [a.id])
        _ = tool.handle(.drag(CGPoint(x: 230, y: 180), []), document: doc, selection: [a.id])
        let up = tool.handle(.up(CGPoint(x: 250, y: 200), []), document: doc, selection: [a.id])
        #expect(up.command?.name == "Ridimensiona")
        #expect(applied(up, to: doc).annotations.first?.bounds == CGRect(x: 100, y: 100, width: 150, height: 100))
    }

    @Test func rotateThroughTheRotationHandleSnapsWithShift() {
        let tool = controller()
        let doc = document([a])
        _ = tool.handle(.down(CGPoint(x: 150, y: 70), [], clickCount: 1), document: doc, selection: [a.id])
        let up = tool.handle(.up(CGPoint(x: 250, y: 130), .shift), document: doc, selection: [a.id])
        #expect(up.command?.name == "Ruota")
        let rotation = applied(up, to: doc).annotations.first?.rotation ?? 0
        #expect(abs(rotation - .pi / 2) < 1e-9)
    }

    @Test func lockedAnnotationIsSelectableButNotMovedOrDeleted() {
        var locked = a
        locked.isLocked = true
        let tool = controller()
        let doc = document([locked])
        #expect(tool.handle(.down(CGPoint(x: 150, y: 125), [], clickCount: 1), document: doc, selection: []).selection == [a.id])
        #expect(tool.handle(.drag(CGPoint(x: 190, y: 125), []), document: doc, selection: [a.id]).preview == nil)
        #expect(tool.handle(.up(CGPoint(x: 190, y: 125), []), document: doc, selection: [a.id]).command == nil)
        #expect(tool.handle(.key(.delete, []), document: doc, selection: [a.id]).command == nil)
    }

    @Test func deleteKeyDeletesTheUnlockedSelection() {
        var locked = b
        locked.isLocked = true
        let doc = document([a, locked])
        let result = controller().handle(.key(.delete, []), document: doc, selection: [a.id, b.id])
        #expect(applied(result, to: doc).annotations == [locked])
    }

    @Test func arrowKeysNudgeOnePixelAndTenWithShift() {
        let tool = controller()
        let doc = document([a])
        #expect(tool.handle(.key(.left, []), document: doc, selection: [a.id]).nudge == CGSize(width: -1, height: 0))
        #expect(tool.handle(.key(.down, .shift), document: doc, selection: [a.id]).nudge == CGSize(width: 0, height: 10))
    }

    @Test func escapeCancelsTheGesture() {
        let tool = controller()
        let doc = document([a])
        _ = tool.handle(.down(CGPoint(x: 150, y: 125), [], clickCount: 1), document: doc, selection: [])
        #expect(tool.handle(.drag(CGPoint(x: 190, y: 125), []), document: doc, selection: [a.id]).preview != nil)
        let escape = tool.handle(.key(.escape, []), document: doc, selection: [a.id])
        #expect(escape.preview == nil)
        #expect(escape.selection == nil)
        #expect(!tool.isGestureActive)
        #expect(tool.handle(.up(CGPoint(x: 190, y: 125), []), document: doc, selection: [a.id]).command == nil)
    }

    @Test func escapeWhenIdleClearsTheSelection() {
        #expect(controller().handle(.key(.escape, []), document: document([a]), selection: [a.id]).selection == [])
    }

    @Test func toolShortcutsMapToTools() {
        #expect(EditorTool.forShortcut("r") == .shape)
        #expect(EditorTool.forShortcut("R") == .shape)
        #expect(EditorTool.forShortcut("v") == .select)
        #expect(EditorTool.forShortcut("z") == nil)
        #expect(Set(EditorTool.allCases.map(\.shortcut)).count == EditorTool.allCases.count)
    }
}
