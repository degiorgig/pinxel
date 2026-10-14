import CoreGraphics
import DocumentModel
import Foundation

public struct ToolModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = ToolModifiers(rawValue: 1)
    public static let option = ToolModifiers(rawValue: 2)
    public static let command = ToolModifiers(rawValue: 4)
}

public enum ToolKey: Sendable {
    case delete, escape, left, right, up, down
}

/// Eventi astratti in coordinate del documento.
public enum ToolEvent: Sendable {
    case down(CGPoint, ToolModifiers, clickCount: Int)
    case drag(CGPoint, ToolModifiers)
    case up(CGPoint, ToolModifiers)
    case key(ToolKey, ToolModifiers)
}

public struct ToolResult {
    /// Annotazioni da mostrare al posto del documento; `nil` = mostra il documento.
    public var preview: [Annotation]?
    public var command: (any EditCommand)?
    /// Nuova selezione; `nil` = invariata.
    public var selection: Set<UUID>?
    public var marquee: CGRect?
    public var nudge: CGSize?

    public init(preview: [Annotation]? = nil, command: (any EditCommand)? = nil, selection: Set<UUID>? = nil,
                marquee: CGRect? = nil, nudge: CGSize? = nil) {
        self.preview = preview
        self.command = command
        self.selection = selection
        self.marquee = marquee
        self.nudge = nudge
    }
}

/// Macchina a stati degli strumenti: riceve eventi in coordinate del documento e restituisce anteprime
/// e comandi. Non conosce viste né finestre (spec §6.3).
public final class ToolController {
    public var tool: EditorTool = .select {
        didSet { if tool != oldValue { gesture = .idle } }
    }
    public var styles = ToolStyles()
    /// Distanze in pixel del documento; il canvas le aggiorna con lo zoom.
    public var hitTolerance: Double = 4
    public var rotationHandleOffset: Double = 30
    public var dragThreshold: Double = 3
    var makeID: () -> UUID = { UUID() }

    private enum Gesture {
        case idle
        case marquee(start: CGPoint, base: Set<UUID>)
        case move(start: CGPoint, originals: [Annotation], copyIDs: [UUID]?, started: Bool)
        /// `grab`: distanza fra la maniglia e il punto premuto, mantenuta per tutto il gesto.
        case resize(Handle, original: Annotation, start: CGPoint, grab: CGSize, started: Bool)
        case rotate(original: Annotation, start: CGPoint, grab: CGSize, started: Bool)
        case create(start: CGPoint, id: UUID, points: [CGPoint])
    }

    private var gesture: Gesture = .idle

    public init() {}

    public var isGestureActive: Bool {
        if case .idle = gesture { return false }
        return true
    }

    public func handle(_ event: ToolEvent, document: PinxelDocument, selection: Set<UUID>) -> ToolResult {
        if case .key(let key, let modifiers) = event {
            return handleKey(key, modifiers, document: document, selection: selection)
        }
        return tool == .select
            ? handleSelect(event, document: document, selection: selection)
            : handleCreate(event, document: document)
    }

    // MARK: Tastiera

    private func handleKey(_ key: ToolKey, _ modifiers: ToolModifiers, document: PinxelDocument, selection: Set<UUID>) -> ToolResult {
        let step: Double = modifiers.contains(.shift) ? 10 : 1
        switch key {
        case .escape:
            if isGestureActive {
                gesture = .idle
                return ToolResult()
            }
            return ToolResult(selection: [])
        case .delete:
            let ids = Set(document.annotations.filter { selection.contains($0.id) && !$0.isLocked }.map(\.id))
            guard !ids.isEmpty else { return ToolResult() }
            return ToolResult(command: DeleteAnnotations(ids: ids, in: document))
        case .left: return ToolResult(nudge: CGSize(width: -step, height: 0))
        case .right: return ToolResult(nudge: CGSize(width: step, height: 0))
        case .up: return ToolResult(nudge: CGSize(width: 0, height: -step))
        case .down: return ToolResult(nudge: CGSize(width: 0, height: step))
        }
    }

    // MARK: Selezione

