import AppCore
import AppKit
import UniformTypeIdentifiers

/// Thumbnail at bottom right for 5 s: click opens the editor, dragging exports a PNG.
@MainActor
final class QuickPreviewController {
    private let panel: NSPanel
    private var timer: Timer?
    private let onComplete: (Bool) -> Void
    private var finished = false
    var size: NSSize { panel.frame.size }

    init(image: CGImage, scale: Double, onComplete: @escaping (Bool) -> Void) {
        self.onComplete = onComplete
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

    /// Enters from the right edge.
    func show(at target: NSRect) {
        if Self.reduceMotion {
            panel.setFrame(target, display: false)
            panel.alphaValue = 0
        } else {
            panel.setFrame(target.offsetBy(dx: target.width + QuickPreviewLayout.margin, dy: 0), display: false)
        }
        panel.orderFrontRegardless()
        animate(duration: 0.3) {
            self.panel.animator().setFrame(target, display: true)
            self.panel.animator().alphaValue = 1
        }
        resume()
    }

    /// Repositions the preview when those below it disappear.
    func move(to target: NSRect) {
        guard !finished, panel.frame != target else { return }
        animate(duration: 0.3) { self.panel.animator().setFrame(target, display: true) }
    }

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func animate(duration: TimeInterval, _ changes: @escaping () -> Void, completion: (@MainActor @Sendable () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.reduceMotion ? 0.2 : duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            changes()
        }, completionHandler: { MainActor.assumeIsolated { completion?() } })
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
        onComplete(open)
        // On expiry it returns where it came from; when opened it dissolves in place.
        let exit = open || Self.reduceMotion ? panel.frame : panel.frame.offsetBy(dx: panel.frame.width + QuickPreviewLayout.margin, dy: 0)
        animate(duration: open ? 0.15 : 0.3, {
            self.panel.animator().setFrame(exit, display: true)
            self.panel.animator().alphaValue = 0
        }, completion: { [panel] in panel.orderOut(nil) })
    }
}

@MainActor
final class QuickPreviewView: NSView, NSDraggingSource {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private let image: CGImage
    private var dragged = false
    private var mouseDownLocation: NSPoint?

    init(image: CGImage, size: NSSize) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: size))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(PostCaptureAction.openEditor.title)
        setAccessibilityIdentifier("pinxel.quickPreview")
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspectFill
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func accessibilityPerformPress() -> Bool {
        guard let onClick else { return false }
        onClick()
        return true
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        dragged = false
        mouseDownLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        // A small movement during the click does not start the drag.
        guard !dragged, let start = mouseDownLocation,
              hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4,
              let url = writeTemporaryPNG() else { return }
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
        // Unique folder for each drag: two captures in the same second do not overwrite each other.
        let name = FileNamer.baseName(template: FileNamer.defaultTemplate, date: Date())
        guard let url = try? TemporaryFiles.uniqueURL(fileName: "\(name).png"),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              (try? png.write(to: url)) != nil else { return nil }
        return url
    }
}
