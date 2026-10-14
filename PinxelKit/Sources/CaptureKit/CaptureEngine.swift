import CoreGraphics

/// Tutto ciò che serve all'overlay: immagini congelate degli schermi e finestre visibili (dalla più in primo piano).
public struct CaptureSnapshot: Sendable {
    public let displays: [FrozenDisplay]
    public let windows: [WindowInfo]

    public init(displays: [FrozenDisplay], windows: [WindowInfo]) {
        self.displays = displays
        self.windows = windows
    }

    /// Scala dello schermo che contiene il centro della finestra.
    public func scale(for window: WindowInfo) -> Double {
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        return ScreenGeometry.display(at: center, in: displays.map(\.info))?.scale
            ?? displays.map(\.info.scale).max() ?? 1
    }
}

public enum CaptureError: Error, Equatable {
    case windowNotFound
    case displayNotFound
    case emptySelection
}

@MainActor
public protocol CaptureEngine {
    func snapshot(excludingBundleIdentifier bundleIdentifier: String) async throws -> CaptureSnapshot
    func captureWindow(_ id: UInt32, includeShadow: Bool) async throws -> CGImage
}

/// Motore deterministico per test e UI test: uno schermo blu 800×600 pt a 2x con un quadrato rosso.
@MainActor
public final class FakeCaptureEngine: CaptureEngine {
    public static let windowID: UInt32 = 7
    public static let redSquare = CGRect(x: 100, y: 100, width: 200, height: 150)

    public init() {}

    public func snapshot(excludingBundleIdentifier bundleIdentifier: String) async throws -> CaptureSnapshot {
        let info = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 2)
        let window = WindowInfo(id: Self.windowID, frame: Self.redSquare, title: "Finestra finta", appName: "Finta", bundleIdentifier: "com.example.fake")
        return CaptureSnapshot(displays: [FrozenDisplay(info: info, image: Self.makeScreen())], windows: [window])
    }

    public func captureWindow(_ id: UInt32, includeShadow: Bool) async throws -> CGImage {
        guard id == Self.windowID else { throw CaptureError.windowNotFound }
        return Self.solid(width: 400, height: 300, red: 1, green: 0, blue: 0)
    }

    private static func makeScreen() -> CGImage {
        let ctx = context(width: 1600, height: 1200)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        // Il contesto ha origine in basso a sinistra: converto il quadrato (punti, in alto a sinistra) in pixel.
        let square = CGRect(x: redSquare.minX * 2, y: 1200 - redSquare.maxY * 2, width: redSquare.width * 2, height: redSquare.height * 2)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(square)
        return ctx.makeImage()!
    }

    private static func solid(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let ctx = context(width: width, height: height)
        ctx.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CaptureComposer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}
