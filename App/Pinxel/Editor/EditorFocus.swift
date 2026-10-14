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

    func focus(_ model: EditorModel) {
        self.model = model
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
        if next != state { state = next }
    }
}
