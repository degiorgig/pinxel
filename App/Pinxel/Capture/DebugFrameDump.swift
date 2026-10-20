import CaptureKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Debug only: with `-PinxelDebugDumpFrames <folder>` saves every frame of the scroll capture.
@MainActor
enum DebugFrameDump {
    static func wrap(_ source: any RegionFrameSource) -> any RegionFrameSource {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-PinxelDebugDumpFrames"), index + 1 < arguments.count {
            return DumpingSource(base: source, folder: URL(fileURLWithPath: arguments[index + 1]))
        }
        #endif
        return source
    }
}

#if DEBUG
@MainActor
private final class DumpingSource: RegionFrameSource {
    private let base: any RegionFrameSource
    private let folder: URL
    private var count = 0

    init(base: any RegionFrameSource, folder: URL) {
        self.base = base
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func prepare(display: DisplayInfo) async throws {
        try await base.prepare(display: display)
    }

    func frame(of rect: CGRect, on display: DisplayInfo) async throws -> CGImage {
        let image = try await base.frame(of: rect, on: display)
        count += 1
        let url = folder.appendingPathComponent(String(format: "frame-%03d.png", count))
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return image
    }
}
#endif
