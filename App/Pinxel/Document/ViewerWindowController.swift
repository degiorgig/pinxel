import AppKit

/// Finestra di sola visualizzazione; nel piano 3 diventa l'editor.
@MainActor
final class ViewerWindowController: NSWindowController {
    convenience init(image: CGImage, scale: Double) {
        let size = NSSize(width: Double(image.width) / scale, height: Double(image.height) / scale)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = NSImage(cgImage: image, size: size)
        imageView.imageScaling = .scaleNone
        imageView.setAccessibilityIdentifier("pinxel.viewer.image")

        let scrollView = NSScrollView()
        scrollView.documentView = imageView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor

        let visible = NSScreen.main?.visibleFrame.size ?? size
        let contentSize = NSSize(width: min(max(size.width, 320), visible.width * 0.8),
                                 height: min(max(size.height, 240), visible.height * 0.8))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentView = scrollView
        window.center()
        self.init(window: window)
    }
}
