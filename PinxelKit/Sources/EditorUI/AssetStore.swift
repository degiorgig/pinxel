import CoreGraphics
import DocumentModel
import Foundation
import ImageIO
import Rendering

/// Document images plus those pasted in this session; pasted ones are saved with the document
/// (`PinxelArchive.write` writes only those still in use).
public final class AssetStore: AssetProvider {
    private let base: any AssetProvider
    private var addedImages: [ImageAssetRef: CGImage] = [:]
    /// PNGs of the pasted images, to add to the archive on save.
    public private(set) var addedData: [ImageAssetRef: Data] = [:]

    public init(base: any AssetProvider) {
        self.base = base
    }

    public func image(for ref: ImageAssetRef) -> CGImage? {
        addedImages[ref] ?? base.image(for: ref)
    }

    /// Adds an image as `assets/<uuid>.png`; `nil` if it cannot be encoded.
    public func add(_ image: CGImage, id: UUID = UUID()) -> ImageAssetRef? {
        guard let data = Self.png(image) else { return nil }
        let ref = ImageAssetRef(name: "assets/\(id.uuidString).png")
        addedImages[ref] = image
        addedData[ref] = data
        return ref
    }

    /// PNG of an image available here, to put it on the pasteboard.
    public func pngData(for ref: ImageAssetRef) -> Data? {
        if let data = addedData[ref] { return data }
        return image(for: ref).flatMap(Self.png)
    }

    /// Adds under the same name an image that came from the pasteboard from another document.
    @discardableResult
    public func add(pngData data: Data, as ref: ImageAssetRef) -> Bool {
        guard image(for: ref) == nil else { return true }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        addedImages[ref] = image
        addedData[ref] = data
        return true
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
