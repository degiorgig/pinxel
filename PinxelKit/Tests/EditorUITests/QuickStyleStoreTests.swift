import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

@MainActor
struct QuickStyleStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "PinxelQuickStyleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func style(_ width: Double) -> Style { Style(stroke: .accentRed, lineWidth: width) }

    @Test func recordsTheMostRecentFirstWithoutDuplicates() {
        let store = QuickStyleStore(defaults: freshDefaults())
        store.record(style(1), for: .arrow)
        store.record(style(2), for: .arrow)
        store.record(style(1), for: .arrow)
        #expect(store.styles(for: .arrow) == [style(1), style(2)])
        #expect(store.styles(for: .shape).isEmpty)
    }

    @Test func keepsAtMostEightPerTool() {
        let store = QuickStyleStore(defaults: freshDefaults())
        for width in 1...10 { store.record(style(Double(width)), for: .pen) }
        #expect(store.styles(for: .pen).count == QuickStyleStore.limit)
        #expect(store.styles(for: .pen).first == style(10))
    }

    @Test func persistsAndSurvivesCorruptData() {
        let defaults = freshDefaults()
        QuickStyleStore(defaults: defaults).record(style(5), for: .shape)
        #expect(QuickStyleStore(defaults: defaults).styles(for: .shape) == [style(5)])
        defaults.set(Data("{rotto".utf8), forKey: "PinxelQuickStyles")
        #expect(QuickStyleStore(defaults: defaults).styles(for: .shape).isEmpty)
    }

    private let arrow = Annotation(id: TestDocuments.id(1), kind: .arrow(ArrowData(line: LineGeometry(start: .zero, end: CGPoint(x: 50, y: 0)))))
    private let shape = Annotation(id: TestDocuments.id(2), kind: .shape(ShapeData(rect: CGRect(x: 0, y: 0, width: 50, height: 50), shape: .rectangle)))

    private func makeModel(_ annotations: [Annotation], store: QuickStyleStore) -> EditorModel {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: annotations, size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), undoManager: undo)
        return EditorModel(session: session, quickStyles: store)
    }

    @Test func applyingAQuickStyleChangesOnlyObjectsOfTheSameTool() {
        let model = makeModel([arrow, shape], store: QuickStyleStore(defaults: freshDefaults()))
        model.session.selection = [arrow.id, shape.id]
        #expect(model.quickStyleTool == .arrow)
        model.applyQuickStyle(style(9))
        #expect(model.session.document.annotations[0].style == style(9))
        #expect(model.session.document.annotations[1].style == shape.style)
    }

    @Test func withoutSelectionTheQuickStyleGoesToTheTool() {
        let model = makeModel([], store: QuickStyleStore(defaults: freshDefaults()))
        model.tool = .pen
        model.applyQuickStyle(style(7))
        #expect(model.toolStyles.style(for: .pen) == style(7))
        model.tool = .crop
        #expect(model.quickStyleTool == nil)
    }

    @Test func objectsCreatedWithAToolAreRecorded() {
        let store = QuickStyleStore(defaults: freshDefaults())
        let canvas = CanvasView(model: makeModel([], store: store))
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.model.tool = .shape
        canvas.send(.down(CGPoint(x: 10, y: 10), [], clickCount: 1))
        canvas.send(.drag(CGPoint(x: 60, y: 60), []))
        canvas.send(.up(CGPoint(x: 60, y: 60), []))
        #expect(store.styles(for: .shape) == [canvas.model.toolStyles.style(for: .shape)])
    }
}
