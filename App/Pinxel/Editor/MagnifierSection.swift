import DocumentModel
import EditorUI
import SwiftUI

/// Forma, ingrandimento e connettore della lente (spec §6.4).
struct MagnifierSection: View {
    let model: EditorModel

    private enum ShapeChoice: Hashable {
        case rectangle, rounded, ellipse

        init(_ shape: ShapeType) {
            switch shape {
            case .rectangle: self = .rectangle
            case .roundedRectangle: self = .rounded
            case .ellipse: self = .ellipse
            }
        }

        var shape: ShapeType {
            switch self {
            case .rectangle: .rectangle
            case .rounded: .roundedRectangle(cornerRadius: 12)
            case .ellipse: .ellipse
            }
        }
    }

    private static let zooms: [Double] = [1.5, 2, 3, 4]

    var body: some View {
        Section("Lente") {
            Picker("Forma", selection: Binding(
                get: { ShapeChoice(model.inspectedAnnotation?.magnifierShape ?? model.toolStyles.magnifierShape) },
                set: { choice in
                    let shape = choice.shape
                    model.update(name: "Forma lente", selection: { $0.magnifierShape = shape }, tool: { $0.magnifierShape = shape })
                }
            )) {
                Text("Rettangolo").tag(ShapeChoice.rectangle)
                Text("Arrotondata").tag(ShapeChoice.rounded)
                Text("Cerchio").tag(ShapeChoice.ellipse)
            }
            Picker("Ingrandimento", selection: Binding(
                get: {
                    let zoom = model.inspectedAnnotation?.magnifierZoom ?? model.toolStyles.magnifierZoom
                    return Self.zooms.min { abs($0 - zoom) < abs($1 - zoom) } ?? 2
                },
                set: { zoom in
                    model.update(name: "Ingrandimento", selection: { $0.magnifierZoom = zoom }, tool: { $0.magnifierZoom = zoom })
                }
            )) {
                ForEach(Self.zooms, id: \.self) { Text("\($0.formatted())×").tag($0) }
            }
            Toggle("Connettore", isOn: Binding(
                get: { model.inspectedAnnotation?.magnifierConnector ?? model.toolStyles.magnifierConnector },
                set: { on in
                    model.update(name: "Connettore", selection: { $0.magnifierConnector = on }, tool: { $0.magnifierConnector = on })
                }
            ))
        }
    }
}
