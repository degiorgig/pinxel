import AppKit
import ApplicationServices
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Fotogrammi reali con ScreenCaptureKit, escludendo le finestre di Pinxel. Verificata dalla checklist manuale
/// (docs/manual-tests/scrolling.md).
@MainActor
public final class ScreenCaptureKitFrameSource: RegionFrameSource {
    private let bundleIdentifier: String
    private var filter: SCContentFilter?

    public init(excludingBundleIdentifier bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    public func prepare(display: DisplayInfo) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let screen = content.displays.first(where: { $0.displayID == display.id }) else { throw CaptureError.displayNotFound }
        let own = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleIdentifier }
        filter = SCContentFilter(display: screen, excludingWindows: own)
    }

    public func frame(of rect: CGRect, on display: DisplayInfo) async throws -> CGImage {
        if filter == nil { try await prepare(display: display) }
        guard let filter else { throw CaptureError.displayNotFound }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = Self.sourceRect(for: rect, on: display)
        let size = Self.pixelSize(for: rect, on: display)
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    static func sourceRect(for rect: CGRect, on display: DisplayInfo) -> CGRect {
        rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    }

    static func pixelSize(for rect: CGRect, on display: DisplayInfo) -> (width: Int, height: Int) {
        (Int((rect.width * display.scale).rounded()), Int((rect.height * display.scale).rounded()))
    }
}

/// Scorrimento con eventi di sistema in pixel; richiede il permesso Accessibilità.
@MainActor
public struct CGEventScrollDriver: ScrollDriver {
    /// Segna gli eventi di Pinxel, per distinguerli dallo scorrimento dell'utente nei monitor globali.
    public static let syntheticMarker: Int64 = 0x5069_6E78
    static let maximumChunk = 50.0

    public init() {}

    public func scroll(by points: Double, at point: CGPoint) {
        for chunk in Self.chunks(for: points) {
            // Rotella negativa: il contenuto sale, cioè si va più giù nel documento.
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                      wheel1: Int32((-chunk).rounded()), wheel2: 0, wheel3: 0) else { continue }
            event.location = point
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    static func chunks(for points: Double) -> [Double] {
        guard points != 0 else { return [] }
        let count = Int((abs(points) / maximumChunk).rounded(.up))
        return Array(repeating: points / Double(count), count: count)
    }
}

@MainActor
public protocol AccessibilityPermission {
    var isGranted: Bool { get }
    /// Mostra la richiesta di sistema.
    func request()
    func openSystemSettings()
}

@MainActor
public struct SystemAccessibilityPermission: AccessibilityPermission {
    public init() {}

    public var isGranted: Bool { AXIsProcessTrusted() }

    public func request() {
        // Chiave di kAXTrustedCheckOptionPrompt, scritta per esteso: la globale C non è concurrency-safe.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Per test e UI test.
@MainActor
public struct FixedAccessibilityPermission: AccessibilityPermission {
    public let isGranted: Bool
    public init(isGranted: Bool) { self.isGranted = isGranted }
    public func request() {}
    public func openSystemSettings() {}
}
