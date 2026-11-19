import CoreGraphics
import Foundation
import Testing
import DocumentModel
import Rendering
@testable import Persistence
import PinxelTestSupport

struct ExporterTests {
    let provider = DictionaryAssetProvider([
        TestDocuments.background: TestImages.quadrants(),
        TestDocuments.placedImage: TestImages.solid(width: 10, height: 10, red: 0, green: 0.6, blue: 1),
    ])

    @Test func pngAtNativeScaleMatchesCanvasRenderExactly() throws {
        // Document at scale 2: 2x = native pixels, i.e. what the canvas shows at 100%.
        let document = TestDocuments.document()
        let exported = try ImageCodec.decode(Exporter.export(document, assets: provider, format: .png, scale: .twoX))
        let canvas = try DocumentRenderer().renderImage(document, assets: provider, options: RenderOptions(outputScale: 1))
        #expect(PixelBuffer(exported).differingPixelFraction(from: PixelBuffer(canvas), channelTolerance: 0) == 0)
    }

    @Test func oneXHalvesARetinaCapture() throws {
        let image = try ImageCodec.decode(Exporter.export(TestDocuments.document(), assets: provider, format: .png, scale: .oneX))
        #expect(image.width == 200 && image.height == 150)
    }

    @Test func twoXDoublesANonRetinaCapture() throws {
        let document = TestDocuments.document(scale: 1)
        let image = try ImageCodec.decode(Exporter.export(document, assets: provider, format: .png, scale: .twoX))
        #expect(image.width == 800 && image.height == 600)
    }

    @Test func jpegUsesWhiteMatte() throws {
        var document = TestDocuments.document(annotations: [])
        document.canvasStyle = CanvasStyle(padding: 20)
        let data = try Exporter.export(document, assets: provider, format: .jpeg(quality: 0.9), scale: .twoX)
        #expect(data.starts(with: [0xFF, 0xD8]))
        let pixels = PixelBuffer(try ImageCodec.decode(data))
        let corner = pixels.pixel(x: 3, y: 3)
        #expect(corner.r > 245 && corner.g > 245 && corner.b > 245, "got \(corner)")
    }

    @Test func heicExportDecodes() throws {
        let data = try Exporter.export(TestDocuments.document(), assets: provider, format: .heic(quality: 0.8), scale: .twoX)
        let image = try ImageCodec.decode(data)
        #expect(image.width == 400 && image.height == 300)
    }

    @Test func pdfHasOnePageOfTheRightSize() throws {
        let data = try Exporter.export(TestDocuments.document(), assets: provider, format: .pdf, scale: .oneX)
        #expect(data.starts(with: Array("%PDF".utf8)))
        let pdf = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(pdf.numberOfPages == 1)
        let box = try #require(pdf.page(at: 1)).getBoxRect(.mediaBox)
        #expect(box.size == CGSize(width: 200, height: 150))
    }

    @Test(arguments: [
        Annotation(kind: .blur(BlurData(rect: CGRect(x: 150, y: 30, width: 100, height: 80), radius: 12))),
        Annotation(kind: .pixelate(PixelateData(rect: CGRect(x: 150, y: 30, width: 100, height: 80), blockSize: 16))),
        Annotation(kind: .shape(ShapeData(rect: CGRect(x: 150, y: 30, width: 100, height: 80), shape: .rectangle)),
                   style: Style(stroke: nil, fill: .black)),
    ])
    func pdfEmbedsOnlyTheFlattenedScreenshot(cover: Annotation) throws {
        let document = TestDocuments.document(annotations: [cover])
        let data = try Exporter.export(document, assets: provider, format: .pdf, scale: .oneX)
        let pdf = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        let page = try #require(pdf.page(at: 1))
        // The only image in the PDF is the flattened capture, at the 400×300 pixels of the source even on a 200×150 pt page.
        #expect(Self.embeddedImageSizes(in: page.dictionary) == [CGSize(width: 400, height: 300)])

        let context = TestImages.makeContext(width: 200, height: 150)
        context.drawPDFPage(page)
        let renderedPage = try #require(context.makeImage())
        let flattened = try DocumentRenderer().renderImage(document, assets: provider, options: RenderOptions(outputScale: 0.5))
        #expect(PixelBuffer(renderedPage).differingPixelFraction(from: PixelBuffer(flattened)) < 0.01)
    }

