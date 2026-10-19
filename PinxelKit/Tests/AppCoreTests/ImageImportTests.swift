import CoreGraphics
import DocumentModel
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AppCore

struct ImageImportTests {
    private func image(width: Int, height: Int) throws -> CGImage {
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(ctx.makeImage())
    }

    private func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func pngBecomesTheCaptureOfANewDocument() throws {
        let data = try encode(try image(width: 120, height: 80), as: .png)
        let contents = try ImageImport.contents(fromImageData: data)
        #expect(contents.document.canvasSize == PixelSize(width: 120, height: 80))
        #expect(contents.document.scale == 1)
        #expect(contents.document.annotations.count == 1)
        guard case .image(let capture) = contents.document.annotations.first?.kind else { Issue.record("no capture"); return }
        #expect(capture.rect == CGRect(x: 0, y: 0, width: 120, height: 80))
        #expect(contents.images[capture.asset] != nil)
    }

    @Test func retinaResolutionGivesScaleTwo() throws {
        let data = try encode(try image(width: 120, height: 80), as: .png,
                              properties: [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144])
        #expect(try ImageImport.contents(fromImageData: data).document.scale == 2)
    }

    @Test func jpegOrientationIsApplied() throws {
        // Orientamento EXIF 6: la foto va ruotata di 90°, quindi larghezza e altezza si scambiano.
        let data = try encode(try image(width: 120, height: 80), as: .jpeg, properties: [kCGImagePropertyOrientation: 6])
        #expect(try ImageImport.contents(fromImageData: data).document.canvasSize == PixelSize(width: 80, height: 120))
    }

    @Test func notAnImageThrows() {
        #expect(throws: ImageImportError.unreadable) { try ImageImport.contents(fromImageData: Data("ciao".utf8)) }
    }
}
