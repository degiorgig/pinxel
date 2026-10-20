import DocumentModel
import Foundation
import Observation

/// Kind of object the properties panel refers to.
public enum InspectedKind: Equatable, Sendable {
    case arrow, line, shape, text, callout, pen, highlight, step, effect, magnifier, image, crop, cutOut, none

    init(_ kind: Annotation.Kind) {
        switch kind {
        case .arrow: self = .arrow
        case .line: self = .line
        case .shape: self = .shape
        case .text: self = .text
        case .callout: self = .callout
        case .pen: self = .pen
        case .highlight: self = .highlight
        case .step: self = .step
        case .blur, .pixelate: self = .effect
        case .magnifier: self = .magnifier
        case .image: self = .image
        case .unknown: self = .none
        }
    }

    init(_ tool: EditorTool) {
        switch tool {
        case .select: self = .none
        case .arrow: self = .arrow
        case .line: self = .line
        case .shape: self = .shape
        case .text: self = .text
        case .callout: self = .callout
        case .pen: self = .pen
        case .highlight: self = .highlight
        case .step: self = .step
        case .blur: self = .effect
        case .magnifier: self = .magnifier
        case .crop: self = .crop
        case .cutOut: self = .cutOut
        }
    }

    public var showsStroke: Bool { [.arrow, .line, .shape, .callout, .pen, .highlight, .magnifier].contains(self) }
    public var showsFill: Bool { [.shape, .step, .text, .callout].contains(self) }
    public var showsLineWidth: Bool { showsStroke }
    public var showsDash: Bool { [.arrow, .line, .shape, .callout].contains(self) }
    public var showsOpacity: Bool { ![.effect, .crop, .cutOut, .none].contains(self) }
    public var showsShadow: Bool { ![.effect, .highlight, .crop, .cutOut, .none].contains(self) }
    public var showsText: Bool { self == .text || self == .callout }
    /// Crop and cut have no colors or strokes: the panel shows only their options.
    public var showsStyleSection: Bool { showsStroke || showsFill || showsOpacity || showsShadow }
}

/// Editor window state beyond the document: active tool, tool styles, panel.
@MainActor
@Observable
public final class EditorModel {
    public let session: EditorSession
    public var tool: EditorTool = .select {
        // Choosing a tool turns off the hand.
        didSet { isPanning = false }
    }
    /// Hand control above the canvas: dragging pans the view instead of using the tool.
    public var isPanning = false
    /// Canvas zoom (1 = 100%), copied from the canvas for the controls above the image.
    public internal(set) var zoom: Double = 1
    /// The canvas, to which the controls above the image send zoom and fit.
    @ObservationIgnored public internal(set) weak var canvas: (any EditorActions)?
    public var toolStyles = ToolStyles()
    public var isInspectorPresented = true
    /// Sheet of the Image menu open on the window.
    public var presentedSheet: EditorSheet?
    /// Text being edited on the canvas (observable copy for the panel); `nil` when not editing.
    public internal(set) var editingText: RichText?
    /// The text being edited, to which the panel sends its changes.
    @ObservationIgnored public internal(set) weak var textEditing: (any TextEditingControl)?

    public let quickStyles: QuickStyleStore

    public init(session: EditorSession, quickStyles: QuickStyleStore = .shared) {
        self.session = session
        self.quickStyles = quickStyles
    }

    /// The tool whose quick styles the panel shows: that of the selected object or the active one.
    public var quickStyleTool: EditorTool? {
        if let annotation = inspectedAnnotation { return EditorTool(kind: annotation.kind) }
        return tool.createsAnnotations ? tool : nil
    }

    /// Applies a quick style to the selected objects of the same tool, or to the tool.
    public func applyQuickStyle(_ style: Style) {
        guard let target = quickStyleTool else { return }
        update(name: CommandName.quickStyle, selection: { annotation in
            if EditorTool(kind: annotation.kind) == target { annotation.style = style }
        }, tool: { styles in
            styles.styles[target] = style
        })
    }

    /// Crop and cut work on the whole image: the panel shows their options even with a selection.
    public var inspectedAnnotation: Annotation? {
        [.crop, .cutOut].contains(tool) ? nil : session.selectedAnnotations.first
    }

    public var inspectedKind: InspectedKind {
        if let annotation = inspectedAnnotation { return InspectedKind(annotation.kind) }
        return InspectedKind(tool)
    }

    /// Style of the first selected annotation, otherwise that of the active tool.
    public var inspectedStyle: Style {
        inspectedAnnotation?.style ?? toolStyles.style(for: tool)
    }

