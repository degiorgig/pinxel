import AppKit
import CaptureKit

/// Borderless window that can receive the keyboard.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OverlayController {
    private(set) var model: SelectionModel
    private let snapshot: CaptureSnapshot
    private var windows: [OverlayWindow] = []
    private var views: [SelectionView] = []
    private var continuation: CheckedContinuation<SelectionResult, Never>?

    init(snapshot: CaptureSnapshot, mode: CaptureMode) {
        self.snapshot = snapshot
        model = SelectionModel(mode: mode, windows: snapshot.windows, displays: snapshot.displays.map(\.info))
    }

    func run() async -> SelectionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    /// Modifies the model, redraws and, if there is a result, closes the overlay.
    func update(_ change: (inout SelectionModel) -> SelectionResult?) {
        let result = change(&model)
        views.forEach { $0.needsDisplay = true }
        if let result { finish(result) }
    }

    private func present() {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = snapshot.displays.first(where: { $0.info.id == number.uint32Value }) else { continue }
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = .black
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let view = SelectionView(display: display, controller: self)
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            windows.append(window)
            views.append(view)
        }
        guard !windows.isEmpty else {
            finish(.cancelled)
            return
        }
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.frame.contains(mouse) } ?? windows[0]
        windows.forEach { $0.orderFrontRegardless() }
        keyWindow.makeKeyAndOrderFront(nil)
        keyWindow.makeFirstResponder(keyWindow.contentView)
        let primary = NSScreen.screens.first?.frame.height ?? 0
        update { model in
            model.mouseMoved(to: ScreenGeometry.topLeft(fromAppKit: CGRect(origin: mouse, size: .zero), primaryHeight: primary).origin)
            return nil
        }
        NSCursor.crosshair.push()
    }

    private func finish(_ result: SelectionResult) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        continuation.resume(returning: result)
    }
}
