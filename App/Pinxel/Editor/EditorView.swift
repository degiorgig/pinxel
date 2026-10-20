import EditorUI
import Library
import SwiftUI

/// Window content: canvas in the center, tools in the native toolbar, properties on the right.
struct EditorView: View {
    @Bindable var model: EditorModel
    let stripState: LibraryStripState
    /// The window's file, read at every draw: an untitled document can become a file.
    let currentURL: () -> URL?
    /// The window hosting this view: a click on the carousel decides about it, not about the frontmost window.
    let window: () -> NSWindow?
    @AppStorage("libraryStripVisible") private var stripVisible = true

    var body: some View {
        VStack(spacing: 0) {
            CanvasRepresentable(model: model)
                // Capture changed in the same window: a new canvas, not the old one with another model.
                .id(ObjectIdentifier(model))
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
                    Picker("Tool", selection: $model.tool) {
                        ForEach(EditorTool.allCases, id: \.self) { tool in
                            Label(tool.title, systemImage: tool.symbolName)
                                .help(Text(verbatim: "\(tool.title) (\(String(tool.shortcut).uppercased()))"))
                                .tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .disabled(model.session.isReadOnly)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    // The same commands as Arrange, at hand: the shortcuts with [ and ] are awkward
                    // on keyboards that produce them with ⌥.
                    let canArrange = EditorMenuState(model: model).hasEditableSelection
                    Button {
                        model.canvas?.bringToFront(nil)
                    } label: {
                        Label("To Front", systemImage: "square.3.layers.3d.top.filled")
                    }
                    .help("Bring the selection to the front (⇧⌘])")
                    .disabled(!canArrange)
                    Button {
                        model.canvas?.sendToBack(nil)
                    } label: {
                        Label("To Back", systemImage: "square.3.layers.3d.bottom.filled")
                    }
                    .help("Send the selection to the back (⇧⌘[)")
                    .disabled(!canArrange)
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: SharedCapture(model: model), preview: SharePreview("Pinxel Capture"))
                        .help("Share the image")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        stripVisible.toggle()
                    } label: {
                        Label("Strip", systemImage: "rectangle.bottomthird.inset.filled")
                    }
                    .help("Show or hide the capture strip (⌃⌘L)")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.isInspectorPresented.toggle()
                    } label: {
                        Label("Properties", systemImage: "sidebar.trailing")
                    }
                    .help("Show or hide the properties panel")
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


/// Banner above the canvas for documents from a newer version (spec §8, §10).
private struct ReadOnlyBanner: View {
    var body: some View {
        Label("Created with a newer version of Pinxel: you can view and export it, but not edit it.", systemImage: "lock.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
    }
}
