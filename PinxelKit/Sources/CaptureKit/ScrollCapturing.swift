import CoreGraphics

/// Images of a screen rectangle, one at a time, for scrolling capture.
@MainActor
public protocol RegionFrameSource {
    /// Prepares the capture after Pinxel's windows (frame, panel) have appeared, to exclude them.
    func prepare(display: DisplayInfo) async throws
    /// `rect` in global points with origin at top left; the image is at the screen's resolution.
    func frame(of rect: CGRect, on display: DisplayInfo) async throws -> CGImage
}

public extension RegionFrameSource {
    func prepare(display: DisplayInfo) async throws {}
}
