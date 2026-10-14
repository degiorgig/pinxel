import CoreGraphics

public enum ImagePlacement {
    /// Riquadro di un'immagine incollata, in pixel del documento: alla stessa densità del documento
    /// (uno screenshot Retina in una cattura Retina mantiene i suoi pixel), ridotta entro l'80% della cattura,
    /// centrata in `center`.
    public static func rect(pixelSize: CGSize, imageScale: Double, documentScale: Double, center: CGPoint, imageSize: CGSize) -> CGRect {
        let factor = documentScale / max(imageScale, 1)
        var width = pixelSize.width * factor
        var height = pixelSize.height * factor
        let shrink = min(1, imageSize.width * 0.8 / max(width, 1), imageSize.height * 0.8 / max(height, 1))
        width = max(1, (width * shrink).rounded())
        height = max(1, (height * shrink).rounded())
        return CGRect(x: (center.x - width / 2).rounded(), y: (center.y - height / 2).rounded(), width: width, height: height)
    }
}
