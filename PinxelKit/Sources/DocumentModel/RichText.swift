import Foundation

public enum RichTextAlignment: String, Codable, Sendable {
    case left, center, right
}

public struct TextRun: Codable, Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    /// `nil` = usa `RichText.color`.
    public var color: RGBA?

    public init(text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false, color: RGBA? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.color = color
    }
}

public struct RichText: Codable, Equatable, Sendable {
    public var runs: [TextRun]
    public var fontFamily: String
    public var fontSize: Double
    public var color: RGBA
    public var alignment: RichTextAlignment

    public init(
        runs: [TextRun],
        fontFamily: String = "Helvetica",
        fontSize: Double = 24,
        color: RGBA = .black,
        alignment: RichTextAlignment = .left
    ) {
        self.runs = runs
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.color = color
        self.alignment = alignment
    }

    public init(
        _ plain: String,
        fontFamily: String = "Helvetica",
        fontSize: Double = 24,
        color: RGBA = .black,
        alignment: RichTextAlignment = .left
    ) {
        self.init(runs: [TextRun(text: plain)], fontFamily: fontFamily, fontSize: fontSize, color: color, alignment: alignment)
    }

    public var plainText: String { runs.map(\.text).joined() }
}