    private func handleSelect(_ event: ToolEvent, document: PinxelDocument, selection: Set<UUID>) -> ToolResult {
        let annotations = document.annotations
        switch event {
        case .down(let point, let modifiers, _):
            if selection.count == 1, let selected = annotations.first(where: { selection.contains($0.id) }),
               let handle = HitTesting.handle(at: point, for: selected, tolerance: hitTolerance, rotationOffset: rotationHandleOffset),
               let handlePoint = HitTesting.handles(for: selected, rotationOffset: rotationHandleOffset).first(where: { $0.handle == handle })?.point {
                let grab = CGSize(width: handlePoint.x - point.x, height: handlePoint.y - point.y)
                gesture = handle == .rotation
                    ? .rotate(original: selected, start: point, grab: grab, started: false)
                    : .resize(handle, original: selected, start: point, grab: grab, started: false)
                return ToolResult()
            }
            if let hit = HitTesting.annotation(at: point, in: annotations, tolerance: hitTolerance) {
                var newSelection = selection
                if modifiers.contains(.shift) {
                    if newSelection.contains(hit.id) { newSelection.remove(hit.id) } else { newSelection.insert(hit.id) }
                } else if !newSelection.contains(hit.id) {
                    newSelection = [hit.id]
                }
                let movable = annotations.filter { newSelection.contains($0.id) && !$0.isLocked }
                if newSelection.contains(hit.id), !movable.isEmpty {
                    let copies = modifiers.contains(.option) ? movable.map { _ in makeID() } : nil
                    gesture = .move(start: point, originals: movable, copyIDs: copies, started: false)
                } else {
                    gesture = .idle
                }
                return ToolResult(selection: newSelection)
            }
            let base = modifiers.contains(.shift) ? selection : []
            gesture = .marquee(start: point, base: base)
            return ToolResult(selection: base)

        case .drag(let point, let modifiers):
            switch gesture {
            case .marquee(let start, let base):
                let rect = CGRect.bounding([start, point])
                return ToolResult(selection: base.union(HitTesting.ids(intersecting: rect, in: annotations)), marquee: rect)
            case .move(let start, let originals, let copyIDs, let started):
                let delta = constrainedDelta(from: start, to: point, modifiers)
                guard started || hypot(point.x - start.x, point.y - start.y) >= dragThreshold else { return ToolResult() }
                gesture = .move(start: start, originals: originals, copyIDs: copyIDs, started: true)
                return ToolResult(preview: movedPreview(originals, copyIDs: copyIDs, delta: delta, in: annotations))
            case .resize(let handle, let original, let start, let grab, let started):
                guard started || start.distance(to: point) >= dragThreshold else { return ToolResult() }
                gesture = .resize(handle, original: original, start: start, grab: grab, started: true)
                let resized = AnnotationGeometry.resized(original, handle: handle, to: point.offset(by: grab), keepAspect: modifiers.contains(.shift))
                return ToolResult(preview: replacing([resized], in: annotations))
            case .rotate(let original, let start, let grab, let started):
                guard started || start.distance(to: point) >= dragThreshold else { return ToolResult() }
                gesture = .rotate(original: original, start: start, grab: grab, started: true)
                let rotated = AnnotationGeometry.rotated(original, pointer: point.offset(by: grab), snap: modifiers.contains(.shift))
                return ToolResult(preview: replacing([rotated], in: annotations))
            case .idle, .create:
                return ToolResult()
            }

        case .up(let point, let modifiers):
            defer { gesture = .idle }
            switch gesture {
            case .marquee(let start, let base):
                let rect = CGRect.bounding([start, point])
                return ToolResult(selection: base.union(HitTesting.ids(intersecting: rect, in: annotations)))
            case .move(let start, let originals, let copyIDs, let started):
                guard started else { return ToolResult() }
                let delta = constrainedDelta(from: start, to: point, modifiers)
                let after = originals.map { AnnotationGeometry.moved($0, by: delta) }
                if let copyIDs {
                    let copies = zip(after, copyIDs).map { moved, id in
                        Annotation(id: id, kind: moved.kind, style: moved.style, rotation: moved.rotation, isLocked: false)
                    }
                    return ToolResult(command: AddAnnotations(copies, name: "Duplica"), selection: Set(copyIDs))
                }
                return ToolResult(command: UpdateAnnotations(name: "Sposta", before: originals, after: after))
            case .resize(let handle, let original, let start, let grab, let started):
                // Un clic su una maniglia, senza trascinare, non modifica nulla.
                guard started || start.distance(to: point) >= dragThreshold else { return ToolResult() }
                let after = AnnotationGeometry.resized(original, handle: handle, to: point.offset(by: grab), keepAspect: modifiers.contains(.shift))
                guard after != original else { return ToolResult() }
                return ToolResult(command: UpdateAnnotations(name: "Ridimensiona", before: [original], after: [after]))
            case .rotate(let original, let start, let grab, let started):
                guard started || start.distance(to: point) >= dragThreshold else { return ToolResult() }
                let after = AnnotationGeometry.rotated(original, pointer: point.offset(by: grab), snap: modifiers.contains(.shift))
                guard after != original else { return ToolResult() }
                return ToolResult(command: UpdateAnnotations(name: "Ruota", before: [original], after: [after]))
            case .idle, .create:
                return ToolResult()
            }

        case .key:
            return ToolResult()
        }
    }

