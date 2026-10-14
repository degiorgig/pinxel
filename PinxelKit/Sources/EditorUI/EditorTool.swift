import DocumentModel

public enum EditorTool: String, CaseIterable, Sendable {
    case select, arrow, line, shape, pen, highlight, step, blur

    public var title: String {
        switch self {
        case .select: "Selezione"
        case .arrow: "Freccia"
        case .line: "Linea"
        case .shape: "Forma"
        case .pen: "Penna"
        case .highlight: "Evidenziatore"
        case .step: "Step"
        case .blur: "Sfocatura"
        }
    }

    /// Tasto singolo che attiva lo strumento (spec §6.2).
    public var shortcut: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .shape: "r"
        case .pen: "p"
        case .highlight: "h"
        case .step: "s"
        case .blur: "b"
        }
    }

    public var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .shape: "square"
        case .pen: "pencil.tip"
        case .highlight: "highlighter"
        case .step: "1.circle"
        case .blur: "eye.slash"
        }
    }

    public static func forShortcut(_ character: Character) -> EditorTool? {
        let key = Character(character.lowercased())
        return allCases.first { $0.shortcut == key }
    }
}

public enum EffectMode: String, CaseIterable, Sendable {
    case blur, pixelate
}

/// Stile e opzioni con cui ogni strumento crea le annotazioni.
public struct ToolStyles: Equatable, Sendable {
    public var styles: [EditorTool: Style]
    public var arrowHeads = ArrowHeads()
    public var shapeType: ShapeType = .rectangle
    public var stepSequence: StepSequence = .numbers
    /// Diametro degli step in pixel del documento.
    public var stepDiameter: Double = 48
    public var effectMode: EffectMode = .blur
    /// Raggio della sfocatura o lato dei blocchi, in pixel del documento.
    public var effectAmount: Double = 12

    public init() {
        styles = Dictionary(uniqueKeysWithValues: EditorTool.allCases.map { ($0, Self.defaultStyle(for: $0)) })
    }

    public static func defaultStyle(for tool: EditorTool) -> Style {
        switch tool {
        case .highlight: Style(stroke: .highlightYellow, lineWidth: 24)
        case .step: Style(stroke: nil, fill: .accentRed, lineWidth: 0)
        case .blur, .select: Style(stroke: nil, lineWidth: 0)
        case .arrow, .line, .shape, .pen: Style()
        }
    }

    public func style(for tool: EditorTool) -> Style {
        styles[tool] ?? Self.defaultStyle(for: tool)
    }
}
