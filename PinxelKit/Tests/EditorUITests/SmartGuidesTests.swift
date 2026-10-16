import CoreGraphics
import DocumentModel
import Foundation
import PinxelTestSupport
import Testing
@testable import EditorUI

struct SmartGuidesTests {
    private let moving = CGRect(x: 100, y: 100, width: 50, height: 50)

    @Test func snapsAnEdgeWithinTheTolerance() {
        let snap = SmartGuides.snap(moving, to: [CGRect(x: 153, y: 300, width: 40, height: 40)], tolerance: 6)
        #expect(snap.offset == CGSize(width: 3, height: 0))
        #expect(snap.guides == [GuideLine(orientation: .vertical, position: 153, from: 100, to: 340)])
    }

    @Test func ignoresLinesBeyondTheTolerance() {
        let snap = SmartGuides.snap(moving, to: [CGRect(x: 160, y: 300, width: 40, height: 40)], tolerance: 6)
        #expect(snap.offset == .zero && snap.guides.isEmpty)
    }

    @Test func alignsCentersAndPicksTheClosestLine() {
        let snap = SmartGuides.snap(moving, to: [CGRect(x: 108, y: 300, width: 30, height: 30), CGRect(x: 0, y: 147, width: 20, height: 20)], tolerance: 6)
        // Centro 125 contro centro 123 (−2) batte il bordo sinistro 100 contro 108 (+8, fuori tolleranza).
        #expect(snap.offset.width == -2)
        // Bordo inferiore 150 contro bordo superiore 147 (−3) e centro 125 contro 157 (fuori).
        #expect(snap.offset.height == -3)
        #expect(snap.guides.contains { $0.orientation == .vertical && $0.position == 123 })
        #expect(snap.guides.contains { $0.orientation == .horizontal && $0.position == 147 })
    }

    private let left = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 100, y: 100, width: 50, height: 50), shape: .rectangle)),
                                  style: Style(stroke: nil, fill: .black, lineWidth: 0))
    private let right = Annotation(id: TestDocuments.id(2), kind: .shape(ShapeData(rect: CGRect(x: 200, y: 100, width: 50, height: 50), shape: .rectangle)),
                                   style: Style(stroke: nil, fill: .black, lineWidth: 0))

    private func move(by delta: CGSize, modifiers: ToolModifiers = []) -> (drag: ToolResult, document: PinxelDocument) {
        let controller = ToolController()
        controller.dragThreshold = 3
        var document = TestDocuments.document(annotations: [left, right])
        let start = CGPoint(x: 125, y: 125)
        let end = CGPoint(x: start.x + delta.width, y: start.y + delta.height)
        // ⇧ al clic toglierebbe l'oggetto dalla selezione: i modificatori contano durante il trascinamento.
        _ = controller.handle(.down(start, modifiers.subtracting(.shift), clickCount: 1), document: document, selection: [left.id])
        let drag = controller.handle(.drag(end, modifiers), document: document, selection: [left.id])
        let up = controller.handle(.up(end, modifiers), document: document, selection: [left.id])
        up.command?.apply(to: &document)
        return (drag, document)
    }

    @Test func movingSnapsToAnotherObjectAndShowsGuides() {
        let result = move(by: CGSize(width: 47, height: 0))
        #expect(!result.drag.guides.isEmpty)
        #expect(result.document.annotations[0].bounds == CGRect(x: 150, y: 100, width: 50, height: 50))
    }

    @Test func commandTurnsSnappingOff() {
        let result = move(by: CGSize(width: 47, height: 0), modifiers: .command)
        #expect(result.drag.guides.isEmpty)
        #expect(result.document.annotations[0].bounds.minX == 147)
    }

    @Test func shiftKeepsTheLockedAxisStill() {
        let result = move(by: CGSize(width: 47, height: 2), modifiers: .shift)
        #expect(result.document.annotations[0].bounds == CGRect(x: 150, y: 100, width: 50, height: 50))
    }
}