    // MARK: Creazione

    private func handleCreate(_ event: ToolEvent, document: PinxelDocument) -> ToolResult {
        let annotations = document.annotations
        switch event {
        case .down(let point, let modifiers, _):
            let id = makeID()
            gesture = .create(start: point, id: id, points: [point])
            // Lo step compare subito sotto il puntatore.
            guard let annotation = makeAnnotation(id: id, start: point, end: point, points: [point], modifiers: modifiers) else {
                return ToolResult()
            }
            return ToolResult(preview: annotations + [annotation])

        case .drag(let point, let modifiers):
            guard case .create(let start, let id, var points) = gesture else { return ToolResult() }
            if let last = points.last, last.distance(to: point) >= 1 { points.append(point) }
            gesture = .create(start: start, id: id, points: points)
            guard let annotation = makeAnnotation(id: id, start: start, end: point, points: points, modifiers: modifiers) else {
                return ToolResult()
            }
            return ToolResult(preview: annotations + [annotation])

        case .up(let point, let modifiers):
            guard case .create(let start, let id, var points) = gesture else { return ToolResult() }
            gesture = .idle
            if let last = points.last, last.distance(to: point) >= 1 { points.append(point) }
            guard let annotation = makeAnnotation(id: id, start: start, end: point, points: points, modifiers: modifiers) else {
                return ToolResult()
            }
            return ToolResult(command: AddAnnotations([annotation], name: "Aggiungi \(tool.title.lowercased())"), selection: [id])

        case .key:
            return ToolResult()
        }
    }

    private func makeAnnotation(id: UUID, start: CGPoint, end: CGPoint, points: [CGPoint], modifiers: ToolModifiers) -> Annotation? {
        let style = styles.style(for: tool)
        switch tool {
        case .arrow, .line:
            let target = modifiers.contains(.shift) ? AnnotationGeometry.constrained45(from: start, to: end) : end
            guard start.distance(to: target) >= dragThreshold else { return nil }
            let line = LineGeometry(start: start, end: target)
            let kind: Annotation.Kind = tool == .arrow
                ? .arrow(ArrowData(line: line, heads: styles.arrowHeads))
                : .line(LineData(line: line))
            return Annotation(id: id, kind: kind, style: style)
        case .shape, .blur:
            let corner = modifiers.contains(.shift) ? AnnotationGeometry.squared(from: start, to: end) : end
            let rect = CGRect.bounding([start, corner])
            guard rect.width >= dragThreshold, rect.height >= dragThreshold else { return nil }
            if tool == .shape {
                return Annotation(id: id, kind: .shape(ShapeData(rect: rect, shape: styles.shapeType)), style: style)
            }
            let kind: Annotation.Kind = styles.effectMode == .blur
                ? .blur(BlurData(rect: rect, radius: styles.effectAmount))
                : .pixelate(PixelateData(rect: rect, blockSize: styles.effectAmount))
            return Annotation(id: id, kind: kind, style: style)
        case .pen, .highlight:
            guard points.count >= 2 else { return nil }
            let path = PathGeometry(points: points)
            let kind: Annotation.Kind = tool == .pen ? .pen(PenData(path: path)) : .highlight(HighlightData(path: path))
            return Annotation(id: id, kind: kind, style: style)
        case .step:
            let label = StepLabel(sequence: styles.stepSequence)
            return Annotation(id: id, kind: .step(StepData(center: end, diameter: styles.stepDiameter, label: label)), style: style)
        case .select:
            return nil
        }
    }

    // MARK: Aiuti

    private func constrainedDelta(from start: CGPoint, to point: CGPoint, _ modifiers: ToolModifiers) -> CGSize {
        var delta = CGSize(width: point.x - start.x, height: point.y - start.y)
        if modifiers.contains(.shift) {
            if abs(delta.width) >= abs(delta.height) { delta.height = 0 } else { delta.width = 0 }
        }
        return delta
    }

    private func movedPreview(_ originals: [Annotation], copyIDs: [UUID]?, delta: CGSize, in annotations: [Annotation]) -> [Annotation] {
        let moved = originals.map { AnnotationGeometry.moved($0, by: delta) }
        guard let copyIDs else { return replacing(moved, in: annotations) }
        return annotations + zip(moved, copyIDs).map { moved, id in
            Annotation(id: id, kind: moved.kind, style: moved.style, rotation: moved.rotation, isLocked: false)
        }
    }

    private func replacing(_ changed: [Annotation], in annotations: [Annotation]) -> [Annotation] {
        let byID = Dictionary(changed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return annotations.map { byID[$0.id] ?? $0 }
    }
}
