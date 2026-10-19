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
                Text("Select an object or choose a tool to see its properties.")
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
        Section("Style") {
            if kind.showsStroke {
                ColorPicker("Color", selection: Binding(
                    get: { Color(nsColor: (model.inspectedStyle.stroke ?? .accentRed).nsColor) },
                    set: { model.setStyle(\.stroke, RGBA(nsColor: NSColor($0)), coalescing: true) }
                ), supportsOpacity: false)
            }
            if kind.showsFill {
                Toggle("Fill", isOn: Binding(
                    get: { model.inspectedStyle.fill != nil },
                    set: { model.setFill($0) }
                ))
                if style.fill != nil {
                    ColorPicker("Fill Color", selection: Binding(
                        get: { Color(nsColor: (model.inspectedStyle.fill ?? .accentRed).nsColor) },
                        set: { model.setStyle(\.fill, RGBA(nsColor: NSColor($0)), coalescing: true) }
                    ), supportsOpacity: true)
                }
            }
            if kind.showsLineWidth {
                LabeledContent("Line Width") {
                    CommittingSlider(value: style.lineWidth, range: 1...40,
                                     preview: { model.previewStyle(\.lineWidth, $0) },
                                     commit: { model.setStyle(\.lineWidth, $0) })
                }
            }
            if kind.showsDash {
                Picker("Stroke", selection: Binding(get: { model.inspectedStyle.dash }, set: { model.setStyle(\.dash, $0) })) {
                    Text("Solid").tag(DashPattern.solid)
                    Text("Dashed").tag(DashPattern.dashed)
                    Text("Dotted").tag(DashPattern.dotted)
                }
            }
            if kind.showsOpacity {
                LabeledContent("Opacity") {
                    CommittingSlider(value: style.opacity, range: 0.1...1,
                                     preview: { model.previewStyle(\.opacity, $0) },
                                     commit: { model.setStyle(\.opacity, $0) })
                }
            }
            if kind.showsShadow {
                Toggle("Shadow", isOn: Binding(
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
            Section("Arrow") {
                Picker("Start", selection: headBinding(start: true)) { headOptions }
                Picker("End", selection: headBinding(start: false)) { headOptions }
            }
        case .shape:
            Section("Shape") {
                Picker("Type", selection: shapeBinding) {
                    Text("Rectangle").tag(ShapeChoice.rectangle)
                    Text("Rounded").tag(ShapeChoice.rounded)
                    Text("Ellipse").tag(ShapeChoice.ellipse)
                }
            }
        case .step:
            Section("Step") {
                Picker("Sequence", selection: Binding(
                    get: { model.inspectedAnnotation?.stepSequence ?? model.toolStyles.stepSequence },
                    set: { sequence in
                        model.update(name: CommandName.sequence, selection: { $0.stepSequence = sequence }, tool: { $0.stepSequence = sequence })
                    }
                )) {
                    Text(verbatim: "1, 2, 3").tag(StepSequence.numbers)
                    Text(verbatim: "A, B, C").tag(StepSequence.uppercaseLetters)
                    Text(verbatim: "a, b, c").tag(StepSequence.lowercaseLetters)
                }
            }
        case .effect:
            Section("Privacy") {
                Picker("Effect", selection: Binding(
                    get: { model.inspectedAnnotation?.effectMode ?? model.toolStyles.effectMode },
                    set: { model.setEffectMode($0) }
                )) {
                    Text("Blur").tag(EffectMode.blur)
                    Text("Pixelate").tag(EffectMode.pixelate)
                }
                .pickerStyle(.segmented)
                LabeledContent("Intensity") {
                    CommittingSlider(
                        value: model.inspectedAnnotation?.effectAmount ?? model.toolStyles.effectAmount,
                        range: 2...40,
                        preview: { amount in
                            model.previewUpdate(selection: { $0.effectAmount = amount }, tool: { $0.effectAmount = amount })
                        },
                        commit: { amount in
                            model.update(name: CommandName.intensity, selection: { $0.effectAmount = amount }, tool: { $0.effectAmount = amount })
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
        Text("None").tag(HeadStyle.none)
        Text("Triangle").tag(HeadStyle.triangle)
        Text("Open").tag(HeadStyle.open)
        Text("Circle").tag(HeadStyle.circle)
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
                model.update(name: CommandName.arrowHeads, selection: { $0.arrowHeads = chosen }, tool: { $0.arrowHeads = chosen })
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
                model.update(name: CommandName.shape, selection: { $0.shapeType = shape }, tool: { $0.shapeType = shape })
            }
        )
    }
}
