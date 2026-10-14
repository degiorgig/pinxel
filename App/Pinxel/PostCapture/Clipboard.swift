import AppCore
import AppKit

@MainActor
enum Clipboard {
    static func copy(_ image: CGImage) {
        let representation = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = representation.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// L'immagine negli appunti, con la sua scala in pixel per punto.
    static func image() -> (image: CGImage, scale: Double)? {
        guard let image = NSImage(pasteboard: .general),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return (cgImage, CaptureDocumentBuilder.pastedScale(pixelWidth: cgImage.width, pointWidth: image.size.width))
    }
}
