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
    case delete, escape, enter, left, right, up, down
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
    /// Apri la modifica sulla tela di questo testo o callout.
    public var editText: TextEditRequest?
    /// Passa a questo strumento (es. Selezione dopo un ritaglio).
    public var tool: EditorTool?

    public init(preview: [Annotation]? = nil, command: (any EditCommand)? = nil, selection: Set<UUID>? = nil,
                marquee: CGRect? = nil, nudge: CGSize? = nil, editText: TextEditRequest? = nil, tool: EditorTool? = nil) {
        self.preview = preview
        self.command = command
        self.selection = selection
        self.marquee = marquee
        self.nudge = nudge
        self.editText = editText
        self.tool = tool
    }
}

/// Testo o callout da modificare sulla tela. Se `isNew`, l'annotazione non è ancora nel documento:
/// viene aggiunta alla fine della modifica, solo se il testo non è vuoto.
public struct TextEditRequest: Equatable, Sendable {
    public var annotation: Annotation
    public var isNew: Bool

    public init(annotation: Annotation, isNew: Bool) {
        self.annotation = annotation
        self.isNew = isNew
    }
}

/// Macchina a stati degli strumenti: riceve eventi in coordinate del documento e restituisce anteprime
/// e comandi. Non conosce viste né finestre (spec §6.3).
public final class ToolController {
    public var tool: EditorTool = .select {
        didSet {
            guard tool != oldValue else { return }
            cancelGesture()
            cropRect = nil
        }
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
        /// Spostamento di una sola parte di una lente.
        case movePart(start: CGPoint, original: Annotation, part: MagnifierPart, started: Bool)
        case create(start: CGPoint, id: UUID, points: [CGPoint])
    }

    private var gesture: Gesture = .idle
    /// Dimensioni dell'immagine del documento dell'ultimo evento (lente, ritaglio, guide).
    private var imageSize: CGSize = .zero
    /// Riquadro del ritaglio in corso, in coordinate del documento; `nil` = tutta l'immagine.
    public private(set) var cropRect: CGRect?
    private var cropDrag: (mode: CropGeometry.DragMode, start: CGPoint, original: CGRect)?
    /// Fascia che il taglio toglierebbe, mentre la si trascina.
    public private(set) var cutPreview: CutOut?
    private var cutStart: CGPoint?

    public init() {}

    public var isGestureActive: Bool {
        if cropDrag != nil || cutStart != nil { return true }
        if case .idle = gesture { return false }
        return true
    }

    /// Interrompe il gesto in corso senza produrre comandi.
    private func cancelGesture() {
        gesture = .idle
        cropDrag = nil
        cutStart = nil
        cutPreview = nil
    }

    /// Riquadro da mostrare sopra l'immagine con lo strumento Ritaglio; `nil` con gli altri strumenti.
    public func cropOverlay(imageSize: PixelSize) -> CGRect? {
        guard tool == .crop else { return nil }
        return cropRect ?? CGRect(origin: .zero, size: imageSize.cgSize)
    }

    public func handle(_ event: ToolEvent, document: PinxelDocument, selection: Set<UUID>) -> ToolResult {
        imageSize = document.imageSize.cgSize
        if case .key(let key, let modifiers) = event {
            return handleKey(key, modifiers, document: document, selection: selection)
        }
        switch tool {
        case .select: return handleSelect(event, document: document, selection: selection)
        case .text, .callout: return handleText(event, document: document)
        case .crop: return handleCrop(event, document: document)
        case .cutOut: return handleCut(event, document: document)
        default: return handleCreate(event, document: document)
        }
    }

    // MARK: Tastiera

