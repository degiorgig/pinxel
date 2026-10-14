import AppKit
import DocumentModel
import EditorUI
import SwiftUI

/// Strumento Ritaglio: istruzioni e pulsanti (le azioni arrivano alla tela tramite la catena dei responder).
struct CropSection: View {
    var body: some View {
        Section("Ritaglio") {
            Text("Trascina sull'immagine o sposta le maniglie. ⇧ mantiene un quadrato. Invio ritaglia, Esc annulla.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Annulla") { NSApp.sendAction(#selector(EditorActions.cancelCrop(_:)), to: nil, from: nil) }
                Spacer()
                Button("Ritaglia") { NSApp.sendAction(#selector(EditorActions.commitCrop(_:)), to: nil, from: nil) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}


/// Strumento Taglia e ricuci: bordo della cucitura e istruzioni.
struct CutSection: View {
    @Bindable var model: EditorModel

    var body: some View {
        Section("Taglia e ricuci") {
            Picker("Bordo", selection: $model.toolStyles.cutEdge) {
                Text("Dritto").tag(CutEdge.straight)
                Text("Zig-zag").tag(CutEdge.zigzag)
            }
            .pickerStyle(.segmented)
            Text("Trascina in verticale per togliere una fascia orizzontale, in orizzontale per togliere una fascia verticale.")
                .foregroundStyle(.secondary)
        }
    }
}
