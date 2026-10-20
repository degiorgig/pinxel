import DocumentModel
import Foundation

/// End of a text edit on the canvas: a single command for the whole session (spec §6.3).
public enum TextEditing {
    /// Annotation to draw under the `NSTextView`: without text (the view shows it), with the current
    /// document style and the height reached by the typed text.
    public static func placeholder(for request: TextEditRequest, current: Annotation?, height: Double) -> Annotation {
        var annotation = request.isNew ? request.annotation : (current ?? request.annotation)
        if var text = annotation.richText {
            text.runs = []
            annotation.richText = text
        }
        annotation.growTextHeight(to: height)
        return annotation
    }

    /// New non-empty text → addition; existing text emptied → deletion; modified → update
    /// of the current version in the document. `nil` if nothing changes or the object is locked or gone.
    public static func commit(_ request: TextEditRequest, text: RichText, minimumHeight: Double,
                              document: PinxelDocument) -> (any EditCommand)? {
        let isEmpty = text.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if request.isNew {
            guard !isEmpty else { return nil }
            var annotation = request.annotation
            annotation.richText = text
            annotation.growTextHeight(to: minimumHeight)
            if case .callout = annotation.kind { return AddAnnotations([annotation], name: CommandName.addCallout) }
            return AddAnnotations([annotation], name: CommandName.addText)
        }
        guard let current = document.annotations.first(where: { $0.id == request.annotation.id }), !current.isLocked else {
            return nil
        }
        if isEmpty { return DeleteAnnotations(ids: [current.id], in: document, name: CommandName.deleteText) }
        var updated = current
        updated.richText = text
        updated.growTextHeight(to: minimumHeight)
        guard updated != current else { return nil }
        return UpdateAnnotations(name: CommandName.editText, before: [current], after: [updated])
    }
}

/// What the properties panel can ask of the text being edited.
@MainActor
public protocol TextEditingControl: AnyObject {
    /// Applies a change to all the text (size, color, alignment, bold…).
    func applyToAll(_ change: (inout RichText) -> Void)
    /// Confirms the text and ends the edit.
    func finish()
    /// Style change for the new object being written (no effect on an object already in the document).
    func applyToNewAnnotation(_ change: (inout Annotation) -> Void)
}
