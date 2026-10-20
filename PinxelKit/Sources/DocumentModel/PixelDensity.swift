import Foundation

public enum PixelDensity {
    /// Pixels per point of an image, rounded and limited to 1...3: a Retina screenshot is 2.
    public static func scale(pixelWidth: Int, pointWidth: Double) -> Double {
        guard pointWidth > 0, pointWidth.isFinite else { return 1 }
        return min(3, max(1, (Double(pixelWidth) / pointWidth).rounded()))
    }
}
