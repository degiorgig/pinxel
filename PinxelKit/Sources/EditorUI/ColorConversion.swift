import AppKit
import DocumentModel

extension RGBA {
    /// The color's sRGB components (system pickers may return other color spaces).
    public init(nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(color.redComponent), green: Double(color.greenComponent),
                  blue: Double(color.blueComponent), alpha: Double(color.alphaComponent))
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
