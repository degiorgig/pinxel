import AppKit
import DocumentModel
import Foundation
import PinxelTestSupport
import Rendering
import Testing
@testable import EditorUI

/// Defects found by the review following 27a0a80.
@MainActor
struct ReviewFollowUpTests {
    private let shape = Annotation(id: TestDocuments.id(2), kind: .shape(ShapeData(rect: CGRect(x: 20, y: 20, width: 40, height: 30), shape: .rectangle)))

    private static var windows: [NSWindow] = []

    private func makeCanvas(_ annotations: [Annotation] = [], pasteboard: NSPasteboard? = nil) -> CanvasView {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let session = EditorSession(document: TestDocuments.document(annotations: annotations, size: PixelSize(width: 400, height: 300), scale: 1),
                                    assets: DictionaryAssetProvider([TestDocuments.background: TestImages.quadrants()]), undoManager: undo)
        let canvas = CanvasView(model: EditorModel(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = canvas
        Self.windows.append(window)
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        canvas.pasteboard = pasteboard ?? NSPasteboard(name: NSPasteboard.Name("com.degiorgi.pinxel.tests.\(UUID().uuidString)"))
        return canvas
    }

    private func pngData(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    // 1. A pasted image cut together with a shape also arrives in another document.
    @Test func mixedSelectionKeepsItsImageAcrossDocuments() throws {
        let source = makeCanvas([shape])
        source.pasteboard.clearContents()
        source.pasteboard.setData(pngData(width: 40, height: 20), forType: .png)
        source.pasteKeepingCanvas(nil)
        source.model.session.selection = Set(source.model.session.document.userAnnotations.map(\.id))
        source.cut(nil)

        let target = makeCanvas(pasteboard: source.pasteboard)
        target.paste(nil)
        let pasted = target.model.session.document.userAnnotations
        #expect(pasted.count == 2)
        let image = try #require(pasted.compactMap { annotation -> PlacedImageData? in
            if case .image(let data) = annotation.kind { return data }
            return nil
        }.first)
        let stored = try #require(target.model.session.assets.image(for: image.asset))
        #expect(stored.width == 40 && stored.height == 20)
        // The file is saved with the new document.
        #expect(target.model.session.assets.addedData[image.asset] != nil)
    }

    // 2. With an object selected, the Crop tool shows its options (Crop, Cancel).
    @Test func cropToolTakesThePanelOverTheSelection() {
        let canvas = makeCanvas([shape])
        canvas.model.session.selection = [shape.id]
        canvas.model.tool = .crop
        #expect(canvas.model.inspectedKind == .crop)
        #expect(canvas.model.quickStyleTool == nil)
        canvas.model.tool = .cutOut
        #expect(canvas.model.inspectedKind == .cutOut)
        canvas.model.tool = .select
        #expect(canvas.model.inspectedKind == .shape)
    }

    // 3. A rotated text stays rotated while it is being written.
    @Test func rotatedTextIsEditedWithItsRotation() throws {
        let rect = CGRect(x: 100, y: 100, width: 160, height: 40)
        let text = Annotation(id: TestDocuments.id(1), kind: .text(TextData(rect: rect, text: RichText("Ciao"))),
                              style: Style(stroke: nil, lineWidth: 0), rotation: .pi / 2)
        let canvas = makeCanvas([text])
        canvas.beginTextEditing(TextEditRequest(annotation: text, isNew: false))
        let editor = try #require(canvas.textEditor)
        // The top-right corner of the box, rotated as the renderer draws it, at two zoom levels.
        let rotation = CGAffineTransform(translationX: rect.midX, y: rect.midY).rotated(by: .pi / 2).translatedBy(x: -rect.midX, y: -rect.midY)
        let expected = CGPoint(x: rect.maxX, y: rect.minY).applying(rotation)
        for zoom in [false, true] {
            if zoom { canvas.zoomIn(nil) }
            let corner = canvas.convert(CGPoint(x: editor.container.bounds.maxX, y: editor.container.bounds.minY), from: editor.container)
            let actual = canvas.documentPoint(fromView: corner)
            #expect(abs(actual.x - expected.x) < 0.5 && abs(actual.y - expected.y) < 0.5, "zoom \(zoom)")
        }
    }
}
