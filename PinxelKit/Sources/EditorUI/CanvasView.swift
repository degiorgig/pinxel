import AppKit
import DocumentModel
import Observation
import Rendering

/// Azioni dei menu dell'editor, inviate alla catena dei responder.
@MainActor
@objc public protocol EditorActions {
    func zoomIn(_ sender: Any?)
    func zoomOut(_ sender: Any?)
    func zoomToFit(_ sender: Any?)
    func zoomToActualSize(_ sender: Any?)
    func bringToFront(_ sender: Any?)
    func bringForward(_ sender: Any?)
    func sendBackward(_ sender: Any?)
    func sendToBack(_ sender: Any?)
    func duplicateSelection(_ sender: Any?)
    func lockSelection(_ sender: Any?)
    func unlockSelection(_ sender: Any?)
}

/// Tela dell'editor: disegna il documento con `DocumentRenderer` e trasforma mouse e tastiera in eventi
/// per il `ToolController`.
@MainActor
public final class CanvasView: NSView, EditorActions {
    public let model: EditorModel
    let controller = ToolController()
    private(set) var viewport: Viewport
    /// Appunti di Copia/Incolla; i test ne usano uno privato.
    var pasteboard: NSPasteboard = .general

    private let renderer = DocumentRenderer()
    private var marquee: CGRect?
    /// Finché l'utente non cambia zoom o posizione, la tela segue le dimensioni della finestra.
    private var followsWindow = true
    private var spaceHeld = false
    private var panPoint: CGPoint?
    private var renderFailed = false

    static let annotationsType = NSPasteboard.PasteboardType(AnnotationClipboard.typeIdentifier)

    private var session: EditorSession { model.session }

    public init(model: EditorModel) {
        self.model = model
        viewport = Viewport(documentScale: model.session.document.scale)
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Tela")
        setAccessibilityIdentifier("pinxel.editor.canvas")
        updateAccessibilityValue()
        observeModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: Coordinate

    var canvasSize: CGSize { renderer.canvasSize(for: session.document) }
    private var padding: Double { session.document.canvasStyle.padding }
    private var viewCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    /// Punto del documento (spazio delle annotazioni) sotto un punto della vista.
    func documentPoint(fromView point: CGPoint) -> CGPoint {
        let canvas = viewport.canvasPoint(fromView: point)
        return CGPoint(x: canvas.x - padding, y: canvas.y - padding)
    }

    func viewPoint(fromDocument point: CGPoint) -> CGPoint {
        viewport.viewPoint(fromCanvas: CGPoint(x: point.x + padding, y: point.y + padding))
    }

    public override func layout() {
        super.layout()
        if followsWindow, bounds.width > 0, bounds.height > 0 {
            viewport.fit(canvasSize: canvasSize, in: bounds.size)
        }
    }

    private func observeModel() {
        withObservationTracking {
            _ = session.document
            _ = session.selection
            _ = session.preview
            _ = model.tool
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.needsDisplay = true
                self.updateAccessibilityValue()
                self.window?.invalidateCursorRects(for: self)
                self.observeModel()
            }
        }
    }

    private func updateAccessibilityValue() {
        setAccessibilityValue("Annotazioni: \(session.document.annotations.count), selezionate: \(session.selection.count)")
    }

    // MARK: Disegno

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        syncController()
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        let size = canvasSize
        let canvasRect = viewport.viewRect(fromCanvas: CGRect(origin: .zero, size: size))
        drawCheckerboard(in: canvasRect, context: ctx)

