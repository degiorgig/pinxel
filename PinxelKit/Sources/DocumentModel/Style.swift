import Foundation

public enum DashPattern: String, Codable, Sendable {
    case solid, dashed, dotted
}

public struct Shadow: Codable, Equatable, Sendable {
    /// Offset in document pixels (positive y = downwards).
    public var offset: CGSize
    public var blur: Double
    public var color: RGBA

    public init(offset: CGSize = CGSize(width: 0, height: 3), blur: Double = 6, color: RGBA = RGBA(red: 0, green: 0, blue: 0, alpha: 0.5)) {
        self.offset = offset
        self.blur = blur
        self.color = color
    }
}

public struct Style: Codable, Equatable, Sendable {
    public var stroke: RGBA?
    public var fill: RGBA?
    public var lineWidth: Double
    public var dash: DashPattern
    /// 0...1, applied to the annotation as a group.
    public var opacity: Double
    public var shadow: Shadow?

    public init(
        stroke: RGBA? = .accentRed,
        fill: RGBA? = nil,
        lineWidth: Double = 4,
        dash: DashPattern = .solid,
        opacity: Double = 1,
        shadow: Shadow? = nil
    ) {
        self.stroke = stroke
        self.fill = fill
        self.lineWidth = lineWidth
        self.dash = dash
        self.opacity = opacity
        self.shadow = shadow
    }
}
