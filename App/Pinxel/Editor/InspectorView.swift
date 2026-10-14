import AppKit
import DocumentModel
import EditorUI
import SwiftUI

/// Pannello proprietà: stile e opzioni dello strumento attivo o della selezione (spec §6.1).
struct InspectorView: View {
    @Bindable var model: EditorModel

    private enum ShapeChoice: Hashable {
        case rectangle, rounded, ellipse
    }

    var body: some View {
        let kind = model.inspectedKind
        Form {
            if kind == .none {
                Text("Seleziona un oggetto o scegli uno strumento per vederne le proprietà.")
                    .foregroundStyle(.secondary)
            } else {
                if kind.showsStyleSection { styleSection(kind) }
                QuickStylesSection(model: model)
                kindSection(kind)
            }
        }
        .formStyle(.grouped)
        .disabled(model.session.isReadOnly)
    }

    @ViewBuilder
    private func styleSection(_ kind: InspectedKind) -> some View {
        let style = model.inspectedStyle
        Section("Stile") {
            if kind.showsStroke {
                ColorPicker("Colore", selection: Binding(
                    get: { Color(nsColor: (model.inspectedStyle.stroke ?? .accentRed).nsColor) },
                    set: { model.setStyle(\.stroke, RGBA(nsColor: NSColor($0)), coalescing: true) }
                ), supportsOpacity: false)
            }
            if kind.showsFill {
                Toggle("Riempimento", isOn: Binding(
                    get: { model.inspectedStyle.fill != nil },
                    set: { model.setStyle(\.fill, $0 ? (model.inspectedStyle.stroke ?? .accentRed) : nil) }
                ))
                if style.fill != nil {
                    ColorPicker("Colore riempimento", selection: Binding(
                        get: { Color(nsColor: (model.inspectedStyle.fill ?? .accentRed).nsColor) },
                        set: { model.setStyle(\.fill, RGBA(nsColor: NSColor($0)), coalescing: true) }
                    ), supportsOpacity: true)
                }
            }
            if kind.showsLineWidth {
                LabeledContent("Spessore") {
                    CommittingSlider(value: style.lineWidth, range: 1...40,
                                     preview: { model.previewStyle(\.lineWidth, $0) },
                                     commit: { model.setStyle(\.lineWidth, $0) })
                }
            }
            if kind.showsDash {
                Picker("Tratto", selection: Binding(get: { model.inspectedStyle.dash }, set: { model.setStyle(\.dash, $0) })) {
                    Text("Continuo").tag(DashPattern.solid)
                    Text("Tratteggiato").tag(DashPattern.dashed)
                    Text("Punteggiato").tag(DashPattern.dotted)
                }
            }
            if kind.showsOpacity {
                LabeledContent("Opacità") {
                    CommittingSlider(value: style.opacity, range: 0.1...1,
                                     preview: { model.previewStyle(\.opacity, $0) },
                                     commit: { model.setStyle(\.opacity, $0) })
                }
            }
            if kind.showsShadow {
                Toggle("Ombra", isOn: Binding(
                    get: { model.inspectedStyle.shadow != nil },
                    set: { model.setStyle(\.shadow, $0 ? Shadow() : nil) }
                ))
            }
        }
    }

    @ViewBuilder
    private func kindSection(_ kind: InspectedKind) -> some View {
        switch kind {
        case .arrow:
            Section("Freccia") {
                Picker("Inizio", selection: headBinding(start: true)) { headOptions }
                Picker("Fine", selection: headBinding(start: false)) { headOptions }
            }
        case .shape:
            Section("Forma") {
                Picker("Tipo", selection: shapeBinding) {
                    Text("Rettangolo").tag(ShapeChoice.rectangle)
                    Text("Arrotondato").tag(ShapeChoice.rounded)
                    Text("Ellisse").tag(ShapeChoice.ellipse)
                }
            }
        case .step:
            Section("Step") {
                Picker("Sequenza", selection: Binding(
                    get: { model.inspectedAnnotation?.stepSequence ?? model.toolStyles.stepSequence },
                    set: { sequence in
                        model.update(name: "Sequenza", selection: { $0.stepSequence = sequence }, tool: { $0.stepSequence = sequence })
                    }
                )) {
                    Text("1, 2, 3").tag(StepSequence.numbers)
                    Text("A, B, C").tag(StepSequence.uppercaseLetters)
                    Text("a, b, c").tag(StepSequence.lowercaseLetters)
                }
            }
        case .effect:
            Section("Privacy") {
                Picker("Effetto", selection: Binding(
                    get: { model.inspectedAnnotation?.effectMode ?? model.toolStyles.effectMode },
                    set: { model.setEffectMode($0) }
                )) {
                    Text("Sfocatura").tag(EffectMode.blur)
                    Text("Pixel").tag(EffectMode.pixelate)
                }
                .pickerStyle(.segmented)
                LabeledContent("Intensità") {
                    CommittingSlider(
                        value: model.inspectedAnnotation?.effectAmount ?? model.toolStyles.effectAmount,
                        range: 2...40,
                        preview: { amount in
                            model.previewUpdate(selection: { $0.effectAmount = amount }, tool: { $0.effectAmount = amount })
                        },
                        commit: { amount in
                            model.update(name: "Intensità", selection: { $0.effectAmount = amount }, tool: { $0.effectAmount = amount })
                        }
                    )
                }
            }
        case .text, .callout:
            TextSection(model: model)
        case .magnifier:
            MagnifierSection(model: model)
        case .crop:
            CropSection()
        case .cutOut:
            CutSection(model: model)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var headOptions: some View {
        Text("Nessuna").tag(HeadStyle.none)
        Text("Triangolo").tag(HeadStyle.triangle)
        Text("Aperta").tag(HeadStyle.open)
        Text("Cerchio").tag(HeadStyle.circle)
    }

    private func headBinding(start: Bool) -> Binding<HeadStyle> {
        Binding(
            get: {
                let heads = model.inspectedAnnotation?.arrowHeads ?? model.toolStyles.arrowHeads
                return start ? heads.start : heads.end
            },
            set: { head in
                var heads = model.inspectedAnnotation?.arrowHeads ?? model.toolStyles.arrowHeads
                if start { heads.start = head } else { heads.end = head }
                let chosen = heads
                model.update(name: "Punte", selection: { $0.arrowHeads = chosen }, tool: { $0.arrowHeads = chosen })
            }
        )
    }

    private var shapeBinding: Binding<ShapeChoice> {
        Binding(
            get: {
                switch model.inspectedAnnotation?.shapeType ?? model.toolStyles.shapeType {
                case .rectangle: .rectangle
                case .roundedRectangle: .rounded
                case .ellipse: .ellipse
                }
            },
            set: { choice in
                let shape: ShapeType = switch choice {
                case .rectangle: .rectangle
                case .rounded: .roundedRectangle(cornerRadius: 12)
                case .ellipse: .ellipse
                }
                model.update(name: "Forma", selection: { $0.shapeType = shape }, tool: { $0.shapeType = shape })
            }
        )
    }
}
