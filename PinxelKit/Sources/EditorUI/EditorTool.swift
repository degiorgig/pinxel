import DocumentModel

public enum EditorTool: String, CaseIterable, Sendable {
    case select, arrow, line, shape, text, callout, step, pen, highlight, blur, magnifier, crop, cutOut

    public var title: String {
        switch self {
        case .select: "Selezione"
        case .arrow: "Freccia"
        case .line: "Linea"
        case .shape: "Forma"
        case .text: "Testo"
        case .callout: "Callout"
        case .step: "Step"
        case .pen: "Penna"
        case .highlight: "Evidenziatore"
        case .blur: "Sfocatura"
        case .magnifier: "Lente"
        case .crop: "Ritaglio"
        case .cutOut: "Taglia e ricuci"
        }
    }

    /// Tasto singolo che attiva lo strumento (spec §6.2).
    public var shortcut: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .shape: "r"
        case .text: "t"
        case .callout: "c"
        case .step: "s"
        case .pen: "p"
        case .highlight: "h"
        case .blur: "b"
        case .magnifier: "m"
        case .crop: "k"
        case .cutOut: "x"
        }
    }

    public var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .shape: "square"
        case .text: "textformat"
        case .callout: "text.bubble"
        case .step: "1.circle"
        case .pen: "pencil.tip"
        case .highlight: "highlighter"
        case .blur: "eye.slash"
        case .magnifier: "plus.magnifyingglass"
        case .crop: "crop"
        case .cutOut: "scissors"
        }
    }

    /// Gli strumenti che aggiungono annotazioni (non selezione, ritaglio e taglio).
    public var createsAnnotations: Bool {
        ![.select, .crop, .cutOut].contains(self)
    }

    /// Lo strumento che crea annotazioni di questo tipo.
    public init?(kind: Annotation.Kind) {
        switch kind {
        case .arrow: self = .arrow
        case .line: self = .line
        case .shape: self = .shape
        case .text: self = .text
        case .callout: self = .callout
        case .step: self = .step
        case .pen: self = .pen
        case .highlight: self = .highlight
        case .blur, .pixelate: self = .blur
        case .magnifier: self = .magnifier
        case .image, .unknown: return nil
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
    /// Carattere, dimensione, colore e allineamento dei testi nuovi (senza run).
    public var text = RichText(runs: [], fontFamily: "Helvetica", fontSize: 24, color: .black)
    public var calloutText = RichText(runs: [], fontFamily: "Helvetica", fontSize: 20, color: .black)
    public var magnifierShape: ShapeType = .ellipse
    public var magnifierConnector = true
    /// Ingrandimento della lente: lato della destinazione / lato della sorgente.
    public var magnifierZoom: Double = 2
    public var cutEdge: CutEdge = .zigzag

    public init() {
        styles = Dictionary(uniqueKeysWithValues: EditorTool.allCases.map { ($0, Self.defaultStyle(for: $0)) })
    }

    public static func defaultStyle(for tool: EditorTool) -> Style {
        switch tool {
        case .highlight: Style(stroke: .highlightYellow, lineWidth: 24)
        case .step: Style(stroke: nil, fill: .accentRed, lineWidth: 0)
        case .text: Style(stroke: nil, fill: nil, lineWidth: 0)
        case .callout: Style(stroke: .accentRed, fill: .white, lineWidth: 3)
        case .magnifier: Style(stroke: .black, lineWidth: 3)
        case .blur, .select, .crop, .cutOut: Style(stroke: nil, lineWidth: 0)
        case .arrow, .line, .shape, .pen: Style()
        }
    }

    public func style(for tool: EditorTool) -> Style {
        styles[tool] ?? Self.defaultStyle(for: tool)
    }
}
