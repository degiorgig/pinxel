import AppKit
import DocumentModel
import Observation
import Rendering

/// Editor menu actions, sent through the responder chain.
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
    func commitCrop(_ sender: Any?)
    func cancelCrop(_ sender: Any?)
    func pasteKeepingCanvas(_ sender: Any?)
}

/// Editor canvas: draws the document with `DocumentRenderer` and turns mouse and keyboard input into events
/// for the `ToolController`.
@MainActor
public final class CanvasView: NSView, EditorActions {
    public let model: EditorModel
    let controller = ToolController()
    private(set) var viewport: Viewport {
        didSet { if model.zoom != viewport.zoom { model.zoom = viewport.zoom } }
    }
    /// Copy/Paste pasteboard; tests use a private one.
    var pasteboard: NSPasteboard = .general

    private let renderer = DocumentRenderer()
    private var marquee: CGRect?
    private var guides: [GuideLine] = []
    /// Until the user changes zoom or position, the canvas follows the window size.
    private var followsWindow = true
    private(set) var spaceHeld = false
    /// Repeated pastes of the same pasteboard content, to offset each copy a little further.
    private var lastPaste: (changeCount: Int, count: Int)?
    private var panPoint: CGPoint?
    private var renderFailed = false
    /// Text being edited on the canvas, and the tool the edit started with.
    private(set) var textEditor: CanvasTextEditor?
    private var textEditingTool: EditorTool?
    /// The click that took focus away from the text being edited must do nothing else.
    private var swallowNextMouseDown = false

    static let annotationsType = NSPasteboard.PasteboardType(AnnotationClipboard.typeIdentifier)
    static let annotationImagesType = NSPasteboard.PasteboardType(AnnotationClipboard.imagesTypeIdentifier)

    private var session: EditorSession { model.session }