        var document = session.document
        document.annotations = session.displayedAnnotations
        ctx.saveGState()
        ctx.clip(to: canvasRect)
        ctx.interpolationQuality = viewport.zoom >= 2 ? .none : .high
        ctx.translateBy(x: viewport.origin.x, y: viewport.origin.y)
        ctx.scaleBy(x: viewport.pointsPerPixel, y: viewport.pointsPerPixel)
        // Il renderer capovolge per un contesto con origine in basso; questa vista è già capovolta.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        do {
            try renderer.render(document, assets: session.assets, in: ctx)
            renderFailed = false
        } catch {
            renderFailed = true
        }
        ctx.restoreGState()

        if renderFailed { drawMessage("Impossibile mostrare l'immagine del documento.") }
        drawSelection(in: ctx)
        if let marquee { drawMarquee(marquee, in: ctx) }
    }

    private func drawCheckerboard(in rect: CGRect, context ctx: CGContext) {
        let visible = rect.intersection(bounds)
        guard !visible.isNull, !visible.isEmpty else { return }
        let square: CGFloat = 8
        ctx.saveGState()
        ctx.clip(to: visible)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(visible)
        ctx.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
        let firstRow = Int(((visible.minY - rect.minY) / square).rounded(.down))
        let firstColumn = Int(((visible.minX - rect.minX) / square).rounded(.down))
        var row = firstRow
        while rect.minY + CGFloat(row) * square < visible.maxY {
            var column = firstColumn
            while rect.minX + CGFloat(column) * square < visible.maxX {
                if (row + column) % 2 != 0 {
                    ctx.fill(CGRect(x: rect.minX + CGFloat(column) * square, y: rect.minY + CGFloat(row) * square, width: square, height: square))
                }
                column += 1
            }
            row += 1
        }
        ctx.restoreGState()
    }

    private func drawSelection(in ctx: CGContext) {
        let selected = session.displayedAnnotations.filter { session.selection.contains($0.id) }
        guard !selected.isEmpty else { return }
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        for annotation in selected {
            let bounds = annotation.bounds
            guard !bounds.isNull else { continue }
            switch annotation.kind {
            case .arrow, .line: continue // bastano le maniglie agli estremi
            default: break
            }
            let corners = HitTesting.corners(of: bounds).map {
                viewPoint(fromDocument: $0.rotated(around: bounds.center, by: annotation.rotation))
            }
            ctx.setLineDash(phase: 0, lengths: annotation.isLocked ? [4, 3] : [])
            ctx.addLines(between: corners)
            ctx.closePath()
            ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])
        if selected.count == 1, let annotation = selected.first {
            let handles = HitTesting.handles(for: annotation, rotationOffset: controller.rotationHandleOffset)
            if let rotation = handles.first(where: { $0.handle == .rotation }), let top = handles.first(where: { $0.handle == .top }) {
                ctx.move(to: viewPoint(fromDocument: top.point))
                ctx.addLine(to: viewPoint(fromDocument: rotation.point))
                ctx.strokePath()
            }
            ctx.setFillColor(NSColor.white.cgColor)
            for (handle, point) in handles {
                let center = viewPoint(fromDocument: point)
                let rect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                if handle == .rotation {
                    ctx.fillEllipse(in: rect)
                    ctx.strokeEllipse(in: rect)
                } else {
                    ctx.fill(rect)
                    ctx.stroke(rect)
                }
            }
        }
        ctx.restoreGState()
    }

    private func drawMarquee(_ rect: CGRect, in ctx: CGContext) {
        let area = CGRect.bounding([viewPoint(fromDocument: rect.origin), viewPoint(fromDocument: CGPoint(x: rect.maxX, y: rect.maxY))])
        ctx.saveGState()
        ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
        ctx.fill(area)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(area.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
    }

    private func drawMessage(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    // MARK: Eventi

    private func syncController() {
        if controller.tool != model.tool { controller.tool = model.tool }
        controller.styles = model.toolStyles
        let pointsPerPixel = viewport.pointsPerPixel
        controller.hitTolerance = 4 / pointsPerPixel
        controller.rotationHandleOffset = 24 / pointsPerPixel
        controller.dragThreshold = 3 / pointsPerPixel
    }

    private func modifiers(of event: NSEvent) -> ToolModifiers {
        var result: ToolModifiers = []
        if event.modifierFlags.contains(.shift) { result.insert(.shift) }
        if event.modifierFlags.contains(.option) { result.insert(.option) }
        if event.modifierFlags.contains(.command) { result.insert(.command) }
        return result
    }

    func send(_ event: ToolEvent) {
        syncController()
        apply(controller.handle(event, document: session.document, selection: session.selection))
    }

    private func apply(_ result: ToolResult) {
        marquee = result.marquee
        defer { needsDisplay = true }
        guard !session.isReadOnly else {
            // Sola lettura: si può selezionare, non modificare.
            if let selection = result.selection { session.selection = selection }
            session.preview = nil
            return
        }
        session.preview = result.preview
        // Prima il comando: un oggetto nuovo deve esistere per poter essere selezionato.
        if let command = result.command { session.perform(command) }
        if let selection = result.selection { session.selection = selection }
        if let delta = result.nudge { session.nudge(by: delta) }
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if spaceHeld {
            panPoint = point
            NSCursor.closedHand.set()
            return
        }
        send(.down(documentPoint(fromView: point), modifiers(of: event), clickCount: event.clickCount))
    }

    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let last = panPoint {
            pan(by: CGSize(width: point.x - last.x, height: point.y - last.y))
            panPoint = point
            return
        }
        send(.drag(documentPoint(fromView: point), modifiers(of: event)))
    }

    public override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if panPoint != nil {
            panPoint = nil
            (spaceHeld ? NSCursor.openHand : NSCursor.arrow).set()
            return
        }
        send(.up(documentPoint(fromView: point), modifiers(of: event)))
    }

    public override func keyDown(with event: NSEvent) {
        let modifiers = modifiers(of: event)
        switch event.keyCode {
        case 51, 117: send(.key(.delete, modifiers))
        case 53: send(.key(.escape, modifiers))
        case 123: send(.key(.left, modifiers))
        case 124: send(.key(.right, modifiers))
        case 125: send(.key(.down, modifiers))
        case 126: send(.key(.up, modifiers))
        case 49:
            if !spaceHeld {
                spaceHeld = true
                NSCursor.openHand.set()
            }
        default:
            let flags = event.modifierFlags.intersection([.command, .control, .option])
            if flags.isEmpty, let characters = event.charactersIgnoringModifiers, model.selectTool(forKey: characters) { return }
            super.keyDown(with: event)
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49 else {
            super.keyUp(with: event)
            return
        }
        spaceHeld = false
        window?.invalidateCursorRects(for: self)
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: model.tool == .select ? .arrow : .crosshair)
    }

    public override func scrollWheel(with event: NSEvent) {
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        if event.modifierFlags.contains(.command) {
            let anchor = convert(event.locationInWindow, from: nil)
            setZoom(viewport.zoom * (1 + event.scrollingDeltaY * factor / 200), anchor: anchor)
        } else {
            pan(by: CGSize(width: event.scrollingDeltaX * factor, height: event.scrollingDeltaY * factor))
        }
    }

    public override func magnify(with event: NSEvent) {
        setZoom(viewport.zoom * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil))
    }

    private func setZoom(_ zoom: Double, anchor: CGPoint) {
        viewport.setZoom(zoom, anchor: anchor)
        followsWindow = false
        needsDisplay = true
    }

    private func pan(by delta: CGSize) {
        viewport.pan(by: delta)
        followsWindow = false
        needsDisplay = true
    }

    // MARK: Azioni dei menu

    @objc public func zoomIn(_ sender: Any?) {
        setZoom(Viewport.zoomLevels.first { $0 > viewport.zoom + 1e-9 } ?? Viewport.zoomRange.upperBound, anchor: viewCenter)
    }

    @objc public func zoomOut(_ sender: Any?) {
        setZoom(Viewport.zoomLevels.last { $0 < viewport.zoom - 1e-9 } ?? Viewport.zoomRange.lowerBound, anchor: viewCenter)
    }

    @objc public func zoomToFit(_ sender: Any?) {
        followsWindow = true
        viewport.fit(canvasSize: canvasSize, in: bounds.size)
        needsDisplay = true
    }

    @objc public func zoomToActualSize(_ sender: Any?) {
        followsWindow = false
        viewport.actualSize(canvasSize: canvasSize, in: bounds.size)
        needsDisplay = true
    }

    @objc public func bringToFront(_ sender: Any?) { arrange(ReorderAnnotations.bringToFront) }
    @objc public func bringForward(_ sender: Any?) { arrange(ReorderAnnotations.bringForward) }
    @objc public func sendBackward(_ sender: Any?) { arrange(ReorderAnnotations.sendBackward) }
    @objc public func sendToBack(_ sender: Any?) { arrange(ReorderAnnotations.sendToBack) }

    @objc public func duplicateSelection(_ sender: Any?) {
        let selected = session.selectedAnnotations.filter { !$0.isLocked }
        guard !selected.isEmpty, !session.isReadOnly else { return }
        let copies = AnnotationEditing.duplicates(of: selected, offset: AnnotationClipboard.pasteOffset)
        session.perform(AddAnnotations(copies, name: "Duplica"))
        session.selection = Set(copies.map(\.id))
    }

    @objc public func lockSelection(_ sender: Any?) {
        if let command = AnnotationEditing.setLocked(true, ids: session.selection, in: session.document) { session.perform(command) }
    }

    @objc public func unlockSelection(_ sender: Any?) {
        if let command = AnnotationEditing.setLocked(false, ids: session.selection, in: session.document) { session.perform(command) }
    }

    private func arrange(_ make: (Set<UUID>, PinxelDocument) -> ReorderAnnotations) {
        let ids = Set(session.selectedAnnotations.filter { !$0.isLocked }.map(\.id))
        guard !ids.isEmpty else { return }
        let command = make(ids, session.document)
        var changed = session.document
        command.apply(to: &changed)
        guard changed != session.document else { return }
        session.perform(command)
    }

    @objc public func copy(_ sender: Any?) {
        guard let image = try? renderer.renderImage(session.document, assets: session.assets) else {
            NSSound.beep()
            return
        }
        let selected = session.selectedAnnotations
        pasteboard.clearContents()
        guard !selected.isEmpty else {
            writeImage(image)
            return
        }
        if let data = try? AnnotationClipboard.encode(selected) {
            pasteboard.setData(data, forType: Self.annotationsType)
        }
        if let rect = AnnotationClipboard.cropRect(for: selected, padding: padding, canvasSize: canvasSize),
           let crop = image.cropping(to: rect) {
            writeImage(crop)
        }
    }

    @objc public func cut(_ sender: Any?) {
        copy(sender)
        delete(sender)
    }

    @objc public func paste(_ sender: Any?) {
        guard !session.isReadOnly, let data = pasteboard.data(forType: Self.annotationsType),
              let annotations = try? AnnotationClipboard.decode(data) else {
            NSSound.beep()
            return
        }
        let copies = AnnotationClipboard.prepareForPaste(annotations)
        guard !copies.isEmpty else { return }
        session.perform(AddAnnotations(copies, name: "Incolla"))
        session.selection = Set(copies.map(\.id))
    }

    @objc public func delete(_ sender: Any?) {
        send(.key(.delete, []))
    }

    public override func selectAll(_ sender: Any?) {
        session.selection = Set(session.document.annotations.map(\.id))
    }

    private func writeImage(_ image: CGImage) {
        let representation = NSBitmapImageRep(cgImage: image)
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = representation.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
