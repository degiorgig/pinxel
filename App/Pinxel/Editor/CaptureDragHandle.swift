import AppCore
import AppKit
import EditorUI
import Rendering
import SwiftUI

/// Riquadro nell'angolo della tela: trascina l'immagine composita come file PNG nel Finder o in un'altra app (spec §9).
/// Non sta nella toolbar perché lì il trascinamento sposta la finestra. È AppKit perché il Finder vuole un file vero:
/// il PNG si scrive all'inizio del trascinamento, con il testo in corso già confermato.
struct CaptureDragHandle: View {
    let model: EditorModel

    var body: some View {
        CaptureDragSource(model: model)
            .frame(width: 36, height: 36)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .help("Trascina l'immagine in un'altra app o nel Finder")
    }
}

private struct CaptureDragSource: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> CaptureDragSourceView {
        CaptureDragSourceView(model: model)
    }

    func updateNSView(_ view: CaptureDragSourceView, context: Context) {
        view.model = model
    }
}

final class CaptureDragSourceView: NSView, NSDraggingSource {
    var model: EditorModel
    private var mouseDownEvent: NSEvent?

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Trascina l'immagine")
    }


    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { false }
    // Come nel Finder: da una finestra in secondo piano si trascina subito, senza portarla davanti.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        // Un clic senza trascinamento porta comunque la finestra davanti.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let start = down.locationInWindow, now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) >= 3 else { return }
        mouseDownEvent = nil
        guard let (url, image) = try? writePNG() else {
            NSSound.beep()
            return
        }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let preview = NSImage(cgImage: image, size: .zero)
        let factor = 96 / max(preview.size.width, preview.size.height, 1)
        let size = NSSize(width: preview.size.width * factor, height: preview.size.height * factor)
        let center = convert(down.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                              contents: preview)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    private func writePNG() throws -> (URL, CGImage) {
        model.commitTextEditing()
        let session = model.session
        let image = try DocumentRenderer().renderImage(session.document, assets: session.assets)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = FileNamer.baseName(template: FileNamer.defaultTemplate, date: session.document.metadata.captureDate)
        let url = try TemporaryFiles.uniqueURL(fileName: "\(name).png")
        try data.write(to: url)
        return (url, image)
    }
}
