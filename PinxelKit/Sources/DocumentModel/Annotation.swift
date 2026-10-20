import Foundation

public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: Kind
    public var style: Style
    /// Radians, clockwise on screen, around the center of `bounds`.
    public var rotation: Double
    public var isLocked: Bool

    public init(id: UUID = UUID(), kind: Kind, style: Style = Style(), rotation: Double = 0, isLocked: Bool = false) {
        self.id = id
        self.kind = kind
        self.style = style
        self.rotation = rotation
        self.isLocked = isLocked
    }
}

extension Annotation {
    public enum Kind: Equatable, Sendable {
        case arrow(ArrowData)
        case line(LineData)
        case shape(ShapeData)
        case text(TextData)
        case callout(CalloutData)
        case step(StepData)
        case magnifier(MagnifierData)
        case blur(BlurData)
        case pixelate(PixelateData)
        case highlight(HighlightData)
        case pen(PenData)
        case image(PlacedImageData)
        /// Unrecognized type (file from a future version): preserved and saved back unchanged.
        case unknown(type: String, raw: JSONValue)

        public var typeName: String {
            switch self {
            case .arrow: "arrow"
            case .line: "line"
            case .shape: "shape"
            case .text: "text"
            case .callout: "callout"
            case .step: "step"
            case .magnifier: "magnifier"
            case .blur: "blur"
            case .pixelate: "pixelate"
            case .highlight: "highlight"
            case .pen: "pen"
            case .image: "image"
            case .unknown(let type, _): type
            }
        }
    }

    /// Normalized rectangle containing the geometry (without rotation or stroke thickness).
    public var bounds: CGRect {
        switch kind {
        case .arrow(let data): .bounding([data.line.start, data.line.end])
        case .line(let data): .bounding([data.line.start, data.line.end])
        case .shape(let data): data.rect.standardized
        case .text(let data): data.rect.standardized
        case .callout(let data): data.rect.standardized.union(CGRect(origin: data.tail.tip, size: .zero))
        case .step(let data):
            CGRect(x: data.center.x - data.diameter / 2, y: data.center.y - data.diameter / 2,
                   width: data.diameter, height: data.diameter)
        case .magnifier(let data): data.source.standardized.union(data.target.standardized)
        case .blur(let data): data.rect.standardized
        case .pixelate(let data): data.rect.standardized
        case .highlight(let data): .bounding(data.path.points)
        case .pen(let data): .bounding(data.path.points)
        case .image(let data): data.rect.standardized
        case .unknown: .null
        }
    }
}

extension Annotation: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, type, data, rotation, style, isLocked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        style = try c.decode(Style.self, forKey: .style)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "arrow": kind = .arrow(try c.decode(ArrowData.self, forKey: .data))
        case "line": kind = .line(try c.decode(LineData.self, forKey: .data))
        case "shape": kind = .shape(try c.decode(ShapeData.self, forKey: .data))
        case "text": kind = .text(try c.decode(TextData.self, forKey: .data))
        case "callout": kind = .callout(try c.decode(CalloutData.self, forKey: .data))
        case "step": kind = .step(try c.decode(StepData.self, forKey: .data))
        case "magnifier": kind = .magnifier(try c.decode(MagnifierData.self, forKey: .data))
        case "blur": kind = .blur(try c.decode(BlurData.self, forKey: .data))
        case "pixelate": kind = .pixelate(try c.decode(PixelateData.self, forKey: .data))
        case "highlight": kind = .highlight(try c.decode(HighlightData.self, forKey: .data))
        case "pen": kind = .pen(try c.decode(PenData.self, forKey: .data))
        case "image": kind = .image(try c.decode(PlacedImageData.self, forKey: .data))
        default: kind = .unknown(type: type, raw: try c.decode(JSONValue.self, forKey: .data))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.typeName, forKey: .type)
        try c.encode(style, forKey: .style)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(isLocked, forKey: .isLocked)
        switch kind {
        case .arrow(let data): try c.encode(data, forKey: .data)
        case .line(let data): try c.encode(data, forKey: .data)
        case .shape(let data): try c.encode(data, forKey: .data)
        case .text(let data): try c.encode(data, forKey: .data)
        case .callout(let data): try c.encode(data, forKey: .data)
        case .step(let data): try c.encode(data, forKey: .data)
        case .magnifier(let data): try c.encode(data, forKey: .data)
        case .blur(let data): try c.encode(data, forKey: .data)
        case .pixelate(let data): try c.encode(data, forKey: .data)
        case .highlight(let data): try c.encode(data, forKey: .data)
        case .pen(let data): try c.encode(data, forKey: .data)
        case .image(let data): try c.encode(data, forKey: .data)
        case .unknown(_, let raw): try c.encode(raw, forKey: .data)
        }
    }
}
