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
                    LabeledContent("Width") {
                        HStack {
                            TextField("Width", value: Binding(get: { draft.width }, set: { draft.setWidth($0) }), format: .number)
                                .labelsHidden()
                                .frame(width: 90)
                            Text(verbatim: "px").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Height") {
                        HStack {
                            TextField("Height", value: Binding(get: { draft.height }, set: { draft.setHeight($0) }), format: .number)
                                .labelsHidden()
                                .frame(width: 90)
                            Text(verbatim: "px").foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Keep Proportions", isOn: $draft.keepsAspect)
                    Picker("Scale", selection: Binding(get: { draft.percent }, set: { draft.setPercent(Double($0)) })) {
                        ForEach(Self.percents, id: \.self) { Text(verbatim: "\($0)%").tag($0) }
                        if !Self.percents.contains(draft.percent) { Text(verbatim: "\(draft.percent)%").tag(draft.percent) }
                    }
                } header: {
                    Text("Resize Image")
                } footer: {
                    Text("Current: \(draft.original.width) × \(draft.original.height) px. Annotations follow the image.")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Resize") { apply() }
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
            session.perform(SetAnnotations(name: CommandName.resize, before: before,
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
                Section("Border") {
                    Toggle("Border", isOn: Binding(get: { style.border != nil }, set: { style = CanvasStyleEditing.settingBorder($0, in: style) }))
                    if let border = style.border {
                        ColorPicker("Color", selection: Binding(
                            get: { Color(nsColor: border.color.nsColor) },
                            set: { style.border?.color = RGBA(nsColor: NSColor($0)) }
                        ), supportsOpacity: false)
                        LabeledContent("Line Width") {
                            Slider(value: Binding(get: { border.width }, set: { style.border?.width = $0.rounded() }), in: 1...40)
                        }
                    }
                }
                Section("Shadow") {
                    Toggle("Shadow", isOn: Binding(get: { style.shadow != nil }, set: { style = CanvasStyleEditing.settingShadow($0, in: style) }))
                }
                Section("Padding") {
                    LabeledContent("Margin") {
                        HStack {
                            Slider(value: Binding(get: { style.padding }, set: { style.padding = $0.rounded() }), in: 0...200)
                            Text(verbatim: "\(Int(style.padding)) px").monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                    }
                    Toggle("Background", isOn: Binding(get: { style.backgroundColor != nil }, set: { style = CanvasStyleEditing.settingBackground($0, in: style) }))
                    if let background = style.backgroundColor {
                        ColorPicker("Background Color", selection: Binding(
                            get: { Color(nsColor: background.nsColor) },
                            set: { style.backgroundColor = RGBA(nsColor: NSColor($0)) }
                        ), supportsOpacity: true)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { apply() }
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
            model.session.perform(UpdateCanvasStyle(before: before, after: style, name: CommandName.canvasStyle))
        }
        dismiss()
    }
}
