import AppKit
import Carbon.HIToolbox
import CaptureKit
import SwiftUI

@MainActor
protocol ScrollCapturePresenting {
    func run(_ session: ScrollCaptureSession, rect: CGRect, display: DisplayInfo, narrowed: Bool) async -> CGImage?
}

/// Frame around the area and panel beside it, while the user scrolls and the session stitches; how much is scrolled reaches the session
/// as a hint. Keys: Esc cancels, Return finishes.
@MainActor
final class ScrollCaptureController: ScrollCapturePresenting {
    private var windows: [NSWindow] = []
    private var monitors: [Any] = []
    private let keys = HotKeyCenter()

    func run(_ session: ScrollCaptureSession, rect: CGRect, display: DisplayInfo, narrowed: Bool) async -> CGImage? {
        show(session, rect: rect, display: display, narrowed: narrowed)
        defer { close() }
        return await session.run()
    }

    private func show(_ session: ScrollCaptureSession, rect: CGRect, display: DisplayInfo, narrowed: Bool) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        let border = NSWindow(contentRect: ScreenGeometry.appKit(fromTopLeft: rect.insetBy(dx: -4, dy: -4), primaryHeight: primaryHeight),
                              styleMask: .borderless, backing: .buffered, defer: false)
        border.isOpaque = false
        border.backgroundColor = .clear
        border.hasShadow = false
        border.ignoresMouseEvents = true
        border.level = .statusBar
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        border.contentView = ScrollFrameView()
        border.orderFrontRegardless()

        let hosting = NSHostingView(rootView: ScrollCapturePanel(session: session, narrowed: narrowed))
        let size = hosting.fittingSize
        let frame = ScrollCaptureGeometry.panelFrame(size: size, around: rect, in: display.frame)
        let panel = NSPanel(contentRect: ScreenGeometry.appKit(fromTopLeft: frame, primaryHeight: primaryHeight),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        windows = [border, panel]

        // Esc and Return must not reach the app underneath too (Return in a chat would send the message): as
        // global shortcuts they are consumed, with no permission and inside the sandbox.
        for (keyCode, finish) in [(UInt32(kVK_Escape), false), (UInt32(kVK_Return), true), (UInt32(kVK_ANSI_KeypadEnter), true)] {
            _ = keys.register(keyCode: keyCode, id: keyCode) { finish ? session.finish() : session.cancel() }
        }

        // How much the user scrolls over the area: decides between shifts that look identical in the images (similar rows).
        // `scrollingDeltaY` is positive toward the start of the document; trackpad inertia counts too.
        if let scroll = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { event in
            MainActor.assumeIsolated {
                guard let location = event.cgEvent?.location, rect.contains(location), event.scrollingDeltaY != 0 else { return }
                session.userScrolled(by: -event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
            }
        }) { monitors.append(scroll) }
    }

    private func close() {
        keys.unregisterAll()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }
}

/// Line around the area, 1.5 points from the captured rectangle: never in its pixels.
private final class ScrollFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 3, yRadius: 3)
        path.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
