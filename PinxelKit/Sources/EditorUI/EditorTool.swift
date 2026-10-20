import DocumentModel

public enum EditorTool: String, CaseIterable, Sendable {
    case select, arrow, line, shape, text, callout, step, pen, highlight, blur, magnifier, crop, cutOut

    public var title: String {
        switch self {
        case .select: String(localized: "Select", bundle: .module, comment: "Tool name")
        case .arrow: String(localized: "Arrow", bundle: .module, comment: "Tool name")
        case .line: String(localized: "Line", bundle: .module, comment: "Tool name")
        case .shape: String(localized: "Shape", bundle: .module, comment: "Tool name")
        case .text: String(localized: "Text", bundle: .module, comment: "Tool name")
        case .callout: String(localized: "Callout", bundle: .module, comment: "Tool name")
        case .step: String(localized: "Step", bundle: .module, comment: "Tool name")
        case .pen: String(localized: "Pen", bundle: .module, comment: "Tool name")
        case .highlight: String(localized: "Highlighter", bundle: .module, comment: "Tool name")
        case .blur: String(localized: "Blur", bundle: .module, comment: "Tool name")
        case .magnifier: String(localized: "Magnifier", bundle: .module, comment: "Tool name")
        case .crop: String(localized: "Crop", bundle: .module, comment: "Tool name")
        case .cutOut: String(localized: "Cut Out", bundle: .module, comment: "Tool name")
        }
    }

    /// Name in "Undo …" of an object created with the tool.
    public var addCommandName: String {
        switch self {
        case .arrow: String(localized: "Add Arrow", bundle: .module, comment: "Undo: new object")
        case .line: String(localized: "Add Line", bundle: .module, comment: "Undo: new object")
        case .shape: String(localized: "Add Shape", bundle: .module, comment: "Undo: new object")
        case .text: String(localized: "Add Text", bundle: .module, comment: "Undo: new object")
        case .callout: String(localized: "Add Callout", bundle: .module, comment: "Undo: new object")
        case .step: String(localized: "Add Step", bundle: .module, comment: "Undo: new object")
        case .pen: String(localized: "Add Pen Stroke", bundle: .module, comment: "Undo: new object")
        case .highlight: String(localized: "Add Highlight", bundle: .module, comment: "Undo: new object")
        case .blur: String(localized: "Add Blur", bundle: .module, comment: "Undo: new object")
        case .magnifier: String(localized: "Add Magnifier", bundle: .module, comment: "Undo: new object")
        case .select, .crop, .cutOut: CommandName.add
        }
    }

    /// Single key that activates the tool (spec §6.2).
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

    /// The tools that add annotations (not selection, crop and cut).
    public var createsAnnotations: Bool {
        ![.select, .crop, .cutOut].contains(self)
    }

    /// The tool that creates annotations of this kind.
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

/// Style and options with which each tool creates annotations.
public struct ToolStyles: Equatable, Sendable {
    public var styles: [EditorTool: Style]
    public var arrowHeads = ArrowHeads()
    public var shapeType: ShapeType = .rectangle
    public var stepSequence: StepSequence = .numbers
    /// Diameter of steps in document pixels.
    public var stepDiameter: Double = 48
    public var effectMode: EffectMode = .blur
    /// Blur radius or block side, in document pixels.
    public var effectAmount: Double = 12
    /// Font, size, color and alignment of new texts (without runs).
    public var text = RichText(runs: [], fontFamily: "Helvetica", fontSize: 24, color: .black)
    public var calloutText = RichText(runs: [], fontFamily: "Helvetica", fontSize: 20, color: .black)
    public var magnifierShape: ShapeType = .ellipse
    public var magnifierConnector = true
    /// Lens magnification: side of the destination / side of the source.
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
