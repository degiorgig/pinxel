import CoreGraphics

public enum CaptureMode: String, Codable, CaseIterable, Sendable {
    case area, window, screen
}

public enum SelectionResult: Equatable, Sendable {
    case area(CGRect)
    case window(WindowInfo)
    case screen(DisplayInfo)
    case cancelled
}

public enum SelectionKey: Sendable {
    case left, right, up, down, escape, enter
}

/// Stato dell'overlay di selezione, indipendente dalle finestre. Punti globali con origine in alto a sinistra.
public struct SelectionModel: Sendable {
    public enum Phase: Equatable, Sendable {
        case hovering
        case pressed(CGPoint)
        case dragging(anchor: CGPoint, current: CGPoint)
    }

    public static let dragThreshold: CGFloat = 3

    public let mode: CaptureMode
    public private(set) var phase: Phase = .hovering
    public private(set) var pointer: CGPoint = .zero
    private var squareLock = false
    private let windows: [WindowInfo]
    private let displays: [DisplayInfo]

    public init(mode: CaptureMode, windows: [WindowInfo], displays: [DisplayInfo]) {
        self.mode = mode
        self.windows = windows
        self.displays = displays
    }

    public var selectionRect: CGRect? {
        guard case .dragging(let anchor, let current) = phase else { return nil }
        return rect(from: anchor, to: current)
    }

    public var highlightedWindow: WindowInfo? {
        guard mode != .screen, selectionRect == nil else { return nil }
        return ScreenGeometry.window(at: pointer, in: windows)
    }

    public var highlightedDisplay: DisplayInfo? {
        guard mode == .screen else { return nil }
        return ScreenGeometry.display(at: pointer, in: displays)
    }

    public mutating func mouseMoved(to point: CGPoint) {
        pointer = point
    }

    public mutating func mouseDown(at point: CGPoint) {
        pointer = point
        phase = .pressed(point)
    }

    public mutating func mouseDragged(to point: CGPoint, square: Bool) {
        pointer = point
        squareLock = square
        switch phase {
        case .pressed(let anchor):
            let distance = hypot(point.x - anchor.x, point.y - anchor.y)
            if mode == .area, distance >= Self.dragThreshold {
                phase = .dragging(anchor: anchor, current: point)
            }
        case .dragging(let anchor, _):
            phase = .dragging(anchor: anchor, current: point)
        case .hovering:
            break
        }
    }

    /// Sposta l'intera selezione (Spazio tenuto premuto durante il trascinamento).
    public mutating func moveSelection(by delta: CGSize) {
        guard case .dragging(let anchor, let current) = phase else { return }
        phase = .dragging(anchor: anchor.offset(by: delta), current: current.offset(by: delta))
        pointer = pointer.offset(by: delta)
    }

    public mutating func mouseUp(at point: CGPoint) -> SelectionResult? {
        pointer = point
        switch phase {
        case .dragging:
            let rect = selectionRect
            phase = .hovering
            guard let rect, rect.width >= 1, rect.height >= 1 else { return nil }
            return .area(rect)
        case .pressed:
            phase = .hovering
            return clickResult()
        case .hovering:
            return nil
        }
    }

    public mutating func key(_ key: SelectionKey, shift: Bool) -> SelectionResult? {
        let step: CGFloat = shift ? 10 : 1
        let delta: CGSize
        switch key {
        case .escape:
            phase = .hovering
            return .cancelled
        case .enter:
            if let rect = selectionRect {
                phase = .hovering
                return rect.width >= 1 && rect.height >= 1 ? .area(rect) : nil
            }
            return clickResult()
        case .left: delta = CGSize(width: -step, height: 0)
        case .right: delta = CGSize(width: step, height: 0)
        case .up: delta = CGSize(width: 0, height: -step)
        case .down: delta = CGSize(width: 0, height: step)
        }
        if case .dragging(let anchor, let current) = phase {
            phase = .dragging(anchor: anchor, current: current.offset(by: delta))
        }
        pointer = pointer.offset(by: delta)
        return nil
    }

    private func clickResult() -> SelectionResult? {
        switch mode {
        case .area:
            if let window = ScreenGeometry.window(at: pointer, in: windows) { return .window(window) }
            return ScreenGeometry.display(at: pointer, in: displays).map { .screen($0) }
        case .window:
            return ScreenGeometry.window(at: pointer, in: windows).map { .window($0) }
        case .screen:
            return ScreenGeometry.display(at: pointer, in: displays).map { .screen($0) }
        }
    }

    private func rect(from anchor: CGPoint, to current: CGPoint) -> CGRect {
        var width = current.x - anchor.x
        var height = current.y - anchor.y
        if squareLock {
            let side = max(abs(width), abs(height))
            width = width < 0 ? -side : side
            height = height < 0 ? -side : side
        }
        return CGRect(x: anchor.x, y: anchor.y, width: width, height: height).standardized
    }
}

private extension CGPoint {
    func offset(by delta: CGSize) -> CGPoint {
        CGPoint(x: x + delta.width, y: y + delta.height)
    }
}
