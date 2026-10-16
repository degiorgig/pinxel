import AppKit
import CaptureKit
import SwiftUI

@MainActor
protocol ScrollCapturePresenting {
    func run(_ session: ScrollCaptureSession, rect: CGRect, display: DisplayInfo, narrowed: Bool) async -> CGImage?
}

/// Cornice attorno all'area e pannello accanto, mentre la sessione scorre e cuce. Tasti: Esc annulla, Invio finisce.
@MainActor
final class ScrollCaptureController: ScrollCapturePresenting {
    private var windows: [NSWindow] = []
    private var monitors: [Any] = []

    func run(_ session: ScrollCaptureSession, rect: CGRect, display: DisplayInfo, narrowed: Bool) async -> CGImage? {
        show(session, rect: rect, display: display, narrowed: narrowed)
        defer { close() }
        return await session.run()
    }

    private func show(_ session: ScrollCaptureSession, rect: CGRect, display: DisplayInfo, narrowed: Bool) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        let border = NSWindow(contentRect: ScreenGeometry.appKit(fromTopLeft: rect.insetBy(dx: -3, dy: -3), primaryHeight: primaryHeight),
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

        // Lo scorrimento va alla finestra sotto il puntatore: se è fuori dall'area lo si porta al centro.
        let mouse = NSEvent.mouseLocation
        if !rect.contains(CGPoint(x: mouse.x, y: primaryHeight - mouse.y)) {
            CGWarpMouseCursorPosition(CGPoint(x: rect.midX, y: rect.midY))
        }

        let keys: (NSEvent) -> Void = { event in
            switch event.keyCode {
            case 53: session.cancel()
            case 36, 76: session.finish()
            default: break
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            MainActor.assumeIsolated { keys(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            keys(event)
            return event
        }) { monitors.append(local) }
        if let scroll = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { event in
            MainActor.assumeIsolated {
                if event.cgEvent?.getIntegerValueField(.eventSourceUserData) != CGEventScrollDriver.syntheticMarker {
                    session.userDidScroll()
                }
            }
        }) { monitors.append(scroll) }
    }

    private func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }
}

/// Filo attorno all'area, appena fuori dal rettangolo catturato.
private final class ScrollFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 3, yRadius: 3)
        path.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
