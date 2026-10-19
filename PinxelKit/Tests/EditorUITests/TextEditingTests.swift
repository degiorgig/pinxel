import CoreGraphics
import DocumentModel
import Foundation
import PinxelTestSupport
import Testing
@testable import EditorUI

struct TextEditingTests {
    private let existing = Annotation(id: TestDocuments.id(1), kind: .text(TextData(
        rect: CGRect(x: 10, y: 10, width: 100, height: 30), text: RichText("Ciao"))))
    private var newRequest: TextEditRequest {
        TextEditRequest(annotation: Annotation(id: TestDocuments.id(9), kind: .text(TextData(
            rect: CGRect(x: 0, y: 0, width: 100, height: 30), text: RichText(runs: [])))), isNew: true)
    }

    @Test func emptyNewTextCreatesNothing() {
        #expect(TextEditing.commit(newRequest, text: RichText("  \n"), minimumHeight: 0, document: TestDocuments.document(annotations: [])) == nil)
    }

    @Test func newTextAddsOneAnnotationWithTheTypedTextAndHeight() {
        var document = TestDocuments.document(annotations: [])
        let command = TextEditing.commit(newRequest, text: RichText("Nuovo"), minimumHeight: 48, document: document)
        #expect(command?.name == "Aggiungi testo")
        command?.apply(to: &document)
        #expect(document.userAnnotations.count == 1)
        #expect(document.userAnnotations[0].richText?.plainText == "Nuovo")
        #expect(document.userAnnotations[0].textRect?.height == 48)
    }

    @Test func editingExistingTextIsOneUpdateOnTheCurrentVersion() {
        var current = existing
        current.style.fill = .white
        var document = TestDocuments.document(annotations: [current])
        let request = TextEditRequest(annotation: existing, isNew: false)
        let command = TextEditing.commit(request, text: RichText("Ciao mondo"), minimumHeight: 0, document: document)
        #expect(command?.name == "Modifica testo")
        command?.apply(to: &document)
        #expect(document.userAnnotations[0].richText?.plainText == "Ciao mondo")
        #expect(document.userAnnotations[0].style.fill == .white)
        command?.revert(on: &document)
        #expect(document.userAnnotations == [current])
    }

    @Test func clearingExistingTextDeletesIt() {
        var document = TestDocuments.document(annotations: [existing])
        let command = TextEditing.commit(TextEditRequest(annotation: existing, isNew: false), text: RichText(runs: []), minimumHeight: 0, document: document)
        command?.apply(to: &document)
        #expect(document.userAnnotations.isEmpty)
    }

    @Test func unchangedLockedOrMissingTextIsNoCommand() {
        let document = TestDocuments.document(annotations: [existing])
        let request = TextEditRequest(annotation: existing, isNew: false)
        #expect(TextEditing.commit(request, text: RichText("Ciao"), minimumHeight: 0, document: document) == nil)
        var locked = existing
        locked.isLocked = true
        #expect(TextEditing.commit(request, text: RichText("x"), minimumHeight: 0, document: TestDocuments.document(annotations: [locked])) == nil)
        #expect(TextEditing.commit(request, text: RichText("x"), minimumHeight: 0, document: TestDocuments.document(annotations: [])) == nil)
    }

    @Test func placeholderBlanksTheTextAndKeepsTheLiveStyle() {
        var current = existing
        current.style.fill = .accentRed
        let placeholder = TextEditing.placeholder(for: TextEditRequest(annotation: existing, isNew: false), current: current, height: 50)
        #expect(placeholder.richText?.runs.isEmpty == true)
        #expect(placeholder.style.fill == .accentRed)
        #expect(placeholder.textRect?.height == 50)
        let fresh = TextEditing.placeholder(for: newRequest, current: nil, height: 10)
        #expect(fresh.id == TestDocuments.id(9) && fresh.textRect?.height == 30)
    }
}
