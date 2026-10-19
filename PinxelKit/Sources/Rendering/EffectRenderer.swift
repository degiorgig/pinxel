import CoreGraphics
import CoreImage
import DocumentModel

enum EffectRenderer {
    static let ciContext = CIContext(options: [
        .workingColorSpace: ImageDrawing.sRGB,
        .outputColorSpace: ImageDrawing.sRGB,
        .cacheIntermediates: false,
    ])

    /// Regione intera di `rect` dentro il contenuto, o `nil` se vuota.
    static func region(_ rect: CGRect, in size: PixelSize) -> PixelRect? {
        let r = rect.standardized.integral
        guard r.minX.isFinite, r.minY.isFinite, r.width.isFinite, r.height.isFinite else { return nil }
        let pixel = PixelRect(
            x: ImageDrawing.clampedInt(r.minX), y: ImageDrawing.clampedInt(r.minY),
            width: ImageDrawing.clampedInt(r.width), height: ImageDrawing.clampedInt(r.height)
        ).clamped(to: size)
        return pixel.width > 0 && pixel.height > 0 ? pixel : nil
    }

    static func drawBlur(_ data: BlurData, index: Int, context: RenderContext, in ctx: CGContext) {
        guard data.radius > 0, let region = region(data.rect, in: context.contentSize),
              let below = context.layers(index, region) else { return }
        let key = "blur|\(below.key)|\(data.radius)"
        guard let image = context.effects.image(for: key, make: { blurred(below.image, radius: data.radius) }) else { return }
        ImageDrawing.draw(image, in: region.cgRect, context: ctx)
    }

    static func drawPixelate(_ data: PixelateData, index: Int, context: RenderContext, in ctx: CGContext) {
        guard let region = region(data.rect, in: context.contentSize), let below = context.layers(index, region) else { return }
        let key = "pixelate|\(below.key)|\(data.blockSize)"
        guard let image = context.effects.image(for: key, make: { pixelated(below.image, blockSize: data.blockSize) }) else { return }
        ImageDrawing.draw(image, in: region.cgRect, context: ctx)
    }

    private static func blurred(_ input: CGImage, radius: Double) -> CGImage? {
        let image = CIImage(cgImage: input)
        let output = image.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: image.extent)
        return ciContext.createCGImage(output, from: image.extent)
    }

    private static func pixelated(_ input: CGImage, blockSize: Double) -> CGImage? {
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        let image = CIImage(cgImage: input)
        filter.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(blockSize, 1), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: image.extent) else { return nil }
        return ciContext.createCGImage(output, from: image.extent)
    }

    static func drawMagnifier(_ data: MagnifierData, index: Int, style: Style, context: RenderContext, in ctx: CGContext) {
        let target = data.target.standardized
        let source = data.source.standardized
        guard target.width > 0, target.height > 0, source.width > 0, source.height > 0,
              let region = region(data.source, in: context.contentSize),
              let crop = context.layers(index, region)?.image else { return }
        // Solo la parte della sorgente dentro l'immagine viene ingrandita, nella posizione corrispondente.
        let sx = target.width / source.width
        let sy = target.height / source.height
        let visible = region.cgRect
        let cropTarget = CGRect(
            x: target.minX + (visible.minX - source.minX) * sx,
            y: target.minY + (visible.minY - source.minY) * sy,
            width: visible.width * sx,
            height: visible.height * sy
        )
        let stroked = style.stroke != nil && style.lineWidth > 0

        if data.showsConnector, stroked {
            StrokeStyle.apply(style, to: ctx)
            ctx.move(to: CGPoint(x: source.midX, y: source.midY))
            ctx.addLine(to: CGPoint(x: target.midX, y: target.midY))
            ctx.strokePath()
            ctx.addPath(ShapeRenderer.shapePath(data.shape, in: source))
            ctx.strokePath()
        }

        let path = ShapeRenderer.shapePath(data.shape, in: target)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(RGBA.white.cgColor)
        ctx.fill(target)
        ctx.interpolationQuality = .none
        ImageDrawing.draw(crop, in: cropTarget, context: ctx)
        ctx.restoreGState()

        if stroked {
            StrokeStyle.apply(style, to: ctx)
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    static func drawPlacedImage(_ data: PlacedImageData, context: RenderContext, in ctx: CGContext) {
        let rect = data.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        if let image = context.assets.image(for: data.asset) {
            ImageDrawing.draw(image, in: rect, context: ctx)
            return
        }
        // Segnaposto per immagine mancante: grigio con una X.
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        ctx.fill(rect)
        ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 1))
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.move(to: CGPoint(x: rect.minX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        ctx.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        ctx.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        ctx.strokePath()
    }
}
