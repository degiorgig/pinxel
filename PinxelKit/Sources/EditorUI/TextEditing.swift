import DocumentModel
import Foundation

/// Fine di una modifica di testo sulla tela: un solo comando per tutta la sessione (spec §6.3).
public enum TextEditing {
    /// Annotazione da disegnare sotto l'`NSTextView`: senza testo (lo mostra la vista), con lo stile
    /// attuale del documento e l'altezza raggiunta dal testo digitato.
    public static func placeholder(for request: TextEditRequest, current: Annotation?, height: Double) -> Annotation {
        var annotation = request.isNew ? request.annotation : (current ?? request.annotation)
        if var text = annotation.richText {
            text.runs = []
            annotation.richText = text
        }
        annotation.growTextHeight(to: height)
        return annotation
    }

    /// Nuovo testo non vuoto → aggiunta; testo esistente svuotato → eliminazione; modificato → aggiornamento
    /// della versione attuale nel documento. `nil` se non cambia nulla o l'oggetto è bloccato o sparito.
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

/// Ciò che il pannello proprietà può chiedere al testo in modifica.
@MainActor
public protocol TextEditingControl: AnyObject {
    /// Applica una modifica a tutto il testo (dimensione, colore, allineamento, grassetto…).
    func applyToAll(_ change: (inout RichText) -> Void)
    /// Conferma il testo e chiude la modifica.
    func finish()
    /// Modifica di stile per l'oggetto nuovo in scrittura (nessun effetto su un oggetto già nel documento).
    func applyToNewAnnotation(_ change: (inout Annotation) -> Void)
}
