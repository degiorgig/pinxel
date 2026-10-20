import CoreGraphics

/// Virtual long page for tests and UI tests: it is the frame source; tests scroll it with `scrollTo`.
/// Frames are header + `viewportHeight` rows of content + footer.
@MainActor
public final class FakeScrollingPage: RegionFrameSource {
    public let content: CGImage
    public let viewportHeight: Int
    public let header: CGImage?
    public let footer: CGImage?
    public let scale: Double
    /// Content that changes by itself: every frame differs from the previous one.
    public var isAnimating = false
    /// Called at every frame with the frame number (from 1).
    public var onFrame: ((Int) -> Void)?
    public private(set) var position = 0
    public private(set) var frameCount = 0

    public init(content: CGImage, viewportHeight: Int, header: CGImage? = nil, footer: CGImage? = nil,
                scale: Double = 2) {
        self.content = content
        self.viewportHeight = min(viewportHeight, content.height)
        self.header = header
        self.footer = footer
        self.scale = scale
    }

    public var maxPosition: Int { content.height - viewportHeight }

    /// User scroll, in pixels.
    public func scrollTo(_ newPosition: Int) {
        position = min(max(newPosition, 0), maxPosition)
    }

    public func frame(of rect: CGRect, on display: DisplayInfo) async throws -> CGImage {
        frameCount += 1
        onFrame?(frameCount)
        return currentFrame()
    }

    public func currentFrame() -> CGImage {
        let headerHeight = header?.height ?? 0, footerHeight = footer?.height ?? 0
        let width = content.width, height = headerHeight + viewportHeight + footerHeight
        let ctx = Self.context(width: width, height: height)
        // The context has its origin at the bottom left; `cropping` has its origin at the top left.
        if isAnimating {
            ctx.setFillColor(CGColor(srgbRed: Double(frameCount % 7) / 7, green: 0.5, blue: Double(frameCount % 3) / 3, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: frameCount * 7 % max(width, 1), y: 0, width: 3, height: height))
            return ctx.makeImage()!
        }
        if let visible = content.cropping(to: CGRect(x: 0, y: position, width: width, height: viewportHeight)) {
            ctx.draw(visible, in: CGRect(x: 0, y: footerHeight, width: width, height: viewportHeight))
        }
        if let header { ctx.draw(header, in: CGRect(x: 0, y: height - headerHeight, width: width, height: headerHeight)) }
        if let footer { ctx.draw(footer, in: CGRect(x: 0, y: 0, width: width, height: footerHeight)) }
        return ctx.makeImage()!
    }

    /// What a perfect capture must produce: header, all the content, footer.
    public var expectedImage: CGImage {
        let headerHeight = header?.height ?? 0, footerHeight = footer?.height ?? 0
        let width = content.width, height = headerHeight + content.height + footerHeight
        let ctx = Self.context(width: width, height: height)
        ctx.draw(content, in: CGRect(x: 0, y: footerHeight, width: width, height: content.height))
        if let header { ctx.draw(header, in: CGRect(x: 0, y: height - headerHeight, width: width, height: headerHeight)) }
        if let footer { ctx.draw(footer, in: CGRect(x: 0, y: 0, width: width, height: footerHeight)) }
        return ctx.makeImage()!
    }

    static func context(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}
