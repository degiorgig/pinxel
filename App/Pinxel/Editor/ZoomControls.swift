import EditorUI
import SwiftUI

/// Comandi sopra la tela, separati dagli strumenti: riduci, percentuale (clic adatta, doppio clic 100%), ingrandisci
/// e la manina per spostare la vista trascinando.
struct ZoomControls: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 2) {
            Button { model.canvas?.zoomOut(nil) } label: {
                Image(systemName: "minus.magnifyingglass").frame(width: 24, height: 24)
            }
            .help("Riduci (⌘−)")
            .accessibilityIdentifier("pinxel.editor.zoomOut")

            Text("\(Int((model.zoom * 100).rounded()))%")
                .font(.callout)
                .monospacedDigit()
                .frame(minWidth: 44)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.canvas?.zoomToActualSize(nil) }
                .onTapGesture { model.canvas?.zoomToFit(nil) }
                .help("Clic: adatta alla finestra. Doppio clic: dimensioni reali")
                .accessibilityElement()
                .accessibilityLabel("Zoom")
                .accessibilityValue("\(Int((model.zoom * 100).rounded())) percento")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.canvas?.zoomToFit(nil) }
                .accessibilityIdentifier("pinxel.editor.zoomLevel")

            Button { model.canvas?.zoomIn(nil) } label: {
                Image(systemName: "plus.magnifyingglass").frame(width: 24, height: 24)
            }
            .help("Ingrandisci (⌘+)")
            .accessibilityIdentifier("pinxel.editor.zoomIn")

            Divider().frame(height: 18).padding(.horizontal, 4)

            Toggle(isOn: $model.isPanning) {
                Image(systemName: model.isPanning ? "hand.raised.fill" : "hand.raised").frame(width: 24, height: 24)
            }
            .toggleStyle(.button)
            .help("Sposta la vista trascinando (o tieni premuta la barra spaziatrice). Esc per uscire")
            .accessibilityLabel("Sposta la vista")
            .accessibilityIdentifier("pinxel.editor.pan")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}
