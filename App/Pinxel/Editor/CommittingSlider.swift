import SwiftUI

/// Slider that shows only a preview while dragging and records a single command at the end
/// (spec §5.4). Keyboard changes, without dragging, are recorded immediately.
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
