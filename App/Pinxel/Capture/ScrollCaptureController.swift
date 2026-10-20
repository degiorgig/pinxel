import AppKit
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
    private var keyTap: KeyTap?

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

        // Esc and Return must not reach the app underneath too (Return in a chat would send the message): with
        // Accessibility an event tap consumes them; without it, a global monitor only sees them.
        let keyTap = KeyTap { keyCode in
            switch keyCode {
            case 53: session.cancel()
            case 36, 76: session.finish()
            default: return false
            }
            return true
        }
        if keyTap.start() {
            self.keyTap = keyTap
        } else if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            MainActor.assumeIsolated { _ = keyTap.handle(Int64(event.keyCode)) }
        }) { monitors.append(global) }
        let keys: (NSEvent) -> Void = { event in _ = keyTap.handle(Int64(event.keyCode)) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            keys(event)
            return event
        }) { monitors.append(local) }

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
        keyTap?.stop()
        keyTap = nil
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

/// Event tap on keys: consumes those that `handle` handles. Requires the Accessibility permission.
@MainActor
final class KeyTap {
    private let handler: (Int64) -> Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(handler: @escaping (Int64) -> Bool) {
        self.handler = handler
    }

    /// Esc and Return without ⌘, ⌥ or ⌃: with modifiers they stay with the app (for example ⌘Return).
    func handle(_ keyCode: Int64, flags: CGEventFlags = []) -> Bool {
        guard flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty else { return false }
        return handler(keyCode)
    }

    func start() -> Bool {
        let info = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            // The tap is on the main run loop.
            let consumed = MainActor.assumeIsolated {
                let keyTap = Unmanaged<KeyTap>.fromOpaque(info).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = keyTap.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return false
                }
                return type == .keyDown && keyTap.handle(keyCode, flags: flags)
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }, userInfo: info) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }
}
