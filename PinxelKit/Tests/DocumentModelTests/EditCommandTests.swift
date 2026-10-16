import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct EditCommandTests {
    let base = TestDocuments.document()

    func expectReversible(_ command: any EditCommand, on document: PinxelDocument, sourceLocation: SourceLocation = #_sourceLocation) {
        var working = document
        command.apply(to: &working)
        let applied = working
        #expect(applied != document, "command \(command.name) changed nothing", sourceLocation: sourceLocation)
        command.revert(on: &working)
        #expect(working == document, "revert of \(command.name) is not exact", sourceLocation: sourceLocation)
        command.apply(to: &working)
        #expect(working == applied, "redo of \(command.name) differs", sourceLocation: sourceLocation)
    }

    func newShape() -> Annotation {
        Annotation(kind: .shape(ShapeData(rect: CGRect(x: 1, y: 2, width: 3, height: 4), shape: .rectangle)))
    }

    @Test func replaceBackgroundSwapsImageSizeAndOperations() {
        var document = base
        ApplyImageOperation(.crop(PixelRect(x: 0, y: 0, width: 50, height: 40)), in: document).apply(to: &document)
        let pasted = ImageAssetRef(name: "assets/pasted.png")
        let command = ReplaceBackground(pasted, size: PixelSize(width: 120, height: 90), in: document)
        expectReversible(command, on: document)
        var replaced = document
        command.apply(to: &replaced)
        #expect(replaced.background == pasted)
        #expect(replaced.imageSize == PixelSize(width: 120, height: 90))
        #expect(replaced.imageOperations.isEmpty)
        #expect(replaced.annotations == document.annotations)
    }

    @Test func addAppendsOrInserts() {
        let shape = newShape()
        var document = base
        AddAnnotations([shape]).apply(to: &document)
        #expect(document.annotations.last == shape)
        var inserted = base
        AddAnnotations([shape], at: 0).apply(to: &inserted)
        #expect(inserted.annotations.first == shape)
        expectReversible(AddAnnotations([shape]), on: base)
        expectReversible(AddAnnotations([shape], at: 3), on: base)
    }

    @Test func deleteRestoresOriginalPositions() {
        let ids: Set<UUID> = [TestDocuments.id(2), TestDocuments.id(5), TestDocuments.id(14)]
        let command = DeleteAnnotations(ids: ids, in: base)
        var document = base
        command.apply(to: &document)
        #expect(document.annotations.count == base.annotations.count - 3)
        expectReversible(command, on: base)
    }

    @Test func updateReplacesByID() {
        let before = base.annotations[2]
        var after = before
        after.style.lineWidth = 9
        after.rotation = 0.3
        let command = UpdateAnnotations(before: [before], after: [after])
        var document = base
        command.apply(to: &document)
        #expect(document.annotations[2] == after)
        expectReversible(command, on: base)
    }

    @Test func consecutiveUpdatesMerge() {
        let original = base.annotations[0]
        var step1 = original
        step1.rotation = 0.1
        var step2 = step1
        step2.rotation = 0.2
        let first = UpdateAnnotations(name: "Sposta", before: [original], after: [step1])
        let second = UpdateAnnotations(name: "Sposta", before: [step1], after: [step2])
        let merged = first.merged(with: second)
        #expect(merged?.before == [original])
        #expect(merged?.after == [step2])

        let unrelated = UpdateAnnotations(before: [base.annotations[1]], after: [base.annotations[1]])
        #expect(first.merged(with: unrelated) == nil)
    }

    @Test func reorderHelpers() {
        let order = base.annotations.map(\.id)
        let selected: Set<UUID> = [order[0], order[1]]

        var front = base
        ReorderAnnotations.bringToFront(selected, in: base).apply(to: &front)
        #expect(Array(front.annotations.map(\.id).suffix(2)) == [order[0], order[1]])

        var back = base
        ReorderAnnotations.sendToBack([order[5]], in: base).apply(to: &back)
        #expect(back.annotations.first?.id == order[5])

        var forward = base
        ReorderAnnotations.bringForward(selected, in: base).apply(to: &forward)
        #expect(Array(forward.annotations.map(\.id).prefix(3)) == [order[2], order[0], order[1]])

        var backward = base
        ReorderAnnotations.sendBackward([order[3]], in: base).apply(to: &backward)
        #expect(Array(backward.annotations.map(\.id).prefix(4)) == [order[0], order[1], order[3], order[2]])

        expectReversible(ReorderAnnotations.bringToFront(selected, in: base), on: base)
    }

    @Test func imageOperationTransformsAnnotations() {
        let command = ApplyImageOperation(.crop(PixelRect(x: 10, y: 20, width: 300, height: 200)), in: base)
        var document = base
        command.apply(to: &document)
        #expect(document.imageOperations.count == 1)
        #expect(document.imageSize == PixelSize(width: 300, height: 200))
        #expect(document.annotations[0].bounds.minX == base.annotations[0].bounds.minX - 10)
        #expect(command.name == "Ritaglia")
        expectReversible(command, on: base)
    }

    @Test func cropKeepsAnnotationsOutsideAndRevertsExactly() {
        // Ritaglio sulla metà destra: molte annotazioni finiscono a coordinate negative.
        let command = ApplyImageOperation(.crop(PixelRect(x: 200, y: 150, width: 200, height: 150)), in: base)
        var document = base
        command.apply(to: &document)
        #expect(document.annotations.count == base.annotations.count)
        #expect(document.annotations.contains { $0.bounds.maxX < 0 || $0.bounds.maxY < 0 })
        command.revert(on: &document)
        #expect(document == base)
    }

    @Test func canvasStyleAndGroup() {
        let style = UpdateCanvasStyle(before: base.canvasStyle, after: CanvasStyle(padding: 20, backgroundColor: .white))
        expectReversible(style, on: base)

        let shape = newShape()
        let group = CommandGroup(name: "Incolla", commands: [
            AddAnnotations([shape]),
            ReorderAnnotations(newOrder: [shape.id] + base.annotations.map(\.id), in: base),
        ])
        var document = base
        group.apply(to: &document)
        #expect(document.annotations.first == shape)
        // Il secondo comando è stato creato sul documento senza `shape`: il gruppo deve comunque tornare esattamente a `base`.
        group.revert(on: &document)
        #expect(document == base)
    }
}