    private func handleKey(_ key: ToolKey, _ modifiers: ToolModifiers, document: PinxelDocument, selection: Set<UUID>) -> ToolResult {
        let step: Double = modifiers.contains(.shift) ? 10 : 1
        if tool == .crop {
            switch key {
            case .enter: return commitCrop(document: document)
            case .escape:
                cancelGesture()
                cropRect = nil
                return ToolResult(tool: .select)
            default: return ToolResult()
            }
        }
        switch key {
        case .escape:
            if isGestureActive {
                cancelGesture()
                return ToolResult()
            }
            return ToolResult(selection: [])
        case .enter:
            // Invio sul testo selezionato apre la modifica, come in Keynote.
            if tool == .select, selection.count == 1,
               let selected = document.annotations.first(where: { selection.contains($0.id) }),
               selected.richText != nil, !selected.isLocked {
                return ToolResult(editText: TextEditRequest(annotation: selected, isNew: false))
            }
            return ToolResult()
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
        case .down(let point, let modifiers, let clickCount):
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
                if clickCount >= 2, hit.richText != nil, !hit.isLocked {
                    gesture = .idle
                    return ToolResult(selection: [hit.id], editText: TextEditRequest(annotation: hit, isNew: false))
                }
                var newSelection = selection
                if modifiers.contains(.shift) {
                    if newSelection.contains(hit.id) { newSelection.remove(hit.id) } else { newSelection.insert(hit.id) }
                } else if !newSelection.contains(hit.id) {
                    newSelection = [hit.id]
                }
                let movable = annotations.filter { newSelection.contains($0.id) && !$0.isLocked }
                if newSelection.contains(hit.id), !movable.isEmpty {
                    let copies = modifiers.contains(.option) ? movable.map { _ in makeID() } : nil
                    if copies == nil, movable.count == 1, case .magnifier(let data) = movable[0].kind,
                       let part = HitTesting.magnifierPart(at: point, in: data, tolerance: hitTolerance) {
                        // Si sposta solo la parte presa: la sorgente o l'ingrandimento.
                        gesture = .movePart(start: point, original: movable[0], part: part, started: false)
                    } else {
                        gesture = .move(start: point, originals: movable, copyIDs: copies, started: false)
                    }
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
            case .movePart(let start, let original, let part, let started):
                guard started || start.distance(to: point) >= dragThreshold else { return ToolResult() }
                gesture = .movePart(start: start, original: original, part: part, started: true)
                let moved = AnnotationGeometry.moved(original, part: part, by: constrainedDelta(from: start, to: point, modifiers))
                return ToolResult(preview: replacing([moved], in: annotations))
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
            case .movePart(let start, let original, let part, let started):
                guard started else { return ToolResult() }
                let after = AnnotationGeometry.moved(original, part: part, by: constrainedDelta(from: start, to: point, modifiers))
                guard after != original else { return ToolResult() }
                return ToolResult(command: UpdateAnnotations(name: "Sposta", before: [original], after: [after]))
            case .idle, .create:
                return ToolResult()
            }

        case .key:
            return ToolResult()
        }
    }

    // MARK: Ritaglio

    private func handleCrop(_ event: ToolEvent, document: PinxelDocument) -> ToolResult {
        let image = CGRect(origin: .zero, size: document.imageSize.cgSize)
        let current = cropRect ?? image
        switch event {
        case .down(let point, _, _):
            let reach = hitTolerance * 1.5
            if let handle = Handle.boxHandles.first(where: { HitTesting.boxPoint($0, of: current).distance(to: point) <= reach }) {
                cropDrag = (.resize(handle), point, current)
            } else if cropRect != nil, current.contains(point) {
                cropDrag = (.move, point, current)
            } else {
                // Senza un riquadro scelto, trascinare sull'immagine ne disegna uno nuovo.
                cropDrag = (.new, point, current)
            }
            return ToolResult()
        case .drag(let point, let modifiers), .up(let point, let modifiers):
            guard let drag = cropDrag else { return ToolResult() }
            let rect = CropGeometry.dragged(drag.mode, from: drag.start, to: point, original: drag.original,
                                            image: image, keepAspect: modifiers.contains(.shift))
            if drag.mode != .new || (rect.width >= dragThreshold && rect.height >= dragThreshold) { cropRect = rect }
            if case .up = event { cropDrag = nil }
            return ToolResult()
        case .key:
            return ToolResult()
        }
    }

