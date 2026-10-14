import EditorUI
import SwiftUI

/// Contenuto della finestra: tela al centro, strumenti nella toolbar nativa, proprietà a destra.
struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        CanvasRepresentable(model: model)
            .frame(minWidth: 320, minHeight: 240)
            .inspector(isPresented: $model.isInspectorPresented) {
                InspectorView(model: model)
                    .inspectorColumnWidth(min: 240, ideal: 260, max: 340)
            }
            .sheet(item: $model.presentedSheet) { sheet in
                switch sheet {
                case .resizeImage: ResizeImageSheet(model: model)
                case .canvasStyle: CanvasStyleSheet(model: model)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Strumento", selection: $model.tool) {
                        ForEach(EditorTool.allCases, id: \.self) { tool in
                            Label(tool.title, systemImage: tool.symbolName)
                                .help("\(tool.title) (\(String(tool.shortcut).uppercased()))")
                                .tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .primaryAction) {
                    Image(systemName: "photo.on.rectangle")
                        .frame(width: 28, height: 22)
                        .contentShape(Rectangle())
                        .draggable(DraggedCapture(model: model))
                        .help("Trascina l'immagine in un'altra app o nel Finder")
                        .accessibilityLabel("Trascina l'immagine")
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: SharedCapture(model: model), preview: SharePreview("Cattura Pinxel"))
                        .help("Condividi l'immagine")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.isInspectorPresented.toggle()
                    } label: {
                        Label("Proprietà", systemImage: "sidebar.trailing")
                    }
                    .help("Mostra o nascondi il pannello proprietà")
                }
            }
    }
}

struct CanvasRepresentable: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> CanvasView {
        CanvasView(model: model)
    }

    func updateNSView(_ nsView: CanvasView, context: Context) {}
}
