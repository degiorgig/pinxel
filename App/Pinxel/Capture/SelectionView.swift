import AppKit
import CaptureKit

/// Draws the frozen image of a screen and the selection; translates mouse and keyboard for the model.
@MainActor
final class SelectionView: NSView {
    private let display: FrozenDisplay
    private weak var controller: OverlayController?
    private var spaceHeld = false
    private var lastDragPoint: CGPoint?

    init(display: FrozenDisplay, controller: OverlayController) {
        self.display = display
        self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: display.info.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    // MARK: Coordinates

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: display.info.frame.minX + local.x, y: display.info.frame.minY + local.y)
    }

    private func localRect(_ global: CGRect) -> CGRect {
        global.offsetBy(dx: -display.info.frame.minX, dy: -display.info.frame.minY)
    }

    // MARK: Events

    override func mouseMoved(with event: NSEvent) {
        let point = globalPoint(event)
        controller?.update { $0.mouseMoved(to: point); return nil }
    }

    override func mouseDown(with event: NSEvent) {
        let point = globalPoint(event)
        lastDragPoint = point
        controller?.update { $0.mouseDown(at: point); return nil }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = globalPoint(event)
        let square = event.modifierFlags.contains(.shift)
        if spaceHeld, let last = lastDragPoint {
            let delta = CGSize(width: point.x - last.x, height: point.y - last.y)
            controller?.update { $0.moveSelection(by: delta); return nil }
        } else {
            controller?.update { $0.mouseDragged(to: point, square: square); return nil }
        }
        lastDragPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        let point = globalPoint(event)
        lastDragPoint = nil
        controller?.update { $0.mouseUp(at: point) }
    }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let key: SelectionKey?
        switch event.keyCode {
        case 53: key = .escape
        case 36, 76: key = .enter
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        case 49:
            spaceHeld = true
            key = nil
        default: key = nil
        }
        let pixelSize = 1 / max(display.info.scale, 1)
        if let key { controller?.update { $0.key(key, shift: shift, pixelSize: pixelSize) } }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let model = controller?.model else { return }
        // Frozen image (the view is flipped, so it is drawn upright).
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(display.image, in: bounds)
        ctx.restoreGState()

        var focus: CGRect?
        if let rect = model.selectionRect {
            focus = localRect(rect)
        } else if let window = model.highlightedWindow {
            focus = localRect(window.frame)
        } else if let screen = model.highlightedDisplay, screen.id == display.info.id {
            focus = bounds
        }

        // Darken everything except the highlighted area.
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let focus { dim.addRect(focus) }
        ctx.addPath(dim)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fillPath(using: .evenOdd)

        if let focus {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(model.selectionRect == nil ? 3 : 1)
            ctx.stroke(focus.insetBy(dx: 0.5, dy: 0.5))
        }
        if let rect = model.selectionRect {
            let pixels = "\(Int((rect.width * display.info.scale).rounded())) × \(Int((rect.height * display.info.scale).rounded()))"
            drawLabel(pixels, near: CGPoint(x: localRect(rect).minX, y: localRect(rect).maxY + 6))
        }
        drawLoupe(at: model.pointer)
    }

    private func drawLabel(_ text: String, near point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(x: point.x, y: min(point.y, bounds.height - size.height - 8), width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
    }

    /// 11×11 pixel magnifier enlarged 10×, with crosshair and the color of the center pixel.
    private func drawLoupe(at global: CGPoint) {
        guard display.info.frame.insetBy(dx: -1, dy: -1).contains(global) else { return }
        let scale = display.info.scale
        let local = CGPoint(x: global.x - display.info.frame.minX, y: global.y - display.info.frame.minY)
        let centerX = Int(local.x * scale), centerY = Int(local.y * scale)
        let radius = 5
        guard let crop = display.image.cropping(to: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2 + 1, height: radius * 2 + 1)) else { return }

        let side: CGFloat = 110
        var origin = CGPoint(x: local.x + 20, y: local.y + 20)
        if origin.x + side > bounds.width { origin.x = local.x - 20 - side }
        if origin.y + side + 24 > bounds.height { origin.y = local.y - 20 - side - 24 }
        let loupe = CGRect(origin: origin, size: CGSize(width: side, height: side))

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.addEllipse(in: loupe)
        ctx.clip()
        ctx.interpolationQuality = .none
        ctx.translateBy(x: loupe.minX, y: loupe.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(crop, in: CGRect(origin: .zero, size: loupe.size))
        ctx.restoreGState()

        let cell = side / CGFloat(radius * 2 + 1)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: loupe.midX - cell / 2, y: loupe.midY - cell / 2, width: cell, height: cell))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: loupe)

        if let color = pixelColor(x: centerX, y: centerY) {
            drawLabel(String(format: "#%02X%02X%02X", color.0, color.1, color.2), near: CGPoint(x: loupe.minX, y: loupe.maxY + 4))
        }
    }

    private func pixelColor(x: Int, y: Int) -> (UInt8, UInt8, UInt8)? {
        guard x >= 0, y >= 0, x < display.image.width, y < display.image.height,
              let pixel = display.image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var data = [UInt8](repeating: 0, count: 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? (data[0], data[1], data[2]) : nil
    }
}