    @Test func pdfKeepsTextAndArrowsAboveTheCaptureAsVectors() throws {
        let document = TestDocuments.document(annotations: [
            Annotation(kind: .arrow(ArrowData(line: LineGeometry(start: CGPoint(x: 20, y: 20), end: CGPoint(x: 200, y: 150))))),
            Annotation(kind: .text(TextData(rect: CGRect(x: 20, y: 200, width: 300, height: 40), text: RichText("Selectable", fontSize: 24))),
                       style: Style(stroke: nil, fill: nil, lineWidth: 0)),
        ])
        let data = try Exporter.export(document, assets: provider, format: .pdf, scale: .oneX)
        let page = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!)?.page(at: 1))
        // Only the capture is a bitmap; the text brings its font, so it stays selectable.
        #expect(Self.embeddedImageSizes(in: page.dictionary) == [CGSize(width: 400, height: 300)])
        #expect(Self.hasFonts(page.dictionary))
    }

    @Test func anOpaqueStrokeHidesThePixelsBelowItInTheEmbeddedBitmap() throws {
        let stroke = Annotation(kind: .pen(PenData(path: PathGeometry(points: [CGPoint(x: 40, y: 60), CGPoint(x: 160, y: 60)]))),
                                style: Style(stroke: .black, fill: nil, lineWidth: 40))
        let document = TestDocuments.document(annotations: [stroke])
        let data = try Exporter.export(document, assets: provider, format: .pdf, scale: .oneX)
        let page = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!)?.page(at: 1))
        let images = Self.embeddedImages(in: page.dictionary)
        #expect(images.count == 1)
        // Under the stroke the bitmap itself is black: the red of the screenshot is not in the file.
        let pixel = try #require(images.first?.rgb(x: 100, y: 60))
        #expect(pixel.r < 30 && pixel.g < 30 && pixel.b < 30, "got \(pixel)")
    }

    @Test func anImageAwayFromTheTextKeepsTheTextSelectable() throws {
        let document = TestDocuments.document(annotations: [
            Annotation(kind: .text(TextData(rect: CGRect(x: 20, y: 200, width: 200, height: 40), text: RichText("Selectable", fontSize: 24))),
                       style: Style(stroke: nil, fill: nil, lineWidth: 0)),
            Annotation(kind: .image(PlacedImageData(rect: CGRect(x: 330, y: 20, width: 40, height: 30), asset: TestDocuments.placedImage))),
        ])
        let data = try Exporter.export(document, assets: provider, format: .pdf, scale: .oneX)
        let page = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!)?.page(at: 1))
        #expect(Self.hasFonts(page.dictionary))
    }

    @Test func textUnderAFilledShapeIsNotInThePDF() throws {
        let document = TestDocuments.document(annotations: [
            Annotation(kind: .text(TextData(rect: CGRect(x: 20, y: 200, width: 200, height: 40), text: RichText("Secret", fontSize: 24))),
                       style: Style(stroke: nil, fill: nil, lineWidth: 0)),
            Annotation(kind: .shape(ShapeData(rect: CGRect(x: 10, y: 190, width: 230, height: 60), shape: .rectangle)),
                       style: Style(stroke: nil, fill: .black)),
        ])
        let data = try Exporter.export(document, assets: provider, format: .pdf, scale: .oneX)
        let page = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!)?.page(at: 1))
        #expect(!Self.hasFonts(page.dictionary))
    }

    struct EmbeddedImage {
        var width: Int
        var height: Int
        var samples: Data

        /// Color at (x, y) from the top left, for 8-bit RGB samples.
        func rgb(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
            guard width > 0, height > 0 else { return nil }
            let components = samples.count / (width * height)
            guard components >= 3 else { return nil }
            let offset = (y * width + x) * components
            let bytes = [UInt8](samples[samples.startIndex + offset ..< samples.startIndex + offset + 3])
            return (bytes[0], bytes[1], bytes[2])
        }
    }

    /// The decoded samples of every image on the page, inside forms too.
    private static func embeddedImages(in dictionary: CGPDFDictionaryRef?) -> [EmbeddedImage] {
        var resources: CGPDFDictionaryRef?
        var objects: CGPDFDictionaryRef?
        guard let dictionary,
              CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return [] }
        var images: [EmbeddedImage] = []
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let details = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(details, "Subtype", &subtype), let subtype else { return true }
            switch String(cString: subtype) {
            case "Image":
                var width: CGPDFInteger = 0
                var height: CGPDFInteger = 0
                var format = CGPDFDataFormat.raw
                if CGPDFDictionaryGetInteger(details, "Width", &width), CGPDFDictionaryGetInteger(details, "Height", &height),
                   let data = CGPDFStreamCopyData(stream, &format) as Data?, format == .raw {
                    images.append(EmbeddedImage(width: width, height: height, samples: data))
                }
            case "Form":
                images.append(contentsOf: embeddedImages(in: details))
            default:
                break
            }
            return true
        }, nil)
        return images
    }

    /// Whether the page, or a form drawn on it (each annotation is a transparency group), uses a font.
    private static func hasFonts(_ dictionary: CGPDFDictionaryRef?) -> Bool {
        var resources: CGPDFDictionaryRef?
        guard let dictionary, CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return false }
        var fonts: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts, CGPDFDictionaryGetCount(fonts) > 0 { return true }
        var objects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return false }
        var found = false
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream, hasFonts(CGPDFStreamGetDictionary(stream)) { found = true }
            return !found
        }, nil)
        return found
    }

    private static func embeddedImageSizes(in dictionary: CGPDFDictionaryRef?) -> [CGSize] {
        var resources: CGPDFDictionaryRef?
        var objects: CGPDFDictionaryRef?
        guard let dictionary,
              CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &objects), let objects else { return [] }

        var sizes: [CGSize] = []
        CGPDFDictionaryApplyBlock(objects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream),
                  let stream, let details = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(details, "Subtype", &subtype), let subtype else { return true }
            switch String(cString: subtype) {
            case "Image":
                var width: CGPDFInteger = 0
                var height: CGPDFInteger = 0
                if CGPDFDictionaryGetInteger(details, "Width", &width),
                   CGPDFDictionaryGetInteger(details, "Height", &height) {
                    sizes.append(CGSize(width: width, height: height))
                }
            case "Form":
                sizes.append(contentsOf: embeddedImageSizes(in: details))
            default:
                break
            }
            return true
        }, nil)
        return sizes
    }

    @Test func emptyCanvasCannotBeExported() {
        var empty = TestDocuments.document(annotations: [])
        empty.annotations = []
        empty.canvasSize = PixelSize(width: 0, height: 0)
        for format in [ExportFormat.png, .pdf] {
            #expect(throws: RenderError.invalidSize) {
                try Exporter.export(empty, assets: DictionaryAssetProvider([:]), format: format, scale: .oneX)
            }
        }
    }
}
