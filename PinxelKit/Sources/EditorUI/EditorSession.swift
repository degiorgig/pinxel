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
    public let isReadOnly: Bool

    @ObservationIgnored public let assets: any AssetProvider
    @ObservationIgnored public let undoManager: UndoManager
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored private var lastBox: CommandBox?
    @ObservationIgnored private var coalescing: (key: String, date: Date)?

    public init(document: PinxelDocument, assets: any AssetProvider, undoManager: UndoManager = UndoManager(), isReadOnly: Bool = false) {
        self.document = document
        self.assets = assets
        self.undoManager = undoManager
        self.isReadOnly = isReadOnly
    }

    public var displayedAnnotations: [Annotation] { preview ?? document.annotations }

    public var selectedAnnotations: [Annotation] {
        document.annotations.filter { selection.contains($0.id) }
    }

    /// Esegue e registra un comando. Con `coalescingKey`, un `UpdateAnnotations` che segue entro 1 s
    /// un altro con la stessa chiave sugli stessi oggetti si annulla insieme a lui.
    public func perform(_ command: any EditCommand, coalescingKey: String? = nil) {
        guard !isReadOnly else { return }
        preview = nil
        if let key = coalescingKey, let box = lastBox, let last = coalescing, last.key == key,
           now().timeIntervalSince(last.date) < Self.coalescingInterval,
           let previous = box.command as? UpdateAnnotations,
           let next = command as? UpdateAnnotations,
           let merged = previous.merged(with: next) {
            next.apply(to: &document)
            box.command = merged
            coalescing = (key, now())
            pruneSelection()
            return
        }
        command.apply(to: &document)
        let box = CommandBox(command)
        if undoManager.groupsByEvent {
            registerUndo(box)
        } else {
            undoManager.beginUndoGrouping()
            registerUndo(box)
            undoManager.endUndoGrouping()
        }
        lastBox = box
        coalescing = coalescingKey.map { ($0, now()) }
        pruneSelection()
    }

    /// Sposta le annotazioni selezionate e non bloccate; spostamenti ravvicinati si annullano insieme.
    public func nudge(by delta: CGSize) {
        let movable = selectedAnnotations.filter { !$0.isLocked }
        guard !movable.isEmpty else { return }
        let moved = movable.map { AnnotationGeometry.moved($0, by: delta) }
        perform(UpdateAnnotations(name: "Sposta", before: movable, after: moved), coalescingKey: "nudge")
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
    }

    private func redo(_ box: CommandBox) {
        box.command.apply(to: &document)
        finishHistoryStep()
        registerUndo(box)
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
