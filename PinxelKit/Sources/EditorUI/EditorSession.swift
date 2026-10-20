import CoreGraphics
import DocumentModel
import Foundation
import Observation
import Rendering

/// A history step, held by the actions registered in the `UndoManager`; merging of close-together commands
/// replaces the command in the box without registering a new step.
@MainActor
final class CommandBox {
    var command: any EditCommand

    init(_ command: any EditCommand) {
        self.command = command
    }
}

/// State of an editor: document, selection, preview of the current gesture, undo/redo.
@MainActor
@Observable
public final class EditorSession {
    public static let coalescingInterval: TimeInterval = 1

    public private(set) var document: PinxelDocument
    public var selection: Set<UUID> = []
    /// Annotations shown in place of the document's during a gesture (not registered).
    public var preview: [Annotation]?
    /// Canvas style shown in place of the document's while it is being adjusted (not registered).
    public var canvasStylePreview: CanvasStyle?
    public let isReadOnly: Bool

    /// Document images plus the pasted ones.
    @ObservationIgnored public let assets: AssetStore
    @ObservationIgnored public let undoManager: UndoManager
    @ObservationIgnored var now: () -> Date = { Date() }
    @ObservationIgnored private var lastBox: CommandBox?
    @ObservationIgnored private var coalescing: (key: String, date: Date)?
    /// Called when a command, undo or redo translates all objects to fit the canvas:
    /// the view shifts the scroll by the same amount, so nothing jumps on screen.
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

    /// Runs and registers a command, then fits the canvas to the content in the same undo step.
    /// With `coalescingKey`, an `UpdateAnnotations` that follows within 1 s another with the same key on the same objects
    /// is undone together with it, but only if neither moved the canvas: after a fit the coordinates
    /// of `before` are no longer those of the previous step.
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

    /// Moves the selected, unlocked annotations; close-together moves are undone together.
    public func nudge(by delta: CGSize) {
        let movable = selectedAnnotations.filter { !$0.isLocked }
        guard !movable.isEmpty else { return }
        let moved = movable.map { AnnotationGeometry.moved($0, by: delta) }
        perform(UpdateAnnotations(name: CommandName.move, before: movable, after: moved), coalescingKey: "nudge")
    }

    /// To call on every save: the next edit becomes a new step, so the document
    /// shows as modified again instead of merging into an already saved step.
    public func breakCoalescing() {
        lastBox = nil
        coalescing = nil
    }

    /// Replaces the document (Revert, Versions, file changed on disk): the history is reset.
    public func replaceDocument(_ newDocument: PinxelDocument) {
        undoManager.removeAllActions(withTarget: self)
        document = newDocument
        finishHistoryStep()
        selection = []
        canvasStylePreview = nil
    }

    private func registerUndo(_ box: CommandBox) {
        // The UndoManager does not retain the target: it is the session; the box is retained by the closure.
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
