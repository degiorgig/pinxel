import CoreGraphics
import DocumentModel
import Foundation
import PinxelTestSupport
import Testing
@testable import EditorUI

struct CutToolTests {
    private let size = PixelSize(width: 400, height: 300)
    private let shape = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 100, y: 200, width: 50, height: 50), shape: .rectangle)))

    private func controller() -> ToolController {
        let controller = ToolController()
        controller.tool = .cutOut
        controller.styles.cutEdge = .zigzag
        return controller
    }

    @Test func verticalDragCutsAHorizontalBand() {
        #expect(CutGeometry.cut(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 30, y: 160), imageSize: size, edge: .straight)
                == CutOut(axis: .horizontal, start: 100, length: 60, edge: .straight))
    }

    @Test func horizontalDragCutsAVerticalBand() {
        #expect(CutGeometry.cut(from: CGPoint(x: 300, y: 50), to: CGPoint(x: 120.4, y: 70), imageSize: size, edge: .zigzag)
                == CutOut(axis: .vertical, start: 120, length: 180, edge: .zigzag))
    }

    @Test func tinyAndTotalCutsAreRefused() {
        #expect(CutGeometry.cut(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 10, y: 101), imageSize: size, edge: .straight) == nil)
        #expect(CutGeometry.cut(from: CGPoint(x: 10, y: -10), to: CGPoint(x: 10, y: 400), imageSize: size, edge: .straight) == nil)
    }

    @Test func toolPreviewsTheBandAndCommitsWithTheToolEdge() throws {
        let tool = controller()
        let document = TestDocuments.document(annotations: [])
        _ = tool.handle(.down(CGPoint(x: 50, y: 100), [], clickCount: 1), document: document, selection: [])
        _ = tool.handle(.drag(CGPoint(x: 55, y: 150), []), document: document, selection: [])
        #expect(tool.cutPreview == CutOut(axis: .horizontal, start: 100, length: 50, edge: .zigzag))
        let result = tool.handle(.up(CGPoint(x: 55, y: 150), []), document: document, selection: [])
        #expect(try #require(result.command).name == "Taglia e ricuci")
        #expect(tool.cutPreview == nil)
    }

    @Test func cutMovesAnnotationsAndUndoRestoresThem() throws {
        let tool = controller()
        let original = TestDocuments.document(annotations: [shape])
        _ = tool.handle(.down(CGPoint(x: 50, y: 100), [], clickCount: 1), document: original, selection: [])
        let result = tool.handle(.up(CGPoint(x: 50, y: 150), []), document: original, selection: [])
        var document = original
        try #require(result.command).apply(to: &document)
        #expect(document.imageSize == PixelSize(width: 400, height: 250))
        #expect(document.annotations[0].bounds.minY == 150)
        result.command?.revert(on: &document)
        #expect(document == original)
    }

    @Test func escapeCancelsTheCut() {
        let tool = controller()
        let document = TestDocuments.document(annotations: [])
        _ = tool.handle(.down(CGPoint(x: 50, y: 100), [], clickCount: 1), document: document, selection: [])
        _ = tool.handle(.drag(CGPoint(x: 50, y: 150), []), document: document, selection: [])
        _ = tool.handle(.key(.escape, []), document: document, selection: [])
        #expect(tool.cutPreview == nil)
        #expect(tool.handle(.up(CGPoint(x: 50, y: 150), []), document: document, selection: []).command == nil)
    }
}