    public func setStyle<Value: Equatable>(_ keyPath: WritableKeyPath<Style, Value>, _ value: Value, coalescing: Bool = false) {
        let tool = self.tool
        update(name: CommandName.style, coalescing: coalescing, selection: { $0.style[keyPath: keyPath] = value }, tool: { styles in
            styles.styles[tool, default: ToolStyles.defaultStyle(for: tool)][keyPath: keyPath] = value
        })
    }

    public func previewStyle<Value: Equatable>(_ keyPath: WritableKeyPath<Style, Value>, _ value: Value) {
        let tool = self.tool
        previewUpdate(selection: { $0.style[keyPath: keyPath] = value }, tool: { styles in
            styles.styles[tool, default: ToolStyles.defaultStyle(for: tool)][keyPath: keyPath] = value
        })
    }

    /// With a selection it edits the selected annotations (one command); otherwise the tool styles.
    public func update(name: String, coalescing: Bool = false,
                       selection change: (inout Annotation) -> Void,
                       tool toolChange: (inout ToolStyles) -> Void) {
        if session.selection.isEmpty {
            textEditing?.applyToNewAnnotation(change)
            toolChange(&toolStyles)
        } else if let command = AnnotationEditing.update(session.selection, in: session.document, name: name, change) {
            session.perform(command, coalescingKey: coalescing ? name : nil)
        } else {
            // No change (e.g. slider back at its starting value): drop the preview.
            session.preview = nil
        }
    }

    /// Unrecorded preview of an edit in progress (slider being dragged).
    public func previewUpdate(selection change: (inout Annotation) -> Void, tool toolChange: (inout ToolStyles) -> Void) {
        if session.selection.isEmpty {
            textEditing?.applyToNewAnnotation(change)
            toolChange(&toolStyles)
            return
        }
        guard !session.isReadOnly else { return }
        let selection = session.selection
        session.preview = session.document.annotations.map { annotation in
            guard selection.contains(annotation.id), !annotation.isLocked else { return annotation }
            var copy = annotation
            change(&copy)
            return copy
        }
    }

    /// Commits the text being edited on the canvas: call before saving, exporting, dragging or closing,
    /// otherwise the document that is read does not contain what is being typed.
    public func commitTextEditing() {
        textEditing?.finish()
    }

    /// Text shown in the panel: the one being edited, the selected one, or the tool's template.
    public var inspectedRichText: RichText {
        if let editingText { return editingText }
        if let text = inspectedAnnotation?.richText { return text }
        return tool == .callout ? toolStyles.calloutText : toolStyles.text
    }

    /// Edits the text being edited (no commands: only the end of the edit counts), or the selected texts
    /// (one command), or the tool's text template.
    public func updateText(name: String, coalescing: Bool = false, _ change: (inout RichText) -> Void) {
        if let textEditing {
            textEditing.applyToAll(change)
            return
        }
        let tool = self.tool
        update(name: name, coalescing: coalescing, selection: { annotation in
            guard var text = annotation.richText else { return }
            change(&text)
            annotation.richText = text
        }, tool: { styles in
            if tool == .callout { change(&styles.calloutText) } else { change(&styles.text) }
        })
    }

    /// Turns fill on or off only where it makes sense (shapes, steps, texts, callouts). Texts and callouts
    /// start from white, the others from the stroke color.
    public func setFill(_ on: Bool) {
        let tool = self.tool
        func fill(for kind: InspectedKind, current: Style) -> RGBA? {
            guard on else { return nil }
            return current.fill ?? (kind == .text || kind == .callout ? .white : (current.stroke ?? .accentRed))
        }
        update(name: CommandName.fill, selection: { annotation in
            let kind = InspectedKind(annotation.kind)
            guard kind.showsFill else { return }
            annotation.style.fill = fill(for: kind, current: annotation.style)
        }, tool: { styles in
            let kind = InspectedKind(tool)
            guard kind.showsFill else { return }
            var style = styles.style(for: tool)
            style.fill = fill(for: kind, current: style)
            styles.styles[tool] = style
        })
    }

    public func setEffectMode(_ mode: EffectMode) {
        update(name: CommandName.effect, selection: { $0.convertEffect(to: mode) }, tool: { $0.effectMode = mode })
    }

    /// Activates the tool for the pressed key; `false` if the key belongs to no tool.
    @discardableResult
    public func selectTool(forKey characters: String) -> Bool {
        guard !session.isReadOnly, characters.count == 1, let first = characters.first,
              let tool = EditorTool.forShortcut(first) else { return false }
        self.tool = tool
        return true
    }
}
