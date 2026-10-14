import AppKit
import DocumentModel

/// `NSTextView` temporaneo sopra un testo o un callout (spec §6.3). Lavora in pixel del documento:
/// il contenitore ha i bounds del riquadro e la tela gli dà la cornice in punti, così lo zoom scala il testo
/// come lo scala il renderer.
@MainActor
final class CanvasTextEditor: NSObject, NSTextViewDelegate, TextEditingControl {
    let request: TextEditRequest
    let container = FlippedView()
    let textView = NSTextView(usingTextLayoutManager: false)
    /// Riquadro del testo nel documento; l'altezza cresce con il contenuto, non cala.
    private(set) var frame: CGRect
    /// Famiglia, dimensione, colore e allineamento (senza run).
    private var template: RichText
    private let inset: Double
    /// Le annullate della digitazione restano qui: alla fine conta un solo comando nel documento.
    private let typingUndo = UndoManager()
    private var finished = false

    var onChange: ((RichText) -> Void)?
    var onFrameChange: (() -> Void)?
    var onFinish: ((RichText, Double) -> Void)?

    init(request: TextEditRequest) {
        self.request = request
        let annotation = request.annotation
        frame = annotation.textRect ?? .zero
        let text = annotation.richText ?? RichText(runs: [])
        template = text
        template.runs = []
        inset = annotation.textInset
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

    /// Mette il contenitore sulla tela; `convert` porta un rettangolo del documento in punti della vista.
    func place(in convert: (CGRect) -> CGRect) {
        container.frame = convert(frame)
        container.bounds = CGRect(origin: .zero, size: frame.size)
        textView.frame = container.bounds.insetBy(dx: inset, dy: inset)
    }

    /// Chiude la modifica una volta sola (Esc, clic fuori, cambio di strumento, perdita del fuoco).
    func finish() {
        guard !finished else { return }
        finished = true
        onFinish?(richText, frame.height)
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
        finish()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Esc conferma il testo, come uscire dalla modifica in Keynote.
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
