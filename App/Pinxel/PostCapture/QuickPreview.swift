import AppKit
import UniformTypeIdentifiers

/// Miniatura in basso a destra per 5 s: clic apre l'editor, trascinamento esporta un PNG.
@MainActor
final class QuickPreviewController {
    private let panel: NSPanel
    private var timer: Timer?
    private let onOpen: () -> Void
    private let onExpire: () -> Void
    private var finished = false

    init(image: CGImage, scale: Double, onOpen: @escaping () -> Void, onExpire: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onExpire = onExpire
        let maxSide: CGFloat = 220
        let pointSize = NSSize(width: Double(image.width) / scale, height: Double(image.height) / scale)
        let factor = min(1, maxSide / max(pointSize.width, pointSize.height))
        let size = NSSize(width: max(pointSize.width * factor, 40), height: max(pointSize.height * factor, 40))
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = QuickPreviewView(image: image, size: size)
        view.onClick = { [weak self] in self?.complete(open: true) }
        view.onHover = { [weak self] hovering in hovering ? self?.pause() : self?.resume() }
        panel.contentView = view
    }

    /// `stackIndex` impila le anteprime una sopra l'altra.
    func show(stackIndex: Int = 0) {
        if let screen = NSScreen.main?.visibleFrame {
            let offset = CGFloat(stackIndex) * (panel.frame.height + 12)
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 20, y: screen.minY + 20 + offset))
        }
        panel.orderFrontRegardless()
        resume()
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
    }

    private func resume() {
        pause()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.complete(open: false) }
        }
    }

    private func complete(open: Bool) {
        guard !finished else { return }
        finished = true
        pause()
        panel.orderOut(nil)
        open ? onOpen() : onExpire()
    }
}

@MainActor
final class QuickPreviewView: NSView, NSDraggingSource {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private let image: CGImage
    private var dragged = false

    init(image: CGImage, size: NSSize) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspectFill
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let url = writeTemporaryPNG() else { return }
        dragged = true
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: NSImage(cgImage: image, size: bounds.size))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { onClick?() }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func writeTemporaryPNG() -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Pinxel", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Pinxel \(Int(Date().timeIntervalSince1970)).png")
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              (try? png.write(to: url)) != nil else { return nil }
        return url
    }
}
