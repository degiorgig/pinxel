import AppKit
import DocumentModel
import EditorUI
import SwiftUI

/// Immagine → Ridimensiona immagine…: nuove dimensioni in pixel, proporzioni bloccate di base.
struct ResizeImageSheet: View {
    let model: EditorModel
    @State private var draft: ResizeDraft
    @Environment(\.dismiss) private var dismiss

    private static let percents = [25, 50, 75, 100, 150, 200]

    init(model: EditorModel) {
        self.model = model
        _draft = State(initialValue: ResizeDraft(original: model.session.document.imageSize))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Larghezza") {
                        HStack {
                            TextField("Larghezza", value: Binding(get: { draft.width }, set: { draft.setWidth($0) }), format: .number)
                                .labelsHidden()
                                .frame(width: 90)
                            Text("px").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Altezza") {
                        HStack {
                            TextField("Altezza", value: Binding(get: { draft.height }, set: { draft.setHeight($0) }), format: .number)
                                .labelsHidden()
                                .frame(width: 90)
                            Text("px").foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Mantieni le proporzioni", isOn: $draft.keepsAspect)
                    Picker("Scala", selection: Binding(get: { draft.percent }, set: { draft.setPercent(Double($0)) })) {
                        ForEach(Self.percents, id: \.self) { Text("\($0)%").tag($0) }
                        if !Self.percents.contains(draft.percent) { Text("\(draft.percent)%").tag(draft.percent) }
                    }
                } header: {
                    Text("Ridimensiona immagine")
                } footer: {
                    Text("Attuale: \(draft.original.width) × \(draft.original.height) px. Le annotazioni seguono l'immagine.")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Ridimensiona") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.targetSize == nil)
            }
            .padding()
        }
        .frame(width: 400)
    }

    private func apply() {
        if let size = draft.targetSize {
            let session = model.session
            let before = session.document.annotations
            session.perform(SetAnnotations(name: "Ridimensiona", before: before,
                                           after: ContentEditing.scaled(before, from: draft.original, to: size)))
        }
        dismiss()
    }
}

/// Immagine → Bordo, ombra e margini…: anteprima dal vivo sulla tela, un solo comando alla conferma.
struct CanvasStyleSheet: View {
    let model: EditorModel
    @State private var style: CanvasStyle
    @Environment(\.dismiss) private var dismiss

    init(model: EditorModel) {
        self.model = model
        _style = State(initialValue: model.session.document.canvasStyle)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Bordo") {
                    Toggle("Bordo", isOn: Binding(get: { style.border != nil }, set: { style = CanvasStyleEditing.settingBorder($0, in: style) }))
                    if let border = style.border {
                        ColorPicker("Colore", selection: Binding(
                            get: { Color(nsColor: border.color.nsColor) },
                            set: { style.border?.color = RGBA(nsColor: NSColor($0)) }
                        ), supportsOpacity: false)
                        LabeledContent("Spessore") {
                            Slider(value: Binding(get: { border.width }, set: { style.border?.width = $0.rounded() }), in: 1...40)
                        }
                    }
                }
                Section("Ombra") {
                    Toggle("Ombra", isOn: Binding(get: { style.shadow != nil }, set: { style = CanvasStyleEditing.settingShadow($0, in: style) }))
                }
                Section("Margini") {
                    LabeledContent("Margine") {
                        HStack {
                            Slider(value: Binding(get: { style.padding }, set: { style.padding = $0.rounded() }), in: 0...200)
                            Text("\(Int(style.padding)) px").monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                    }
                    Toggle("Sfondo", isOn: Binding(get: { style.backgroundColor != nil }, set: { style = CanvasStyleEditing.settingBackground($0, in: style) }))
                    if let background = style.backgroundColor {
                        ColorPicker("Colore sfondo", selection: Binding(
                            get: { Color(nsColor: background.nsColor) },
                            set: { style.backgroundColor = RGBA(nsColor: NSColor($0)) }
                        ), supportsOpacity: true)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Applica") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(style == model.session.document.canvasStyle)
            }
            .padding()
        }
        .frame(width: 400)
        .onAppear { model.session.canvasStylePreview = style }
        .onChange(of: style) { _, newValue in model.session.canvasStylePreview = newValue }
        .onDisappear { model.session.canvasStylePreview = nil }
    }

    private func apply() {
        let before = model.session.document.canvasStyle
        if style != before {
            model.session.perform(UpdateCanvasStyle(before: before, after: style, name: "Bordo, ombra e margini"))
        }
        dismiss()
    }
}
