import Combine
import EditorUI
import Observation

/// L'editor della finestra principale e lo stato dei suoi menu. I comandi SwiftUI osservano questo oggetto;
/// lo stato si ricalcola quando cambiano documento, selezione o testo in modifica dell'editor.
@MainActor
final class EditorFocus: ObservableObject {
    static let shared = EditorFocus()

    @Published private(set) var state = EditorMenuState()
    private(set) weak var model: EditorModel?
    /// `false` quando un foglio della finestra (Salva, Esporta, Ridimensiona) ha la tastiera.
    private var editorIsKey = true

    func focus(_ model: EditorModel, isKey: Bool) {
        self.model = model
        editorIsKey = isKey
        refresh()
    }

    func keyChanged(_ model: EditorModel, isKey: Bool) {
        guard self.model === model, editorIsKey != isKey else { return }
        editorIsKey = isKey
        refresh()
    }

    func resign(_ model: EditorModel) {
        guard self.model === model else { return }
        self.model = nil
        refresh()
    }

    private func refresh() {
        guard let model else {
            state = EditorMenuState()
            return
        }
        let next = withObservationTracking {
            EditorMenuState(model: model)
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        var adjusted = next
        adjusted.editorIsKey = editorIsKey
        if adjusted != state { state = adjusted }
    }
}