    public init(model: EditorModel) {
        self.model = model
        viewport = Viewport(documentScale: model.session.document.scale)
        super.init(frame: .zero)
        model.canvas = self
        model.zoom = viewport.zoom
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "Canvas", bundle: .module, comment: "Accessibility label of the editor canvas"))
        setAccessibilityIdentifier("pinxel.editor.canvas")
        updateAccessibilityValue()
        observeModel()
        model.session.onCanvasShift = { [weak self] offset in
            guard let self else { return }
            // From here on the canvas no longer follows the window: recentering it would make objects jump.
            self.followsWindow = false
            self.viewport.shift(byCanvas: offset)
            self.textEditor?.shift(by: offset)
            self.layoutTextEditor()
        }
        // Images dragged from the Finder, from other apps or from the library carousel.
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidLoseKey(_:)),
                                                   name: NSWindow.didResignKeyNotification, object: window)
        }
    }

    // MARK: Coordinates

    /// The document with the canvas style in preview, if it is being adjusted.
    private var displayedDocument: PinxelDocument {
        var document = session.document
        if let style = session.canvasStylePreview { document.canvasStyle = style }
        return document
    }

    var canvasSize: CGSize { renderer.canvasSize(for: displayedDocument) }
    private var padding: Double { displayedDocument.canvasStyle.padding }
    private var viewCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    /// Document point (annotation space) under a view point.
    func documentPoint(fromView point: CGPoint) -> CGPoint {
        let canvas = viewport.canvasPoint(fromView: point)
        return CGPoint(x: canvas.x - padding, y: canvas.y - padding)
    }

    func viewPoint(fromDocument point: CGPoint) -> CGPoint {
        viewport.viewPoint(fromCanvas: CGPoint(x: point.x + padding, y: point.y + padding))
    }

    public override func layout() {
        super.layout()
        if bounds.width > 0, bounds.height > 0 {
            if followsWindow {
                viewport.fit(canvasSize: canvasSize, in: bounds.size)
            } else {
                viewport.keepInView(canvasSize: canvasSize, in: bounds.size)
            }
        }
        layoutTextEditor()
    }

    private func observeModel() {
        withObservationTracking {
            _ = session.document
            _ = session.selection
            _ = session.preview
            _ = session.canvasStylePreview
            _ = model.tool
            _ = model.isPanning
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Another tool ends text editing.
                if self.textEditor != nil, self.model.tool != self.textEditingTool { self.finishTextEditing() }
                // Every change can alter the canvas: if it follows the window it is refit, otherwise it stays where it is
                // until enough of it is visible (objects do not jump).
                if self.bounds.width > 0, self.bounds.height > 0 {
                    if self.followsWindow {
                        self.viewport.fit(canvasSize: self.canvasSize, in: self.bounds.size)
                    } else {
                        self.viewport.keepInView(canvasSize: self.canvasSize, in: self.bounds.size)
                    }
                    self.layoutTextEditor()
                }
                self.needsDisplay = true
                self.updateAccessibilityValue()
                self.window?.invalidateCursorRects(for: self)
                self.observeModel()
            }
        }
    }

    private func updateAccessibilityValue() {
        let size = session.document.imageSize
        setAccessibilityValue(String(localized: "Annotations: \(session.document.annotations.count), selected: \(session.selection.count), image: \(size.width)×\(size.height)", bundle: .module, comment: "Canvas accessibility value"))
    }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        syncController()
        // The whole window is checkerboarded, anchored to the image: it follows zoom and scrolling.
        drawCheckerboard(context: ctx)

        let size = canvasSize
        let canvasRect = viewport.viewRect(fromCanvas: CGRect(origin: .zero, size: size))
        let blank = isBlank
        // A new editor is empty: no canvas border, which would already look like an image.
        if !blank { drawCanvasEdge(canvasRect, in: ctx) }

        var document = displayedDocument
        document.annotations = annotationsForDrawing()
        ctx.saveGState()
        // During a gesture an object dragged past the edge stays visible: the canvas fits on release.
        if session.preview == nil { ctx.clip(to: canvasRect) }
        ctx.interpolationQuality = viewport.zoom >= 2 ? .none : .high
        ctx.translateBy(x: viewport.origin.x, y: viewport.origin.y)
        ctx.scaleBy(x: viewport.pointsPerPixel, y: viewport.pointsPerPixel)
        // The renderer flips for a context with a bottom-left origin; this view is already flipped.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        do {
            try renderer.render(document, assets: session.assets, in: ctx)
            renderFailed = false
        } catch {
            renderFailed = true
        }
        ctx.restoreGState()

        if renderFailed { drawMessage(String(localized: "The document's image can't be shown.", bundle: .module, comment: "Canvas message")) }
        if blank, textEditor == nil { drawEmptyHint() }
        drawSelection(in: ctx)
        drawGuides(in: ctx)
        drawCropOverlay(in: ctx)
        drawCutPreview(in: ctx)
        if let marquee { drawMarquee(marquee, in: ctx) }
        if let textEditor { drawTextFrame(textEditor, in: ctx) }
    }

    /// Gray checkerboard; darker in dark mode, so it does not glare.
    private static let checkerLight = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.24, alpha: 1) : .white
    }
    private static let checkerDark = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.85, alpha: 1)
    }

    private func drawCheckerboard(context ctx: CGContext) {
        guard !bounds.isEmpty else { return }
        let square = CGFloat(viewport.checkerSquare)
        let anchor = viewport.origin
        ctx.saveGState()
        ctx.setFillColor(Self.checkerLight.cgColor)
        ctx.fill(bounds)
        ctx.setFillColor(Self.checkerDark.cgColor)
        let firstRow = Int(((bounds.minY - anchor.y) / square).rounded(.down))
        let firstColumn = Int(((bounds.minX - anchor.x) / square).rounded(.down))
        var row = firstRow
        while anchor.y + CGFloat(row) * square < bounds.maxY {
            var column = firstColumn
            while anchor.x + CGFloat(column) * square < bounds.maxX {
                if (row + column) & 1 != 0 {
                    ctx.fill(CGRect(x: anchor.x + CGFloat(column) * square, y: anchor.y + CGFloat(row) * square, width: square, height: square))
                }
                column += 1
            }
            row += 1
        }
        ctx.restoreGState()
    }

    /// A New document still untouched: no objects and the base canvas style.
    public var isBlank: Bool {
        session.document.annotations.isEmpty && session.document.canvasStyle == CanvasStyle()
    }

    private func drawEmptyHint() {
        let text = String(localized: "Paste a screenshot with \u{2318}V", bundle: .module, comment: "Hint on an empty canvas") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        let box = CGRect(x: bounds.midX - size.width / 2 - 14, y: bounds.midY - size.height / 2 - 8,
                         width: size.width + 28, height: size.height + 16).integral
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        let pill = NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2)
        pill.fill()
        NSColor.separatorColor.setStroke()
        pill.lineWidth = 0.5
        pill.stroke()
        text.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: attributes)
    }

    /// Soft shadow and thin hairline around the image: its transparent parts remain distinguishable from the background.
    private func drawCanvasEdge(_ rect: CGRect, in ctx: CGContext) {
        guard !rect.isEmpty else { return }
        ctx.saveGState()
        // The shadow falls only outside the image, so the transparency checkerboard stays visible inside.
        ctx.addRect(bounds)
        ctx.addRect(rect)
        ctx.clip(using: .evenOdd)
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 12, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(rect)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
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
            ctx.setLineDash(phase: 0, lengths: annotation.isLocked ? [4, 3] : [])
            for frame in HitTesting.selectionFrames(for: annotation) {
                let corners = HitTesting.corners(of: frame).map {
                    viewPoint(fromDocument: $0.rotated(around: bounds.center, by: annotation.rotation))
                }
                ctx.addLines(between: corners)
                ctx.closePath()
                ctx.strokePath()
            }
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

    private func drawGuides(in ctx: CGContext) {
        guard !guides.isEmpty else { return }
        ctx.saveGState()
        let path = CGMutablePath()
        for guide in guides {
            switch guide.orientation {
            case .vertical:
                let top = viewPoint(fromDocument: CGPoint(x: guide.position, y: guide.from))
                let bottom = viewPoint(fromDocument: CGPoint(x: guide.position, y: guide.to))
                let x = top.x.rounded() + 0.5
                path.move(to: CGPoint(x: x, y: top.y))
                path.addLine(to: CGPoint(x: x, y: bottom.y))
            case .horizontal:
                let start = viewPoint(fromDocument: CGPoint(x: guide.from, y: guide.position))
                let end = viewPoint(fromDocument: CGPoint(x: guide.to, y: guide.position))
                let y = start.y.rounded() + 0.5
                path.move(to: CGPoint(x: start.x, y: y))
                path.addLine(to: CGPoint(x: end.x, y: y))
            }
        }
        // Light halo under the line: the guide stays visible on any capture.
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(3)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor.systemPink.cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawCropOverlay(in ctx: CGContext) {
        let size = session.document.imageSize
        guard let rect = controller.cropOverlay(imageSize: size) else { return }
        let image = viewRect(fromDocument: CGRect(origin: .zero, size: size.cgSize))
        let crop = viewRect(fromDocument: rect)
        ctx.saveGState()
        let dim = CGMutablePath()
        dim.addRect(image)
        dim.addRect(crop)
        ctx.addPath(dim)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fillPath(using: .evenOdd)
        // Rule-of-thirds lines, as in the Photos crop.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(0.5)
        for third in 1...2 {
            let x = crop.minX + crop.width * CGFloat(third) / 3
            let y = crop.minY + crop.height * CGFloat(third) / 3
            ctx.move(to: CGPoint(x: x, y: crop.minY))
            ctx.addLine(to: CGPoint(x: x, y: crop.maxY))
            ctx.move(to: CGPoint(x: crop.minX, y: y))
            ctx.addLine(to: CGPoint(x: crop.maxX, y: y))
        }
        ctx.strokePath()
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(crop)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        for handle in Handle.boxHandles {
            let center = viewPoint(fromDocument: HitTesting.boxPoint(handle, of: rect))
            let box = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
            ctx.fill(box)
            ctx.stroke(box)
        }
        ctx.restoreGState()
        if let pixels = CropGeometry.pixelRect(rect, imageSize: size) {
            drawBadge("\(pixels.width) × \(pixels.height)", at: CGPoint(x: crop.minX, y: crop.maxY + 6))
        }
    }

    private func drawCutPreview(in ctx: CGContext) {
        guard let cut = controller.cutPreview else { return }
        let size = session.document.imageSize
        let band = cut.axis == .horizontal
            ? CGRect(x: 0, y: Double(cut.start), width: Double(size.width), height: Double(cut.length))
            : CGRect(x: Double(cut.start), y: 0, width: Double(cut.length), height: Double(size.height))
        let rect = viewRect(fromDocument: band)
        ctx.saveGState()
        ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.25).cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [5, 3])
        if cut.axis == .horizontal {
            for y in [rect.minY, rect.maxY] {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        } else {
            for x in [rect.minX, rect.maxX] {
                ctx.move(to: CGPoint(x: x, y: rect.minY))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
        drawBadge("− \(cut.length) px", at: CGPoint(x: rect.minX + 6, y: rect.minY + 6))
    }

    /// Dark label with white text (crop dimensions, cut length).
    private func drawBadge(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(x: point.x, y: point.y, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
    }

    private func drawMessage(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    // MARK: Text on the canvas

    /// Document rectangle in view points.
    func viewRect(fromDocument rect: CGRect) -> CGRect {
        let origin = viewPoint(fromDocument: rect.origin)
        return CGRect(x: origin.x, y: origin.y,
                      width: rect.width * viewport.pointsPerPixel, height: rect.height * viewport.pointsPerPixel)
    }

    func beginTextEditing(_ request: TextEditRequest) {
        finishTextEditing()
        guard !session.isReadOnly, request.annotation.richText != nil, !request.annotation.isLocked else { return }
        let editor = CanvasTextEditor(request: request)
        editor.onChange = { [weak self] text in
            self?.model.editingText = text
            self?.needsDisplay = true
        }
        editor.onFrameChange = { [weak self] in
            self?.layoutTextEditor()
            self?.needsDisplay = true
        }
        editor.onFinish = { [weak self] text, height, byFocusLoss in
            self?.endTextEditing(text: text, height: height, byFocusLoss: byFocusLoss)
        }
        textEditor = editor
        textEditingTool = model.tool
        model.textEditing = editor
        model.editingText = editor.richText
        session.selection = request.isNew ? [] : [request.annotation.id]
        addSubview(editor.container)
        layoutTextEditor()
        window?.makeFirstResponder(editor.textView)
        needsDisplay = true
    }

    func finishTextEditing() {
        textEditor?.finish()
    }

    private func endTextEditing(text: RichText, height: Double, byFocusLoss: Bool) {
        guard let editor = textEditor else { return }
        let request = editor.request
        textEditor = nil
        textEditingTool = nil
        model.textEditing = nil
        model.editingText = nil
        if let command = TextEditing.commit(request, text: text, minimumHeight: height, document: session.document) {
            if request.isNew, command is AddAnnotations, let tool = EditorTool(kind: request.annotation.kind) {
                model.quickStyles.record(request.annotation.style, for: tool)
            }
            session.perform(command)
            let id = request.annotation.id
            session.selection = session.document.annotations.contains { $0.id == id } ? [id] : []
        }
        if byFocusLoss {
            // Focus is already moving elsewhere (inside the transition the first responder is not changed and the view is not
            // removed). If it is a click on the canvas, that click must only end the edit.
            editor.container.isHidden = true
            swallowNextMouseDown = true
            DispatchQueue.main.async { [weak self] in
                editor.container.removeFromSuperview()
                self?.swallowNextMouseDown = false
            }
        } else {
            editor.container.removeFromSuperview()
            if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        }
        needsDisplay = true
    }

    private func layoutTextEditor() {
        textEditor?.place(in: viewRect(fromDocument:))
    }

    /// Annotations to draw: during editing the text is shown by the `NSTextView`, the box remains underneath.
    private func annotationsForDrawing() -> [Annotation] {
        var annotations = session.displayedAnnotations
        guard let editor = textEditor else { return annotations }
        let id = editor.request.annotation.id
        let placeholder = TextEditing.placeholder(for: editor.request, current: annotations.first { $0.id == id }, height: editor.frame.height)
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            annotations[index] = placeholder
        } else {
            annotations.append(placeholder)
        }
        return annotations
    }

    private func drawTextFrame(_ editor: CanvasTextEditor, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        // The container's corners, rotated like the text.
        let box = editor.container.bounds.insetBy(dx: -0.5, dy: -0.5)
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        ctx.addLines(between: corners.map { convert($0, from: editor.container) })
        ctx.closePath()
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: Events

    private func syncController() {
        if controller.tool != model.tool { controller.tool = model.tool }
        controller.styles = model.toolStyles
        let pointsPerPixel = viewport.pointsPerPixel
        controller.hitTolerance = 4 / pointsPerPixel
        controller.rotationHandleOffset = 24 / pointsPerPixel
        controller.dragThreshold = 3 / pointsPerPixel
        controller.snapTolerance = 6 / pointsPerPixel
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
        guides = result.guides
        defer { needsDisplay = true }
        guard !session.isReadOnly else {
            // Read-only: selection is done with the Select tool, nothing else (no ghost selections
            // from the drawing tools).
            if controller.tool == .select, let selection = result.selection { session.selection = selection }
            session.preview = nil
            return
        }
        session.preview = result.preview
        // Command first: a new object must exist in order to be selected.
        if let command = result.command {
            recordQuickStyles(command)
            session.perform(command)
        }
        if let rect = result.crop {
            applyContentEdit(CommandName.crop) { ContentEditing.cropped($0, to: rect, images: session.assets.image(for:), add: { session.assets.add($0) }) }
        }
        if let cut = result.cut {
            let canvas = session.document.imageSize
            applyContentEdit(CommandName.cutOut) { ContentEditing.cut($0, cut, canvas: canvas, images: session.assets.image(for:), add: { session.assets.add($0) }) }
        }
        if let selection = result.selection { session.selection = selection }
        if let delta = result.nudge { session.nudge(by: delta) }
        if let request = result.editText { beginTextEditing(request) }
        if let tool = result.tool { model.tool = tool }
    }

    /// A crop or cut over all the content: a single undo step (the session fits the canvas).
    private func applyContentEdit(_ name: String, _ edit: ([Annotation]) -> [Annotation]) {
        let before = session.document.annotations
        let after = edit(before)
        guard after != before else { return NSSound.beep() }
        session.perform(SetAnnotations(name: name, before: before, after: after))
    }

    /// Objects created with a tool enter that tool's quick styles.
    private func recordQuickStyles(_ command: any EditCommand) {
        guard controller.tool.createsAnnotations, let add = command as? AddAnnotations else { return }
        for annotation in add.annotations {
            if let tool = EditorTool(kind: annotation.kind) { model.quickStyles.record(annotation.style, for: tool) }
        }
    }

    public override func mouseDown(with event: NSEvent) {
        if swallowNextMouseDown {
            swallowNextMouseDown = false
            return
        }
        if textEditor != nil {
            // A click outside the text ends the edit and does nothing else.
            finishTextEditing()
            return
        }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if spaceHeld || model.isPanning {
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
            (spaceHeld || model.isPanning ? NSCursor.openHand : NSCursor.arrow).set()
            return
        }
        send(.up(documentPoint(fromView: point), modifiers(of: event)))
    }

    public override func keyDown(with event: NSEvent) {
        let modifiers = modifiers(of: event)
        switch event.keyCode {
        case 51, 117: send(.key(.delete, modifiers))
        case 53:
            if model.isPanning {
                model.isPanning = false
            } else {
                send(.key(.escape, modifiers))
            }
        case 36, 76: send(.key(.enter, modifiers))
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

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘= zooms in like ⌘+, which on US keyboards would require ⇧.
        if event.type == .keyDown, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "=" {
            zoomIn(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    public override func keyUp(with event: NSEvent) {
        guard event.keyCode == 49 else {
            super.keyUp(with: event)
            return
        }
        spaceHeld = false
        window?.invalidateCursorRects(for: self)
    }

    public override func resignFirstResponder() -> Bool {
        endSpacePan()
        return super.resignFirstResponder()
    }

    @objc private func windowDidLoseKey(_ notification: Notification) {
        endSpacePan()
    }

    /// If Space is released outside the window the keyUp does not arrive: panning ends with focus.
    private func endSpacePan() {
        guard spaceHeld || panPoint != nil else { return }
        spaceHeld = false
        panPoint = nil
        window?.invalidateCursorRects(for: self)
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: model.isPanning ? .openHand : model.tool == .select ? .arrow : .crosshair)
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
        // Like scrolling: the canvas stays where zoom puts it, only kept inside the view.
        viewport.keepInView(canvasSize: canvasSize, in: bounds.size)
        followsWindow = false
        layoutTextEditor()
        needsDisplay = true
    }

    private func pan(by delta: CGSize) {
        viewport.pan(by: delta, canvasSize: canvasSize, in: bounds.size)
        followsWindow = false
        layoutTextEditor()
        needsDisplay = true
    }

    // MARK: Menu actions

    @objc public func zoomIn(_ sender: Any?) {
        setZoom(Viewport.zoomLevels.first { $0 > viewport.zoom + 1e-9 } ?? Viewport.zoomRange.upperBound, anchor: viewCenter)
    }

    @objc public func zoomOut(_ sender: Any?) {
        setZoom(Viewport.zoomLevels.last { $0 < viewport.zoom - 1e-9 } ?? Viewport.zoomRange.lowerBound, anchor: viewCenter)
    }

    @objc public func zoomToFit(_ sender: Any?) {
        followsWindow = true
        viewport.fit(canvasSize: canvasSize, in: bounds.size)
        layoutTextEditor()
        needsDisplay = true
    }

    @objc public func zoomToActualSize(_ sender: Any?) {
        followsWindow = false
        viewport.actualSize(canvasSize: canvasSize, in: bounds.size)
        layoutTextEditor()
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
        session.perform(AddAnnotations(copies, name: CommandName.duplicate))
        session.selection = Set(copies.map(\.id))
    }

    @objc public func lockSelection(_ sender: Any?) {
        if let command = AnnotationEditing.setLocked(true, ids: session.selection, in: session.document) { session.perform(command) }
    }

    @objc public func unlockSelection(_ sender: Any?) {
        if let command = AnnotationEditing.setLocked(false, ids: session.selection, in: session.document) { session.perform(command) }
    }

    @objc public func commitCrop(_ sender: Any?) {
        send(.key(.enter, []))
    }

    @objc public func cancelCrop(_ sender: Any?) {
        send(.key(.escape, []))
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

    // MARK: Right-click menu

    /// Right-click: as in the Finder, the object under the pointer becomes the selection if it is not already part of it,
    /// then the Arrange, Duplicate, Lock and Delete commands act on that selection.
    public override func menu(for event: NSEvent) -> NSMenu? {
        guard !session.isReadOnly else { return nil }
        if textEditor != nil { finishTextEditing() }
        let point = documentPoint(fromView: convert(event.locationInWindow, from: nil))
        if let hit = HitTesting.annotation(at: point, in: session.document.annotations, tolerance: controller.hitTolerance) {
            if !session.selection.contains(hit.id) { session.selection = [hit.id] }
        } else {
            session.selection = []
        }
        return contextMenu()
    }

    private func contextMenu() -> NSMenu {
        let state = EditorMenuState(model: model)
        let menu = NSMenu(title: CommandName.arrange)
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, enabled: Bool) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
        }
        let editable = state.hasEditableSelection
        add(CommandName.bringToFront, #selector(bringToFront(_:)), enabled: editable)
        add(CommandName.bringForward, #selector(bringForward(_:)), enabled: editable)
        add(CommandName.sendBackward, #selector(sendBackward(_:)), enabled: editable)
        add(CommandName.sendToBack, #selector(sendToBack(_:)), enabled: editable)
        menu.addItem(.separator())
        add(CommandName.duplicate, #selector(duplicateSelection(_:)), enabled: editable)
        if state.hasLockedSelection && !state.hasUnlockedSelection {
            add(CommandName.unlock, #selector(unlockSelection(_:)), enabled: true)
        } else {
            add(CommandName.lock, #selector(lockSelection(_:)), enabled: state.hasUnlockedSelection)
        }
        menu.addItem(.separator())
        add(CommandName.delete, #selector(delete(_:)), enabled: editable)
        return menu
    }

    @objc public func copy(_ sender: Any?) {
        write(session.selectedAnnotations)
    }

    @objc public func cut(_ sender: Any?) {
        // Only what can be deleted is cut: locked objects stay and do not end up on the pasteboard.
        let deletable = session.selectedAnnotations.filter { !$0.isLocked }
        guard !deletable.isEmpty, !session.isReadOnly else {
            NSSound.beep()
            return
        }
        write(deletable)
        session.perform(DeleteAnnotations(ids: Set(deletable.map(\.id)), in: session.document, name: CommandName.cut))
    }

    /// Without annotations it copies the whole image; with annotations their private content plus their PNG.
    private func write(_ selected: [Annotation]) {
        guard let image = try? renderer.renderImage(session.document, assets: session.assets) else {
            NSSound.beep()
            return
        }
        pasteboard.clearContents()
        guard !selected.isEmpty else {
            writeImage(image)
            return
        }
        if let data = try? AnnotationClipboard.encode(selected) {
            pasteboard.setData(data, forType: Self.annotationsType)
        }
        let assets = session.assets
        let images = AnnotationClipboard.imageAssets(of: selected).reduce(into: [ImageAssetRef: Data]()) { images, ref in
            images[ref] = assets.pngData(for: ref)
        }
        if !images.isEmpty, let data = try? AnnotationClipboard.encodeImages(images) {
            pasteboard.setData(data, forType: Self.annotationImagesType)
        }
        if let rect = AnnotationClipboard.cropRect(for: selected, padding: padding, canvasSize: canvasSize),
           let crop = image.cropping(to: rect) {
            writeImage(crop)
        }
    }

    /// Paste: a screenshot gives the capture its dimensions, larger or smaller.
    @objc public func paste(_ sender: Any?) {
        paste(adaptCanvas: true)
    }

    /// Pastes an image over the capture without changing its dimensions (a logo, a detail).
    @objc public func pasteKeepingCanvas(_ sender: Any?) {
        paste(adaptCanvas: false)
    }

    private func paste(adaptCanvas: Bool) {
        guard !session.isReadOnly else {
            NSSound.beep()
            return
        }
        if let data = pasteboard.data(forType: Self.annotationsType), let annotations = try? AnnotationClipboard.decode(data) {
            let count = lastPaste?.changeCount == pasteboard.changeCount ? (lastPaste?.count ?? 0) + 1 : 1
            lastPaste = (pasteboard.changeCount, count)
            let assets = session.assets
            // Images pasted into another document arrive with their files.
            if let data = pasteboard.data(forType: Self.annotationImagesType), let images = try? AnnotationClipboard.decodeImages(data) {
                for (ref, png) in images { assets.add(pngData: png, as: ref) }
            }
            let copies = AnnotationClipboard.prepareForPaste(annotations, times: count, keepImage: { assets.image(for: $0) != nil })
            guard !copies.isEmpty else {
                // Only images whose file did not arrive: the PNG stays on the pasteboard.
                if !pasteImage(adaptCanvas: adaptCanvas) { NSSound.beep() }
                return
            }
            session.perform(AddAnnotations(copies, name: CommandName.paste))
            session.selection = Set(copies.map(\.id))
            return
        }
        if !pasteImage(adaptCanvas: adaptCanvas) { NSSound.beep() }
    }

    /// With `adaptCanvas` the screenshot on the pasteboard takes the place of the bottom image, keeping the annotations;
    /// otherwise it becomes an extra image above the rest (spec §5.4).
    private func pasteImage(adaptCanvas: Bool) -> Bool {
        guard adaptCanvas else {
            guard let image = NSImage(pasteboard: pasteboard) else { return false }
            return insertImage(image, centeredAt: nil, name: CommandName.pasteImage)
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let original = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              // Beyond the document limit the saved file would not reopen: it is downsized.
              let cgImage = ImagePlacement.fitting(original, maxSide: PinxelDocument.maxImageSide) else { return false }
        let document = session.document
        let placement = ImagePlacement.place(
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            imageScale: PixelDensity.scale(pixelWidth: original.width, pointWidth: image.size.width),
            documentScale: document.scale,
            center: visibleDocumentCenter(),
            imageSize: document.imageSize,
            adaptCanvas: adaptCanvas
        )
        guard let replacement = ImagePlacement.resized(cgImage, to: placement.imageSize),
              let asset = session.assets.add(replacement) else { return false }
        session.perform(ContentEditing.replacingBottomImage(in: document.annotations, asset: asset,
                                                            size: placement.imageSize.cgSize, newID: UUID()))
        // A new image in place of the capture: it is shown whole, as if just opened (even if the canvas fit
        // has just moved the view).
        followsWindow = true
        session.selection = []
        return true
    }

    /// An image dragged or pasted over the rest; `viewPoint` is the center (in view coordinates),
    /// `nil` = center of the visible part. The canvas fits the object, wherever it lands.
    @discardableResult
    public func insertImage(_ image: NSImage, centeredAt viewPoint: CGPoint?, name: String = CommandName.insertImage) -> Bool {
        guard !session.isReadOnly,
              let original = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cgImage = ImagePlacement.fitting(original, maxSide: PinxelDocument.maxImageSide) else { return false }
        let rect = ImagePlacement.centered(
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            imageScale: PixelDensity.scale(pixelWidth: original.width, pointWidth: image.size.width),
            documentScale: session.document.scale,
            center: viewPoint.map { documentPoint(fromView: $0) } ?? visibleDocumentCenter()
        )
        guard let asset = session.assets.add(cgImage) else { return false }
        let annotation = Annotation(kind: .image(PlacedImageData(rect: rect, asset: asset)), style: Style(stroke: nil, lineWidth: 0))
        session.perform(AddAnnotations([annotation], name: name))
        session.selection = [annotation.id]
        return true
    }

    // MARK: Image dragging

    private func droppedImage(_ sender: NSDraggingInfo) -> NSImage? {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first, let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(pasteboard: pasteboard)
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        !session.isReadOnly && NSImage.canInit(with: sender.draggingPasteboard) ? .copy : []
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let image = droppedImage(sender) else { return false }
        window?.makeFirstResponder(self)
        return insertImage(image, centeredAt: convert(sender.draggingLocation, from: nil))
    }

    /// Center of the visible part of the image in the window, or of the image if none of it is visible;
    /// with an empty canvas, the point under the view center.
    private func visibleDocumentCenter() -> CGPoint {
        let image = CGRect(origin: .zero, size: session.document.imageSize.cgSize)
        if image.isEmpty { return documentPoint(fromView: CGPoint(x: bounds.midX, y: bounds.midY)) }
        let visible = CGRect.bounding([documentPoint(fromView: bounds.origin), documentPoint(fromView: CGPoint(x: bounds.maxX, y: bounds.maxY))])
            .intersection(image)
        return visible.isNull || visible.isEmpty ? image.center : visible.center
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
