import CoreGraphics

/// Pagina lunga virtuale per test e UI test: fa da sorgente dei fotogrammi e da scorrimento.
/// I fotogrammi sono intestazione + `viewportHeight` righe del contenuto + piè di pagina.
@MainActor
public final class FakeScrollingPage: RegionFrameSource, ScrollDriver {
    public let content: CGImage
    public let viewportHeight: Int
    public let header: CGImage?
    public let footer: CGImage?
    public let scale: Double
    /// Quanto scorre davvero rispetto al richiesto (app con accelerazione o scorrimento ridotto).
    public var scrollFactor: Double
    /// Contenuto che cambia da solo: ogni fotogramma è diverso dal precedente.
    public var isAnimating = false
    /// Chiamato a ogni fotogramma con il numero del fotogramma (da 1).
    public var onFrame: ((Int) -> Void)?
    public private(set) var position = 0
    public private(set) var scrollCalls: [Double] = []
    public private(set) var frameCount = 0

    public init(content: CGImage, viewportHeight: Int, header: CGImage? = nil, footer: CGImage? = nil,
                scale: Double = 2, scrollFactor: Double = 1) {
        self.content = content
        self.viewportHeight = min(viewportHeight, content.height)
        self.header = header
        self.footer = footer
        self.scale = scale
        self.scrollFactor = scrollFactor
    }

    public var maxPosition: Int { content.height - viewportHeight }

    public func scroll(by points: Double, at point: CGPoint) {
        scrollCalls.append(points)
        scrollTo(position + Int((points * scale * scrollFactor).rounded()))
    }

    /// Scorrimento a mano, in pixel.
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
        // Il contesto ha origine in basso a sinistra; `cropping` ha origine in alto a sinistra.
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

    /// Ciò che una cattura perfetta deve produrre: intestazione, tutto il contenuto, piè di pagina.
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
