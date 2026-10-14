import CoreGraphics
import DocumentModel
import Foundation
import PinxelTestSupport
import Testing
@testable import EditorUI

struct TextToolTests {
    private let text = Annotation(id: TestDocuments.id(1), kind: .text(TextData(
        rect: CGRect(x: 100, y: 100, width: 160, height: 40), text: RichText("Ciao"))), style: Style(stroke: nil, lineWidth: 0))
    private let callout = Annotation(id: TestDocuments.id(2), kind: .callout(CalloutData(
        rect: CGRect(x: 200, y: 50, width: 100, height: 50), text: RichText("Qui"), tail: CalloutTail(tip: CGPoint(x: 150, y: 200)))))

    private func controller(_ tool: EditorTool) -> ToolController {
        let controller = ToolController()
        controller.tool = tool
        controller.dragThreshold = 3
        controller.makeID = { TestDocuments.id(101) }
        return controller
    }

    private func click(_ controller: ToolController, at point: CGPoint, count: Int = 1, document: PinxelDocument, selection: Set<UUID> = []) -> ToolResult {
        let down = controller.handle(.down(point, [], clickCount: count), document: document, selection: selection)
        let up = controller.handle(.up(point, []), document: document, selection: selection)
        return up.editText != nil || up.command != nil ? up : down
    }

    @Test func newToolsHaveShortcutsAndInspectedKinds() {
        #expect(EditorTool.forShortcut("t") == .text)
        #expect(EditorTool.forShortcut("C") == .callout)
        #expect(EditorTool.forShortcut("m") == .magnifier)
        #expect(EditorTool.forShortcut("k") == .crop)
        #expect(EditorTool.forShortcut("x") == .cutOut)
        #expect(InspectedKind(EditorTool.text).showsText && InspectedKind(EditorTool.callout).showsText)
        #expect(!InspectedKind(EditorTool.crop).showsStyleSection && !InspectedKind(EditorTool.cutOut).showsStyleSection)
        #expect(!EditorTool.crop.createsAnnotations && EditorTool.magnifier.createsAnnotations)
        #expect(EditorTool(kind: callout.kind) == .callout)
        #expect(EditorTool(kind: .pixelate(PixelateData(rect: .zero))) == .blur)
    }

    @Test func clickWithTheTextToolRequestsANewText() throws {
        let tool = controller(.text)
        tool.styles.text = RichText(runs: [], fontSize: 20, color: .accentRed)
        let result = click(tool, at: CGPoint(x: 50, y: 60), document: TestDocuments.document(annotations: []))
        let request = try #require(result.editText)
        #expect(request.isNew)
        #expect(result.command == nil)
        #expect(request.annotation.id == TestDocuments.id(101))
        #expect(request.annotation.textRect == ToolController.defaultTextFrame(at: CGPoint(x: 50, y: 60), template: tool.styles.text, callout: false))
        #expect(request.annotation.richText?.color == .accentRed)
        #expect(request.annotation.richText?.runs.isEmpty == true)
    }

    @Test func dragWithTheCalloutToolUsesTheFrameAndPutsTheTailBelow() throws {
        let tool = controller(.callout)
        let document = TestDocuments.document(annotations: [])
        _ = tool.handle(.down(CGPoint(x: 10, y: 10), [], clickCount: 1), document: document, selection: [])
        let drag = tool.handle(.drag(CGPoint(x: 110, y: 60), []), document: document, selection: [])
        #expect(drag.marquee == CGRect(x: 10, y: 10, width: 100, height: 50))
        let result = tool.handle(.up(CGPoint(x: 110, y: 60), []), document: document, selection: [])
        let annotation = try #require(result.editText?.annotation)
        guard case .callout(let data) = annotation.kind else { Issue.record("no callout"); return }
        #expect(data.rect == CGRect(x: 10, y: 10, width: 100, height: 50))
        #expect(data.tail.tip.y > data.rect.maxY)
        #expect(annotation.style == tool.styles.style(for: .callout))
    }

    @Test func textToolClickOnAnExistingTextEditsIt() throws {
        let result = click(controller(.text), at: CGPoint(x: 150, y: 120), document: TestDocuments.document(annotations: [text]))
        let request = try #require(result.editText)
        #expect(!request.isNew && request.annotation == text)
        #expect(result.selection == [text.id])
    }

    @Test func doubleClickWithTheSelectToolEditsTextButNotLockedText() {
        let select = controller(.select)
        let document = TestDocuments.document(annotations: [text])
        let edit = select.handle(.down(CGPoint(x: 150, y: 120), [], clickCount: 2), document: document, selection: [text.id])
        #expect(edit.editText?.annotation.id == text.id)
        var locked = text
        locked.isLocked = true
        let none = select.handle(.down(CGPoint(x: 150, y: 120), [], clickCount: 2), document: TestDocuments.document(annotations: [locked]), selection: [])
        #expect(none.editText == nil)
    }

    @Test func enterEditsTheSelectedText() {
        let result = controller(.select).handle(.key(.enter, []), document: TestDocuments.document(annotations: [text]), selection: [text.id])
        #expect(result.editText?.annotation.id == text.id)
    }

    @Test func calloutHandlesSitOnTheBubbleAndTheTail() {
        let handles = HitTesting.handles(for: callout, rotationOffset: 30)
        #expect(handles.count == 9)
        #expect(!handles.contains { $0.handle == .rotation })
        #expect(handles.first { $0.handle == .calloutTail }?.point == CGPoint(x: 150, y: 200))
        #expect(handles.first { $0.handle == .topLeft }?.point == CGPoint(x: 200, y: 50))
        #expect(HitTesting.selectionFrames(for: callout) == [CGRect(x: 200, y: 50, width: 100, height: 50)])
    }

    @Test func tailHandleMovesOnlyTheTipAndBoxHandlesOnlyTheBubble() {
        let moved = AnnotationGeometry.resized(callout, handle: .calloutTail, to: CGPoint(x: 400, y: 10), keepAspect: false)
        guard case .callout(let tail) = moved.kind else { Issue.record("no callout"); return }
        #expect(tail.tail.tip == CGPoint(x: 400, y: 10) && tail.rect == CGRect(x: 200, y: 50, width: 100, height: 50))
        let resized = AnnotationGeometry.resized(callout, handle: .bottomRight, to: CGPoint(x: 320, y: 130), keepAspect: false)
        guard case .callout(let box) = resized.kind else { Issue.record("no callout"); return }
        #expect(box.rect == CGRect(x: 200, y: 50, width: 120, height: 80) && box.tail.tip == CGPoint(x: 150, y: 200))
    }

    @Test func clickingCalloutNearTheTailSelectsIt() {
        #expect(HitTesting.contains(callout, point: CGPoint(x: 160, y: 185), tolerance: 4))
        #expect(!HitTesting.contains(callout, point: CGPoint(x: 120, y: 60), tolerance: 4))
    }
}
