import CoreGraphics
import DocumentModel
import Foundation
import PinxelTestSupport
import Testing
@testable import EditorUI

struct MagnifierToolTests {
    private let magnifier = Annotation(id: TestDocuments.id(1), kind: .magnifier(MagnifierData(
        source: CGRect(x: 50, y: 50, width: 20, height: 20), target: CGRect(x: 200, y: 40, width: 60, height: 60))),
        style: Style(stroke: .black, lineWidth: 2))

    private func controller(_ tool: EditorTool) -> ToolController {
        let controller = ToolController()
        controller.tool = tool
        controller.dragThreshold = 3
        controller.hitTolerance = 4
        controller.makeID = { TestDocuments.id(101) }
        return controller
    }

    private func drag(_ controller: ToolController, from start: CGPoint, to end: CGPoint, modifiers: ToolModifiers = [],
                      document: PinxelDocument, selection: Set<UUID> = []) -> PinxelDocument {
        var doc = document
        _ = controller.handle(.down(start, modifiers, clickCount: 1), document: doc, selection: selection)
        _ = controller.handle(.drag(CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), modifiers), document: doc, selection: selection)
        let result = controller.handle(.up(end, modifiers), document: doc, selection: selection)
        result.command?.apply(to: &doc)
        return doc
    }

    private func data(_ annotation: Annotation?) -> MagnifierData? {
        guard case .magnifier(let data) = annotation?.kind else { return nil }
        return data
    }

    @Test func placementPutsTheTargetRightOfTheSourceScaled() {
        let target = MagnifierPlacement.target(for: CGRect(x: 50, y: 100, width: 40, height: 20), zoom: 2, imageSize: CGSize(width: 400, height: 300))
        #expect(target == CGRect(x: 114, y: 90, width: 80, height: 40))
    }

    @Test func placementFlipsLeftNearTheRightEdgeAndStaysInside() {
        let target = MagnifierPlacement.target(for: CGRect(x: 330, y: 280, width: 40, height: 20), zoom: 2, imageSize: CGSize(width: 400, height: 300))
        #expect(target == CGRect(x: 226, y: 260, width: 80, height: 40))
    }

    @Test func dragCreatesAMagnifierWithAPlacedTarget() throws {
        let tool = controller(.magnifier)
        tool.styles.magnifierZoom = 3
        let document = drag(tool, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 40, y: 40), document: TestDocuments.document(annotations: []))
        let created = try #require(data(document.annotations.last))
        #expect(created.source == CGRect(x: 20, y: 20, width: 20, height: 20))
        #expect(created.target.size == CGSize(width: 60, height: 60))
        #expect(created.shape == tool.styles.magnifierShape && created.showsConnector)
    }

    @Test func draggingTheTargetMovesOnlyTheTarget() throws {
        let document = drag(controller(.select), from: CGPoint(x: 230, y: 70), to: CGPoint(x: 250, y: 80),
                            document: TestDocuments.document(annotations: [magnifier]), selection: [magnifier.id])
        let moved = try #require(data(document.annotations.first))
        #expect(moved.target == CGRect(x: 220, y: 50, width: 60, height: 60))
        #expect(moved.source == CGRect(x: 50, y: 50, width: 20, height: 20))
    }

    @Test func draggingTheSourceMovesOnlyTheSource() throws {
        let document = drag(controller(.select), from: CGPoint(x: 60, y: 60), to: CGPoint(x: 90, y: 60),
                            document: TestDocuments.document(annotations: [magnifier]), selection: [magnifier.id])
        let moved = try #require(data(document.annotations.first))
        #expect(moved.source == CGRect(x: 80, y: 50, width: 20, height: 20))
        #expect(moved.target == CGRect(x: 200, y: 40, width: 60, height: 60))
    }

    @Test func optionDragDuplicatesTheWholeMagnifier() throws {
        let document = drag(controller(.select), from: CGPoint(x: 230, y: 70), to: CGPoint(x: 240, y: 70), modifiers: .option,
                            document: TestDocuments.document(annotations: [magnifier]), selection: [magnifier.id])
        #expect(document.annotations.count == 2)
        let copy = try #require(data(document.annotations.last))
        #expect(copy.source.minX == 60 && copy.target.minX == 210)
    }

    @Test func targetAndSourceHandlesResizeTheirOwnRectangle() throws {
        let handles = HitTesting.handles(for: magnifier, rotationOffset: 30)
        #expect(handles.count == 12)
        #expect(!handles.contains { $0.handle == .rotation })
        let byTarget = drag(controller(.select), from: CGPoint(x: 260, y: 100), to: CGPoint(x: 280, y: 120),
                            document: TestDocuments.document(annotations: [magnifier]), selection: [magnifier.id])
        #expect(try #require(data(byTarget.annotations.first)).target == CGRect(x: 200, y: 40, width: 80, height: 80))
        let bySource = drag(controller(.select), from: CGPoint(x: 70, y: 70), to: CGPoint(x: 80, y: 90),
                            document: TestDocuments.document(annotations: [magnifier]), selection: [magnifier.id])
        let source = try #require(data(bySource.annotations.first))
        #expect(source.source == CGRect(x: 50, y: 50, width: 30, height: 40))
        #expect(source.target == CGRect(x: 200, y: 40, width: 60, height: 60))
    }

    @Test func zoomAccessorKeepsTheTargetCenter() throws {
        var annotation = magnifier
        #expect(annotation.magnifierZoom == 3)
        annotation.magnifierZoom = 2
        #expect(try #require(data(annotation)).target == CGRect(x: 210, y: 50, width: 40, height: 40))
        annotation.magnifierShape = .rectangle
        annotation.magnifierConnector = false
        #expect(try #require(data(annotation)).shape == .rectangle)
        #expect(annotation.magnifierConnector == false)
    }
}
