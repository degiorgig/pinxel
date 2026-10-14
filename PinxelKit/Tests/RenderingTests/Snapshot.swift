import CoreGraphics
import Foundation
import ImageIO
import PinxelTestSupport
import Testing
import UniformTypeIdentifiers

/// Confronto con PNG di riferimento in `__Snapshots__/`.
/// Se il riferimento manca (o con PINXEL_RECORD_SNAPSHOTS=1) lo scrive e fa fallire il test:
/// controlla l'immagine a occhio, poi rilancia.
enum Snapshot {
    static func assertMatches(
        _ image: CGImage,
        named name: String,
        tolerance: Double = 0.01,
        filePath: String = #filePath,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let directory = URL(fileURLWithPath: filePath).deletingLastPathComponent().appendingPathComponent("__Snapshots__")
        let reference = directory.appendingPathComponent("\(name).png")
        let recording = ProcessInfo.processInfo.environment["PINXEL_RECORD_SNAPSHOTS"] == "1"

        if recording || !FileManager.default.fileExists(atPath: reference.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try writePNG(image, to: reference)
                Issue.record("Snapshot '\(name)' registrato in \(reference.path): controllalo e rilancia i test.", sourceLocation: sourceLocation)
            } catch {
                Issue.record("Impossibile scrivere lo snapshot '\(name)': \(error)", sourceLocation: sourceLocation)
            }
            return
        }

        guard let source = CGImageSourceCreateWithURL(reference as CFURL, nil),
              let expected = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            Issue.record("Snapshot '\(name)' illeggibile", sourceLocation: sourceLocation)
            return
        }
        let difference = PixelBuffer(image).differingPixelFraction(from: PixelBuffer(expected))
        if difference > tolerance {
            let actual = directory.appendingPathComponent("\(name).actual.png")
            try? writePNG(image, to: actual)
            Issue.record(
                "Snapshot '\(name)' differisce del \(difference * 100)% (tolleranza \(tolerance * 100)%). Risultato in \(actual.path)",
                sourceLocation: sourceLocation
            )
        }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
