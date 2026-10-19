import EditorUI
import Library
import SwiftUI

/// Contenuto della finestra: tela al centro, strumenti nella toolbar nativa, proprietà a destra.
struct EditorView: View {
    @Bindable var model: EditorModel
    let stripState: LibraryStripState
    /// File della finestra, letto a ogni disegno: un documento senza titolo può diventare un file.
    let currentURL: () -> URL?
    /// La finestra che ospita questa vista: il clic sul carosello decide su di lei, non sulla finestra in primo piano.
    let window: () -> NSWindow?
    @AppStorage("libraryStripVisible") private var stripVisible = true

    var body: some View {
        VStack(spacing: 0) {
            CanvasRepresentable(model: model)
                .frame(minWidth: 320, minHeight: 240)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 8) {
                        ZoomControls(model: model)
                        CaptureDragHandle(model: model)
                    }
                    .padding(12)
                }
            if stripVisible {
                let library = AppEnvironment.shared.library
                LibraryStrip(library: library, state: stripState,
                             currentFile: currentURL().flatMap { library.file(for: $0) }) { item, newWindow in
                    LibraryOpener.open(item, from: window(), newWindow: newWindow)
                }
            }
        }
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.session.isReadOnly { ReadOnlyBanner() }
            }
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
                    .disabled(model.session.isReadOnly)
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: SharedCapture(model: model), preview: SharePreview("Cattura Pinxel"))
                        .help("Condividi l'immagine")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        stripVisible.toggle()
                    } label: {
                        Label("Carosello", systemImage: "rectangle.bottomthird.inset.filled")
                    }
                    .help("Mostra o nascondi il carosello delle catture (⌃⌘L)")
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


/// Avviso sopra la tela per i documenti di una versione più recente (spec §8, §10).
private struct ReadOnlyBanner: View {
    var body: some View {
        Label("Creato con una versione più recente di Pinxel: puoi guardarlo ed esportarlo, ma non modificarlo.", systemImage: "lock.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
    }
}
