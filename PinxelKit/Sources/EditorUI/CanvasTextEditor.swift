import AppKit
import DocumentModel

/// Temporary `NSTextView` over a text or callout (spec §6.3). Works in document pixels:
/// the container has the box's bounds and the canvas gives it the frame in points, so zoom scales the text
/// the way the renderer scales it.
@MainActor
final class CanvasTextEditor: NSObject, NSTextViewDelegate, TextEditingControl {
    /// The request; for a new text the annotation follows style changes made while typing.
    private(set) var request: TextEditRequest
    let container = FlippedView()
    let textView = PinxelTextView(usingTextLayoutManager: false)
    /// Text box in the document; the height grows with the content, never shrinks.
    private(set) var frame: CGRect
    /// Family, size, color and alignment (without runs).
    private var template: RichText
    private let inset: Double
    /// Text rotation (radians, as in the document): the editor follows it, so you write as it is drawn.
    private let rotation: Double
    /// Typing undos stay here: in the end only a single command counts in the document.
    private let typingUndo = UndoManager()
    private var finished = false

    var onChange: ((RichText) -> Void)?
    var onFrameChange: (() -> Void)?
    /// Text, height and whether the edit ended because the text lost focus (e.g. a click elsewhere).
    var onFinish: ((RichText, Double, Bool) -> Void)?

    init(request: TextEditRequest) {
        self.request = request
        let annotation = request.annotation
        frame = annotation.textRect ?? .zero
        let text = annotation.richText ?? RichText(runs: [])
        template = text
        template.runs = []
        inset = annotation.textInset
        rotation = annotation.rotation
        super.init()
        textView.frame = CGRect(origin: .zero, size: frame.size).insetBy(dx: inset, dy: inset)
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.focusRingType = .none
        textView.setAccessibilityIdentifier("pinxel.editor.text")
        textView.textStorage?.setAttributedString(RichTextBridge.attributedString(text))
        textView.typingAttributes = RichTextBridge.attributes(template)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.delegate = self
        container.addSubview(textView)
        updateHeight()
    }

    var richText: RichText {
        RichTextBridge.richText(from: textView.attributedString(), template: template)
    }

    /// The canvas fit itself and translated the objects by `offset`: the box follows its text. A new text,
    /// not yet in the document, will be added at the translated point.
    func shift(by offset: CGVector) {
        frame = frame.offsetBy(dx: offset.dx, dy: offset.dy)
        if request.isNew {
            let dx = offset.dx, dy = offset.dy
            request.annotation = request.annotation.transformed(by: PointMapping { CGPoint(x: $0.x + dx, y: $0.y + dy) })
        }
    }

    /// Puts the container on the canvas; `convert` maps a document rectangle to view points.
    func place(in convert: (CGRect) -> CGRect) {
        // The frame is laid down upright, then rotates around its origin and comes back with its center in place.
        container.frameRotation = 0
        let target = convert(frame)
        container.frame = target
        container.bounds = CGRect(origin: .zero, size: frame.size)
        if rotation != 0, let canvas = container.superview {
            // The canvas is flipped like the document: the renderer's positive angle is clockwise here too.
            container.frameRotation = rotation * 180 / .pi
            let center = container.convert(CGPoint(x: frame.width / 2, y: frame.height / 2), to: canvas)
            container.setFrameOrigin(CGPoint(x: container.frame.origin.x + target.midX - center.x,
                                             y: container.frame.origin.y + target.midY - center.y))
        }
        textView.frame = container.bounds.insetBy(dx: inset, dy: inset)
    }

    /// Ends the edit exactly once (Esc, click outside, tool change, loss of focus).
    func finish() {
        finish(byFocusLoss: false)
    }

    private func finish(byFocusLoss: Bool) {
        guard !finished else { return }
        finished = true
        onFinish?(richText, frame.height, byFocusLoss)
    }

    /// Style change from the panel (or a quick style) while a new object is being written: it is not yet in the
    /// document, so the change goes to the object being written.
    func applyToNewAnnotation(_ change: (inout Annotation) -> Void) {
        guard request.isNew else { return }
        change(&request.annotation)
        onChange?(richText)
    }

    func applyToAll(_ change: (inout RichText) -> Void) {
        var text = richText
        change(&text)
        let selection = textView.selectedRange()
        template = text
        template.runs = []
        textView.textStorage?.setAttributedString(RichTextBridge.attributedString(text))
        textView.typingAttributes = RichTextBridge.attributes(template)
        let length = (textView.string as NSString).length
        let location = min(selection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        contentChanged()
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        contentChanged()
    }

    func textDidEndEditing(_ notification: Notification) {
        finish(byFocusLoss: true)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Esc confirms the text, like leaving edit mode in Keynote.
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) || commandSelector == #selector(NSTextView.complete(_:)) {
            finish()
            return true
        }
        return false
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        typingUndo
    }

    private func contentChanged() {
        updateHeight()
        onChange?(richText)
    }

    private func updateHeight() {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let needed = (layoutManager.usedRect(for: textContainer).height + 2 * inset).rounded(.up)
        guard needed > frame.height else { return }
        frame.size.height = needed
        onFrameChange?()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
