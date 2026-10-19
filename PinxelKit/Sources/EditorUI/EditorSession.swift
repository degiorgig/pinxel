import CoreGraphics
import DocumentModel
import Foundation
import Observation
import Rendering

/// Un passo della cronologia, trattenuto dalle azioni registrate nell'`UndoManager`; la fusione dei comandi
/// ravvicinati sostituisce il comando nella scatola senza registrare un nuovo passo.
@MainActor
final class CommandBox {
    var command: any EditCommand

    init(_ command: any EditCommand) {
        self.command = command
    }
}

/// Stato di un editor: documento, selezione, anteprima del gesto in corso, annulla/ripeti.
@MainActor
@Observable
public final class EditorSession {
    public static let coalescingInterval: TimeInterval = 1

    public private(set) var document: PinxelDocument
    public var selection: Set<UUID> = []
    /// Annotazioni mostrate al posto di quelle del documento durante un gesto (non registrate).
    public var preview: [Annotation]?
    /// Stile della tela mostrato al posto di quello del documento mentre lo si regola (non registrato).
    public var canvasStylePreview: CanvasStyle?
    public let isReadOnly: Bool

    /// Immagini del documento più quelle incollate.
    @ObservationIgnored public let assets: AssetStore
    @ObservationIgnored public let undoManager: UndoManager
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored private var lastBox: CommandBox?
    @ObservationIgnored private var coalescing: (key: String, date: Date)?
    /// Chiamata quando un comando, annulla o ripeti trasla tutti gli oggetti per adattare la tela:
    /// la vista sposta lo scorrimento della stessa quantità, così sullo schermo non salta niente.
    @ObservationIgnored public var onCanvasShift: ((CGVector) -> Void)?

    public init(document: PinxelDocument, assets: any AssetProvider, undoManager: UndoManager = UndoManager(), isReadOnly: Bool = false) {
        self.document = document
        self.assets = AssetStore(base: assets)
        self.undoManager = undoManager
        self.isReadOnly = isReadOnly
    }

    public var displayedAnnotations: [Annotation] { preview ?? document.annotations }

    public var selectedAnnotations: [Annotation] {
        document.annotations.filter { selection.contains($0.id) }
    }

    /// Esegue e registra un comando, poi adatta la tela al contenuto nello stesso passo di annulla.
    /// Con `coalescingKey`, un `UpdateAnnotations` che segue entro 1 s un altro con la stessa chiave sugli stessi oggetti
    /// si annulla insieme a lui, ma solo se nessuno dei due ha spostato la tela: dopo un adattamento le coordinate
    /// di `before` non sono più quelle del passo precedente.
    public func perform(_ command: any EditCommand, coalescingKey: String? = nil) {
        guard !isReadOnly else { return }
        preview = nil
        if let key = coalescingKey, let box = lastBox, let last = coalescing, last.key == key,
           now().timeIntervalSince(last.date) < Self.coalescingInterval,
           let previous = box.command as? UpdateAnnotations,
           let next = command as? UpdateAnnotations,
           let merged = previous.merged(with: next) {
            var trial = document
            next.apply(to: &trial)
            if FitCanvas(in: trial) == nil {
                document = trial
                box.command = merged
                coalescing = (key, now())
                pruneSelection()
                return
            }
        }
        command.apply(to: &document)
        var recorded = command
        if let fit = FitCanvas(in: document) {
            fit.apply(to: &document)
            recorded = CommandGroup(name: command.name, commands: [command, fit])
        }
        let box = CommandBox(recorded)
        if undoManager.groupsByEvent {
            registerUndo(box)
        } else {
            undoManager.beginUndoGrouping()
            registerUndo(box)
            undoManager.endUndoGrouping()
        }
        lastBox = recorded is UpdateAnnotations ? box : nil
        coalescing = recorded is UpdateAnnotations ? coalescingKey.map { ($0, now()) } : nil
        pruneSelection()
        notifyShift(of: recorded, sign: 1)
    }

    /// Sposta le annotazioni selezionate e non bloccate; spostamenti ravvicinati si annullano insieme.
    public func nudge(by delta: CGSize) {
        let movable = selectedAnnotations.filter { !$0.isLocked }
        guard !movable.isEmpty else { return }
        let moved = movable.map { AnnotationGeometry.moved($0, by: delta) }
        perform(UpdateAnnotations(name: CommandName.move, before: movable, after: moved), coalescingKey: "nudge")
    }

    /// Da chiamare a ogni salvataggio: la modifica successiva diventa un passo nuovo, così il documento
    /// risulta di nuovo modificato invece di confluire in un passo già salvato.
    public func breakCoalescing() {
        lastBox = nil
        coalescing = nil
    }

    /// Sostituisce il documento (Ripristina, Versioni, file cambiato su disco): la cronologia si azzera.
    public func replaceDocument(_ newDocument: PinxelDocument) {
        undoManager.removeAllActions(withTarget: self)
        document = newDocument
        finishHistoryStep()
        selection = []
        canvasStylePreview = nil
    }

    private func registerUndo(_ box: CommandBox) {
        // L'UndoManager non trattiene il bersaglio: è la sessione; la scatola la trattiene la closure.
        undoManager.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated { session.undo(box) }
        }
        undoManager.setActionName(box.command.name)
    }

    private func undo(_ box: CommandBox) {
        box.command.revert(on: &document)
        finishHistoryStep()
        undoManager.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated { session.redo(box) }
        }
        undoManager.setActionName(box.command.name)
        notifyShift(of: box.command, sign: -1)
    }

    private func redo(_ box: CommandBox) {
        box.command.apply(to: &document)
        finishHistoryStep()
        registerUndo(box)
        notifyShift(of: box.command, sign: 1)
    }

    private func notifyShift(of command: any EditCommand, sign: Double) {
        guard let fit = (command as? CommandGroup)?.commands.compactMap({ $0 as? FitCanvas }).first, fit.offset != .zero else { return }
        onCanvasShift?(CGVector(dx: fit.offset.dx * sign, dy: fit.offset.dy * sign))
    }

    private func finishHistoryStep() {
        preview = nil
        lastBox = nil
        coalescing = nil
        pruneSelection()
    }

    private func pruneSelection() {
        let ids = Set(document.annotations.map(\.id))
        if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
    }
}
