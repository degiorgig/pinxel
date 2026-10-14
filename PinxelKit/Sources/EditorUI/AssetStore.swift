import CoreGraphics
import DocumentModel
import Foundation
import ImageIO
import Rendering

/// Immagini del documento più quelle incollate in questa sessione; le incollate si salvano con il documento
/// (`PinxelArchive.write` scrive solo quelle ancora usate).
public final class AssetStore: AssetProvider {
    private let base: any AssetProvider
    private var addedImages: [ImageAssetRef: CGImage] = [:]
    /// PNG delle immagini incollate, da aggiungere all'archivio al salvataggio.
    public private(set) var addedData: [ImageAssetRef: Data] = [:]

    public init(base: any AssetProvider) {
        self.base = base
    }

    public func image(for ref: ImageAssetRef) -> CGImage? {
        addedImages[ref] ?? base.image(for: ref)
    }

    /// Aggiunge un'immagine come `assets/<uuid>.png`; `nil` se non si riesce a codificarla.
    public func add(_ image: CGImage, id: UUID = UUID()) -> ImageAssetRef? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let ref = ImageAssetRef(name: "assets/\(id.uuidString).png")
        addedImages[ref] = image
        addedData[ref] = data as Data
        return ref
    }
}