    private func commitCrop(document: PinxelDocument) -> ToolResult {
        defer {
            cropRect = nil
            cropDrag = nil
        }
        let size = document.imageSize
        guard let rect = cropRect, let pixel = CropGeometry.pixelRect(rect, imageSize: size),
              pixel != PixelRect(x: 0, y: 0, width: size.width, height: size.height) else {
            return ToolResult(tool: .select)
        }
        return ToolResult(command: ApplyImageOperation(.crop(pixel), in: document), selection: [], tool: .select)
    }

    // MARK: Taglia e ricuci

    private func handleCut(_ event: ToolEvent, document: PinxelDocument) -> ToolResult {
        switch event {
        case .down(let point, _, _):
            cutStart = point
            cutPreview = nil
            return ToolResult()
        case .drag(let point, _):
            guard let start = cutStart else { return ToolResult() }
            cutPreview = CutGeometry.cut(from: start, to: point, imageSize: document.imageSize, edge: styles.cutEdge)
            return ToolResult()
        case .up(let point, _):
            defer {
                cutStart = nil
                cutPreview = nil
            }
            guard let start = cutStart,
                  let cut = CutGeometry.cut(from: start, to: point, imageSize: document.imageSize, edge: styles.cutEdge) else {
                return ToolResult()
            }
            return ToolResult(command: ApplyImageOperation(.cutOut(cut), in: document), selection: [])
        case .key:
            return ToolResult()
        }
    }

    // MARK: Testo e callout

    private func handleText(_ event: ToolEvent, document: PinxelDocument) -> ToolResult {
        switch event {
        case .down(let point, _, _):
            if let hit = HitTesting.annotation(at: point, in: document.annotations, tolerance: hitTolerance),
               hit.richText != nil, !hit.isLocked {
                gesture = .idle
                return ToolResult(selection: [hit.id], editText: TextEditRequest(annotation: hit, isNew: false))
            }
            gesture = .create(start: point, id: makeID(), points: [point])
            return ToolResult(selection: [])
        case .drag(let point, _):
            guard case .create(let start, _, _) = gesture else { return ToolResult() }
            return ToolResult(marquee: CGRect.bounding([start, point]))
        case .up(let point, _):
            guard case .create(let start, let id, _) = gesture else { return ToolResult() }
            gesture = .idle
            return ToolResult(editText: TextEditRequest(annotation: newTextAnnotation(id: id, start: start, end: point), isNew: true))
        case .key:
            return ToolResult()
        }
    }

    /// Riquadro di un testo creato con un clic: una riga di circa dieci caratteri.
    static func defaultTextFrame(at point: CGPoint, template: RichText, callout: Bool) -> CGRect {
        let inset = callout ? 10.0 : 4.0
        let width = (template.fontSize * (callout ? 9 : 10)).rounded()
        let height = (template.fontSize * 1.3 + 2 * inset).rounded(.up)
        return CGRect(x: point.x, y: point.y, width: width, height: height)
    }

    private func newTextAnnotation(id: UUID, start: CGPoint, end: CGPoint) -> Annotation {
        let callout = tool == .callout
        let template = callout ? styles.calloutText : styles.text
        let dragged = CGRect.bounding([start, end])
        let rect = dragged.width >= dragThreshold && dragged.height >= dragThreshold
            ? dragged
            : Self.defaultTextFrame(at: start, template: template, callout: callout)
        let style = styles.style(for: tool)
        guard callout else {
            return Annotation(id: id, kind: .text(TextData(rect: rect, text: template)), style: style)
        }
        let tip = CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY + max(30, template.fontSize * 2))
        return Annotation(id: id, kind: .callout(CalloutData(rect: rect, text: template, tail: CalloutTail(tip: tip))), style: style)
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
        case .magnifier:
            let corner = modifiers.contains(.shift) ? AnnotationGeometry.squared(from: start, to: end) : end
            let source = CGRect.bounding([start, corner])
            guard source.width >= dragThreshold, source.height >= dragThreshold else { return nil }
            let target = MagnifierPlacement.target(for: source, zoom: styles.magnifierZoom, imageSize: imageSize)
            let data = MagnifierData(source: source, target: target, shape: styles.magnifierShape, showsConnector: styles.magnifierConnector)
            return Annotation(id: id, kind: .magnifier(data), style: style)
        case .text, .callout, .crop, .cutOut, .select:
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
