import DocumentModel
import EditorUI
import SwiftUI

/// Gli ultimi stili usati con lo strumento: un clic li applica (spec §6.1).
struct QuickStylesSection: View {
    let model: EditorModel

    var body: some View {
        if let tool = model.quickStyleTool {
            let styles = model.quickStyles.styles(for: tool)
            if !styles.isEmpty {
                Section("Stili rapidi") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
                        ForEach(Array(styles.enumerated()), id: \.offset) { index, style in
                            Button {
                                model.applyQuickStyle(style)
                            } label: {
                                QuickStyleSwatch(style: style, tool: tool)
                            }
                            .buttonStyle(.plain)
                            .help("Applica lo stile rapido \(index + 1)")
                            .accessibilityLabel("Stile rapido \(index + 1)")
                        }
                    }
                }
            }
        }
    }
}

/// Anteprima di uno stile: un tratto per linee e penne, un cerchio per gli step, un riquadro per il resto.
struct QuickStyleSwatch: View {
    let style: Style
    let tool: EditorTool

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            let stroke = style.stroke.map { Color(nsColor: $0.nsColor) }
            let fill = style.fill.map { Color(nsColor: $0.nsColor) }
            let width = min(max(style.lineWidth / 2, 1), 5)
            switch tool {
            case .arrow, .line, .pen, .highlight:
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                context.stroke(path, with: .color(stroke ?? .primary), style: StrokeStyle(lineWidth: width, lineCap: .round))
            case .step:
                context.fill(Path(ellipseIn: rect), with: .color(fill ?? .red))
            default:
                let path = Path(roundedRect: rect, cornerRadius: 4)
                if let fill { context.fill(path, with: .color(fill)) }
                if let stroke, style.lineWidth > 0 { context.stroke(path, with: .color(stroke), lineWidth: width) }
            }
        }
        .frame(width: 30, height: 30)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        .opacity(style.opacity)
        .contentShape(Rectangle())
    }
}
