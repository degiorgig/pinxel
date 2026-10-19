import AppKit
import DocumentModel
import EditorUI
import SwiftUI

/// Strumento Ritaglio: istruzioni e pulsanti (le azioni arrivano alla tela tramite la catena dei responder).
struct CropSection: View {
    var body: some View {
        Section("Crop") {
            Text("Drag over the image or move the handles. ⇧ keeps a square. Return crops, Esc cancels.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { NSApp.sendAction(#selector(EditorActions.cancelCrop(_:)), to: nil, from: nil) }
                Spacer()
                Button("Crop") { NSApp.sendAction(#selector(EditorActions.commitCrop(_:)), to: nil, from: nil) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}


/// Strumento Taglia e ricuci: bordo della cucitura e istruzioni.
struct CutSection: View {
    @Bindable var model: EditorModel

    var body: some View {
        Section("Cut Out") {
            Picker("Edge", selection: $model.toolStyles.cutEdge) {
                Text("Straight").tag(CutEdge.straight)
                Text("Zigzag").tag(CutEdge.zigzag)
            }
            .pickerStyle(.segmented)
            Text("Drag vertically to remove a horizontal band, horizontally to remove a vertical band.")
                .foregroundStyle(.secondary)
        }
    }
}
