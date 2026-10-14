import SwiftUI

/// Cursore che durante il trascinamento mostra solo un'anteprima e alla fine registra un solo comando
/// (spec §5.4). Le modifiche da tastiera, senza trascinamento, si registrano subito.
struct CommittingSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let preview: @MainActor (Double) -> Void
    let commit: @MainActor (Double) -> Void

    @State private var draft: Double?
    @State private var isEditing = false

    var body: some View {
        Slider(
            value: Binding(
                get: { draft ?? value },
                set: { newValue in
                    if isEditing {
                        draft = newValue
                        preview(newValue)
                    } else {
                        commit(newValue)
                    }
                }
            ),
            in: range
        ) { editing in
            isEditing = editing
            if !editing, let final = draft {
                draft = nil
                commit(final)
            }
        }
    }
}
