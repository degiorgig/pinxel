import Foundation

public enum PixelDensity {
    /// Pixel per punto di un'immagine, arrotondati e limitati a 1...3: uno screenshot Retina vale 2.
    public static func scale(pixelWidth: Int, pointWidth: Double) -> Double {
        guard pointWidth > 0, pointWidth.isFinite else { return 1 }
        return min(3, max(1, (Double(pixelWidth) / pointWidth).rounded()))
    }
}
