import AppKit
import DocumentModel

/// `NSTextView` temporaneo sopra un testo o un callout (spec §6.3). Lavora in pixel del documento:
/// il contenitore ha i bounds del riquadro e la tela gli dà la cornice in punti, così lo zoom scala il testo
/// come lo scala il renderer.
@MainActor
final class CanvasTextEditor: NSObject, NSTextViewDelegate, TextEditingControl {
    /// La richiesta; per un testo nuovo l'annotazione segue le modifiche di stile fatte durante la scrittura.
    private(set) var request: TextEditRequest
    let container = FlippedView()
    let textView = PinxelTextView(usingTextLayoutManager: false)
    /// Riquadro del testo nel documento; l'altezza cresce con il contenuto, non cala.
    private(set) var frame: CGRect
    /// Famiglia, dimensione, colore e allineamento (senza run).
    private var template: RichText
    private let inset: Double
    /// Rotazione del testo (radianti, come nel documento): l'editor la segue, così si scrive com'è disegnato.
    private let rotation: Double
    /// Le annullate della digitazione restano qui: alla fine conta un solo comando nel documento.
    private let typingUndo = UndoManager()
    private var finished = false

    var onChange: ((RichText) -> Void)?
    var onFrameChange: (() -> Void)?
    /// Testo, altezza e se la modifica si è chiusa perché il testo ha perso il fuoco (es. un clic altrove).
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

    /// La tela si è adattata e ha traslato gli oggetti di `offset`: il riquadro segue il suo testo. Un testo nuovo,
    /// non ancora nel documento, verrà aggiunto nel punto traslato.
    func shift(by offset: CGVector) {
        frame = frame.offsetBy(dx: offset.dx, dy: offset.dy)
        if request.isNew {
            let dx = offset.dx, dy = offset.dy
            request.annotation = request.annotation.transformed(by: PointMapping { CGPoint(x: $0.x + dx, y: $0.y + dy) })
        }
    }

    /// Mette il contenitore sulla tela; `convert` porta un rettangolo del documento in punti della vista.
    func place(in convert: (CGRect) -> CGRect) {
        // La cornice si posa dritta, poi ruota attorno alla sua origine e torna con il centro al suo posto.
        container.frameRotation = 0
        let target = convert(frame)
        container.frame = target
        container.bounds = CGRect(origin: .zero, size: frame.size)
        if rotation != 0, let canvas = container.superview {
            // La tela è capovolta come il documento: l'angolo positivo del renderer è orario anche qui.
            container.frameRotation = rotation * 180 / .pi
            let center = container.convert(CGPoint(x: frame.width / 2, y: frame.height / 2), to: canvas)
            container.setFrameOrigin(CGPoint(x: container.frame.origin.x + target.midX - center.x,
                                             y: container.frame.origin.y + target.midY - center.y))
        }
        textView.frame = container.bounds.insetBy(dx: inset, dy: inset)
    }

    /// Chiude la modifica una volta sola (Esc, clic fuori, cambio di strumento, perdita del fuoco).
    func finish() {
        finish(byFocusLoss: false)
    }

    private func finish(byFocusLoss: Bool) {
        guard !finished else { return }
        finished = true
        onFinish?(richText, frame.height, byFocusLoss)
    }

    /// Modifica di stile dal pannello (o uno stile rapido) mentre si scrive un oggetto nuovo: non è ancora nel
    /// documento, quindi la modifica va all'oggetto in scrittura.
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
