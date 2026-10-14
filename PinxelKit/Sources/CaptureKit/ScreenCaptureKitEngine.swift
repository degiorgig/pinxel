import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Cattura reale con ScreenCaptureKit. Verificata dalla checklist manuale (docs/manual-tests/capture.md).
@MainActor
public final class ScreenCaptureKitEngine: CaptureEngine {
    public init() {}

    public func snapshot(excludingBundleIdentifier bundleIdentifier: String) async throws -> CaptureSnapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleIdentifier }

        var displays: [FrozenDisplay] = []
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let scale = Double(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = Int((Double(display.width) * scale).rounded())
            configuration.height = Int((Double(display.height) * scale).rounded())
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            displays.append(FrozenDisplay(info: DisplayInfo(id: display.displayID, frame: display.frame, scale: scale), image: image))
        }

        let rank = Dictionary(Self.frontToBackWindowIDs().enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let windows = content.windows
            .filter { window in
                window.isOnScreen && window.windowLayer == 0
                    && window.frame.width > 1 && window.frame.height > 1
                    && window.owningApplication?.bundleIdentifier != bundleIdentifier
            }
            .sorted { (rank[$0.windowID] ?? .max) < (rank[$1.windowID] ?? .max) }
            .map { window in
                WindowInfo(
                    id: window.windowID, frame: window.frame, title: window.title,
                    appName: window.owningApplication?.applicationName,
                    bundleIdentifier: window.owningApplication?.bundleIdentifier
                )
            }
        return CaptureSnapshot(displays: displays, windows: windows)
    }

    public func captureWindow(_ id: UInt32, includeShadow: Bool) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else { throw CaptureError.windowNotFound }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = Double(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsSingleWindow = !includeShadow
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// ID delle finestre sullo schermo, dalla più in primo piano.
    static func frontToBackWindowIDs() -> [UInt32] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }
}
