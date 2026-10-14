import AppKit
import DocumentModel
import EditorUI
import SwiftUI

/// Carattere, dimensione, colore, allineamento e stile di testi e callout, anche durante la modifica sulla tela.
struct TextSection: View {
    let model: EditorModel

    static let families = ["Helvetica", "Helvetica Neue", "Avenir Next", "Georgia", "Menlo", "Marker Felt"]

    var body: some View {
        let text = model.inspectedRichText
        Section("Testo") {
            Picker("Carattere", selection: Binding(
                get: { model.inspectedRichText.fontFamily },
                set: { family in model.updateText(name: "Carattere") { $0.fontFamily = family } }
            )) {
                ForEach(Self.families, id: \.self) { Text($0).tag($0) }
                if !Self.families.contains(text.fontFamily) { Text(text.fontFamily).tag(text.fontFamily) }
            }
            LabeledContent("Dimensione") {
                Stepper(value: Binding(
                    get: { model.inspectedRichText.fontSize },
                    set: { size in model.updateText(name: "Dimensione testo") { $0.fontSize = size } }
                ), in: 8...200, step: 2) {
                    Text("\(Int(text.fontSize)) px").monospacedDigit()
                }
            }
            ColorPicker("Colore testo", selection: Binding(
                get: { Color(nsColor: model.inspectedRichText.color.nsColor) },
                set: { color in model.updateText(name: "Colore testo", coalescing: true) { $0.setColor(RGBA(nsColor: NSColor(color))) } }
            ), supportsOpacity: false)
            Picker("Allineamento", selection: Binding(
                get: { model.inspectedRichText.alignment },
                set: { alignment in model.updateText(name: "Allineamento") { $0.alignment = alignment } }
            )) {
                Image(systemName: "text.alignleft").help("A sinistra").tag(RichTextAlignment.left)
                Image(systemName: "text.aligncenter").help("Al centro").tag(RichTextAlignment.center)
                Image(systemName: "text.alignright").help("A destra").tag(RichTextAlignment.right)
            }
            .pickerStyle(.segmented)
            LabeledContent("Stile") {
                HStack(spacing: 4) {
                    styleToggle("bold", help: "Grassetto (⌘B)", isOn: Binding(
                        get: { model.inspectedRichText.isBold },
                        set: { on in model.updateText(name: "Grassetto") { $0.setBold(on) } }
                    ))
                    styleToggle("italic", help: "Corsivo (⌘I)", isOn: Binding(
                        get: { model.inspectedRichText.isItalic },
                        set: { on in model.updateText(name: "Corsivo") { $0.setItalic(on) } }
                    ))
                    styleToggle("underline", help: "Sottolineato (⌘U)", isOn: Binding(
                        get: { model.inspectedRichText.isUnderlined },
                        set: { on in model.updateText(name: "Sottolineato") { $0.setUnderline(on) } }
                    ))
                }
            }
            .disabled(text.runs.isEmpty)
        }
    }

    private func styleToggle(_ symbol: String, help: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Image(systemName: symbol)
        }
        .toggleStyle(.button)
        .help(help)
        .accessibilityLabel(help)
    }
}
