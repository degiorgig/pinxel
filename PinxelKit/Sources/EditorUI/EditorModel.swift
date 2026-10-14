import DocumentModel
import Foundation
import Observation

/// Tipo di oggetto a cui si riferisce il pannello proprietà.
public enum InspectedKind: Equatable, Sendable {
    case arrow, line, shape, pen, highlight, step, effect, none

    init(_ kind: Annotation.Kind) {
        switch kind {
        case .arrow: self = .arrow
        case .line: self = .line
        case .shape: self = .shape
        case .pen: self = .pen
        case .highlight: self = .highlight
        case .step: self = .step
        case .blur, .pixelate: self = .effect
        default: self = .none
        }
    }

    init(_ tool: EditorTool) {
        switch tool {
        case .select: self = .none
        case .arrow: self = .arrow
        case .line: self = .line
        case .shape: self = .shape
        case .pen: self = .pen
        case .highlight: self = .highlight
        case .step: self = .step
        case .blur: self = .effect
        }
    }

    public var showsStroke: Bool { ![.step, .effect, .none].contains(self) }
    public var showsFill: Bool { self == .shape || self == .step }
    public var showsLineWidth: Bool { showsStroke }
    public var showsDash: Bool { [.arrow, .line, .shape].contains(self) }
    public var showsOpacity: Bool { self != .effect && self != .none }
    public var showsShadow: Bool { ![.effect, .highlight, .none].contains(self) }
}

/// Stato della finestra dell'editor oltre al documento: strumento attivo, stili degli strumenti, pannello.
@MainActor
@Observable
public final class EditorModel {
    public let session: EditorSession
    public var tool: EditorTool = .select
    public var toolStyles = ToolStyles()
    public var isInspectorPresented = true

    public init(session: EditorSession) {
        self.session = session
    }

    public var inspectedAnnotation: Annotation? { session.selectedAnnotations.first }

    public var inspectedKind: InspectedKind {
        if let annotation = inspectedAnnotation { return InspectedKind(annotation.kind) }
        return InspectedKind(tool)
    }

    /// Stile della prima annotazione selezionata, altrimenti quello dello strumento attivo.
    public var inspectedStyle: Style {
        inspectedAnnotation?.style ?? toolStyles.style(for: tool)
    }

    public func setStyle<Value: Equatable>(_ keyPath: WritableKeyPath<Style, Value>, _ value: Value, coalescing: Bool = false) {
        let tool = self.tool
        update(name: "Stile", coalescing: coalescing, selection: { $0.style[keyPath: keyPath] = value }, tool: { styles in
            styles.styles[tool, default: ToolStyles.defaultStyle(for: tool)][keyPath: keyPath] = value
        })
    }

    public func previewStyle<Value: Equatable>(_ keyPath: WritableKeyPath<Style, Value>, _ value: Value) {
        let tool = self.tool
        previewUpdate(selection: { $0.style[keyPath: keyPath] = value }, tool: { styles in
            styles.styles[tool, default: ToolStyles.defaultStyle(for: tool)][keyPath: keyPath] = value
        })
    }

    /// Con una selezione modifica le annotazioni selezionate (un comando); altrimenti gli stili dello strumento.
    public func update(name: String, coalescing: Bool = false,
                       selection change: (inout Annotation) -> Void,
                       tool toolChange: (inout ToolStyles) -> Void) {
        if session.selection.isEmpty {
            toolChange(&toolStyles)
        } else if let command = AnnotationEditing.update(session.selection, in: session.document, name: name, change) {
            session.perform(command, coalescingKey: coalescing ? name : nil)
        }
    }

    /// Anteprima non registrata di una modifica in corso (cursore trascinato).
    public func previewUpdate(selection change: (inout Annotation) -> Void, tool toolChange: (inout ToolStyles) -> Void) {
        if session.selection.isEmpty {
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

    public func setEffectMode(_ mode: EffectMode) {
        update(name: "Effetto", selection: { $0.convertEffect(to: mode) }, tool: { $0.effectMode = mode })
    }

    /// Attiva lo strumento del tasto premuto; `false` se il tasto non è di nessuno strumento.
    @discardableResult
    public func selectTool(forKey characters: String) -> Bool {
        guard characters.count == 1, let first = characters.first, let tool = EditorTool.forShortcut(first) else { return false }
        self.tool = tool
        return true
    }
}
