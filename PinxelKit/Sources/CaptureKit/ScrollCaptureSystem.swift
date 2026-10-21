import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Real frames via ScreenCaptureKit, excluding Pinxel's windows. Verified by the manual checklist
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
        // Excluding the whole app also covers Pinxel windows not yet listed (the frame that just appeared).
        if let own = content.applications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            filter = SCContentFilter(display: screen, excludingApplications: [own], exceptingWindows: [])
        } else {
            let own = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleIdentifier }
            filter = SCContentFilter(display: screen, excludingWindows: own)
        }
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
