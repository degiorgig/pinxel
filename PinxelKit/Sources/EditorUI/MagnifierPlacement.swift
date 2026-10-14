import CoreGraphics

public enum MagnifierPlacement {
    /// Riquadro dell'ingrandimento di una lente nuova: la sorgente scalata di `zoom`, a destra della sorgente
    /// (a sinistra se non ci sta), centrata in verticale e dentro l'immagine finché possibile.
    public static func target(for source: CGRect, zoom: Double, imageSize: CGSize, gap: Double = 24) -> CGRect {
        let s = source.standardized
        let size = CGSize(width: s.width * zoom, height: s.height * zoom)
        var x = s.maxX + gap
        if x + size.width > imageSize.width { x = s.minX - gap - size.width }
        if x < 0 { x = max(0, min(imageSize.width - size.width, s.midX - size.width / 2)) }
        let y = max(0, min(s.midY - size.height / 2, imageSize.height - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
