import AppKit
import DocumentModel
import EditorUI
import SwiftUI

/// Font, size, color, alignment and style of texts and callouts, also while editing on the canvas.
struct TextSection: View {
    let model: EditorModel

    static let families = ["Helvetica", "Helvetica Neue", "Avenir Next", "Georgia", "Menlo", "Marker Felt"]

    var body: some View {
        let text = model.inspectedRichText
        Section("Text") {
            Picker("Font", selection: Binding(
                get: { model.inspectedRichText.fontFamily },
                set: { family in model.updateText(name: CommandName.font) { $0.fontFamily = family } }
            )) {
                ForEach(Self.families, id: \.self) { Text($0).tag($0) }
                if !Self.families.contains(text.fontFamily) { Text(text.fontFamily).tag(text.fontFamily) }
            }
            LabeledContent("Size") {
                Stepper(value: Binding(
                    get: { model.inspectedRichText.fontSize },
                    set: { size in model.updateText(name: CommandName.textSize) { $0.fontSize = size } }
                ), in: 8...200, step: 2) {
                    Text(verbatim: "\(Int(text.fontSize)) px").monospacedDigit()
                }
            }
            ColorPicker("Text Color", selection: Binding(
                get: { Color(nsColor: model.inspectedRichText.color.nsColor) },
                set: { color in model.updateText(name: CommandName.textColor, coalescing: true) { $0.setColor(RGBA(nsColor: NSColor(color))) } }
            ), supportsOpacity: false)
            Picker("Alignment", selection: Binding(
                get: { model.inspectedRichText.alignment },
                set: { alignment in model.updateText(name: CommandName.alignment) { $0.alignment = alignment } }
            )) {
                Image(systemName: "text.alignleft").help("Left").tag(RichTextAlignment.left)
                Image(systemName: "text.aligncenter").help("Center").tag(RichTextAlignment.center)
                Image(systemName: "text.alignright").help("Right").tag(RichTextAlignment.right)
            }
            .pickerStyle(.segmented)
            LabeledContent("Style") {
                HStack(spacing: 4) {
                    styleToggle("bold", help: String(localized: "Bold (⌘B)"), isOn: Binding(
                        get: { model.inspectedRichText.isBold },
                        set: { on in model.updateText(name: CommandName.bold) { $0.setBold(on) } }
                    ))
                    styleToggle("italic", help: String(localized: "Italic (⌘I)"), isOn: Binding(
                        get: { model.inspectedRichText.isItalic },
                        set: { on in model.updateText(name: CommandName.italic) { $0.setItalic(on) } }
                    ))
                    styleToggle("underline", help: String(localized: "Underline (⌘U)"), isOn: Binding(
                        get: { model.inspectedRichText.isUnderlined },
                        set: { on in model.updateText(name: CommandName.underline) { $0.setUnderline(on) } }
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
