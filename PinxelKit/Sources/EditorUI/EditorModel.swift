import DocumentModel
import Foundation
import Observation

/// Tipo di oggetto a cui si riferisce il pannello proprietà.
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
    /// Ritaglio e taglio non hanno colori né tratti: il pannello mostra solo le loro opzioni.
    public var showsStyleSection: Bool { showsStroke || showsFill || showsOpacity || showsShadow }
}

/// Stato della finestra dell'editor oltre al documento: strumento attivo, stili degli strumenti, pannello.
@MainActor
@Observable
public final class EditorModel {
    public let session: EditorSession
    public var tool: EditorTool = .select
    public var toolStyles = ToolStyles()
    public var isInspectorPresented = true
    /// Foglio del menu Immagine aperto sulla finestra.
    public var presentedSheet: EditorSheet?
    /// Testo in modifica sulla tela (copia osservabile per il pannello); `nil` fuori dalla modifica.
    public internal(set) var editingText: RichText?
    /// Il testo in modifica, a cui il pannello manda le sue modifiche.
    @ObservationIgnored public internal(set) weak var textEditing: (any TextEditingControl)?

    public let quickStyles: QuickStyleStore

    public init(session: EditorSession, quickStyles: QuickStyleStore = .shared) {
        self.session = session
        self.quickStyles = quickStyles
    }

    /// Lo strumento di cui il pannello mostra gli stili rapidi: quello dell'oggetto selezionato o quello attivo.
    public var quickStyleTool: EditorTool? {
        if let annotation = inspectedAnnotation { return EditorTool(kind: annotation.kind) }
        return tool.createsAnnotations ? tool : nil
    }

    /// Applica uno stile rapido agli oggetti selezionati dello stesso strumento, o allo strumento.
    public func applyQuickStyle(_ style: Style) {
        guard let target = quickStyleTool else { return }
        update(name: "Stile rapido", selection: { annotation in
            if EditorTool(kind: annotation.kind) == target { annotation.style = style }
        }, tool: { styles in
            styles.styles[target] = style
        })
    }

    /// Ritaglio e taglio lavorano sull'immagine intera: il pannello mostra le loro opzioni anche con una selezione.
    public var inspectedAnnotation: Annotation? {
        [.crop, .cutOut].contains(tool) ? nil : session.selectedAnnotations.first
    }

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
            textEditing?.applyToNewAnnotation(change)
            toolChange(&toolStyles)
        } else if let command = AnnotationEditing.update(session.selection, in: session.document, name: name, change) {
            session.perform(command, coalescingKey: coalescing ? name : nil)
        } else {
            // Nessun cambiamento (es. cursore tornato al valore di partenza): via l'anteprima.
            session.preview = nil
        }
    }

    /// Anteprima non registrata di una modifica in corso (cursore trascinato).
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

    /// Conferma il testo in modifica sulla tela: da chiamare prima di salvare, esportare, trascinare o chiudere,
    /// altrimenti il documento letto non contiene ciò che si sta scrivendo.
    public func commitTextEditing() {
        textEditing?.finish()
    }

    /// Testo mostrato nel pannello: quello in modifica, quello selezionato o il modello dello strumento.
    public var inspectedRichText: RichText {
        if let editingText { return editingText }
        if let text = inspectedAnnotation?.richText { return text }
        return tool == .callout ? toolStyles.calloutText : toolStyles.text
    }

    /// Modifica il testo in modifica (senza comandi: conta la fine della modifica), o i testi selezionati
    /// (un comando), o il modello del testo dello strumento.
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

    /// Accende o spegne il riempimento solo dove ha senso (forme, step, testi, callout). Testi e callout
    /// partono dal bianco, gli altri dal colore del tratto.
    public func setFill(_ on: Bool) {
        let tool = self.tool
        func fill(for kind: InspectedKind, current: Style) -> RGBA? {
            guard on else { return nil }
            return current.fill ?? (kind == .text || kind == .callout ? .white : (current.stroke ?? .accentRed))
        }
        update(name: "Riempimento", selection: { annotation in
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
        update(name: "Effetto", selection: { $0.convertEffect(to: mode) }, tool: { $0.effectMode = mode })
    }

    /// Attiva lo strumento del tasto premuto; `false` se il tasto non è di nessuno strumento.
    @discardableResult
    public func selectTool(forKey characters: String) -> Bool {
        guard !session.isReadOnly, characters.count == 1, let first = characters.first,
              let tool = EditorTool.forShortcut(first) else { return false }
        self.tool = tool
        return true
    }
}
