import Foundation

/// Colore con componenti 0...1 nello spazio colore del documento.
public struct RGBA: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let white = RGBA(red: 1, green: 1, blue: 1)
    public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)
    public static let accentRed = RGBA(red: 0.9, green: 0.16, blue: 0.2)
    public static let highlightYellow = RGBA(red: 1, green: 0.92, blue: 0.23)
}
