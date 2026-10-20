import DocumentModel
import EditorUI
import SwiftUI

/// The last styles used with the tool: one click applies them (spec §6.1).
struct QuickStylesSection: View {
    let model: EditorModel

    var body: some View {
        if let tool = model.quickStyleTool {
            let styles = model.quickStyles.styles(for: tool)
            if !styles.isEmpty {
                Section("Quick Styles") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
                        ForEach(Array(styles.enumerated()), id: \.offset) { index, style in
                            Button {
                                model.applyQuickStyle(style)
                            } label: {
                                QuickStyleSwatch(style: style, tool: tool)
                            }
                            .buttonStyle(.plain)
                            .help("Apply quick style \(index + 1)")
                            .accessibilityLabel("Quick style \(index + 1)")
                        }
                    }
                }
            }
        }
    }
}

/// Preview of a style: a stroke for lines and pens, a circle for steps, a box for the rest.
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
