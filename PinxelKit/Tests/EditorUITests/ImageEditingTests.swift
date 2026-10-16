import AppKit
import DocumentModel
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

struct ImageEditingTests {
    private let original = PixelSize(width: 400, height: 300)

    @Test func resizeDraftKeepsTheAspectRatioWhenAsked() {
        var draft = ResizeDraft(original: original)
        draft.setWidth(200)
        #expect(draft.width == 200 && draft.height == 150)
        draft.keepsAspect = false
        draft.setHeight(100)
        #expect(draft.width == 200 && draft.height == 100)
    }

    @Test func resizeDraftClampsAndRounds() {
        var draft = ResizeDraft(original: original)
        draft.setWidth(0)
        #expect(draft.width == 1 && draft.height == 1)
        draft.setWidth(100_000)
        #expect(draft.width == PinxelDocument.maxImageSide && draft.height == PinxelDocument.maxImageSide * 3 / 4)
        draft.setPercent(50)
        #expect(draft.width == 200 && draft.height == 150 && draft.percent == 50)
        draft.setPercent(33)
        #expect(draft.width == 132 && draft.height == 99)
    }

    @Test func resizeDraftProducesAnUndoableOperation() throws {
        var draft = ResizeDraft(original: original)
        #expect(draft.operation == nil)
        draft.setPercent(50)
        let operation = try #require(draft.operation)
        #expect(operation == .resize(PixelSize(width: 200, height: 150)))
        let shape = Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: CGRect(x: 100, y: 100, width: 50, height: 50), shape: .rectangle)))
        let before = TestDocuments.document(annotations: [shape])
        var document = before
        let command = ApplyImageOperation(operation, in: document)
        command.apply(to: &document)
        #expect(document.imageSize == PixelSize(width: 200, height: 150))
        #expect(document.annotations[0].bounds == CGRect(x: 50, y: 50, width: 25, height: 25))
        command.revert(on: &document)
        #expect(document == before)
    }

    @Test func shadowGetsEnoughPaddingToShow() {
        let needed = CanvasStyleEditing.paddingNeeded(for: CanvasStyleEditing.defaultShadow)
        #expect(needed == 44)
        let on = CanvasStyleEditing.settingShadow(true, in: CanvasStyle())
        #expect(on.shadow == CanvasStyleEditing.defaultShadow && on.padding == 44)
        #expect(CanvasStyleEditing.settingShadow(true, in: CanvasStyle(padding: 100)).padding == 100)
        let off = CanvasStyleEditing.settingShadow(false, in: on)
        #expect(off.shadow == nil && off.padding == 44)
    }

    @Test func borderAndBackgroundTogglesUseDefaultsAndKeepCustomValues() {
        let on = CanvasStyleEditing.settingBorder(true, in: CanvasStyle())
        #expect(on.border == CanvasStyleEditing.defaultBorder)
        var custom = on
        custom.border?.width = 12
        #expect(CanvasStyleEditing.settingBorder(true, in: custom).border?.width == 12)
        #expect(CanvasStyleEditing.settingBorder(false, in: custom).border == nil)
        #expect(CanvasStyleEditing.settingBackground(true, in: CanvasStyle()).backgroundColor == .white)
    }

    @MainActor
    @Test func canvasStylePreviewChangesTheCanvasUntilCleared() {
        let session = EditorSession(document: TestDocuments.document(annotations: [], size: original, scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]))
        let canvas = CanvasView(model: EditorModel(session: session))
        #expect(canvas.canvasSize == CGSize(width: 400, height: 300))
        session.canvasStylePreview = CanvasStyle(padding: 50)
        #expect(canvas.canvasSize == CGSize(width: 500, height: 400))
        session.replaceDocument(session.document)
        #expect(session.canvasStylePreview == nil)
        #expect(canvas.canvasSize == CGSize(width: 400, height: 300))
    }
}
