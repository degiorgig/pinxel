import Foundation

public enum HeadStyle: String, Codable, Sendable {
    case none, triangle, open, circle
}

public struct ArrowHeads: Codable, Equatable, Sendable {
    public var start: HeadStyle
    public var end: HeadStyle

    public init(start: HeadStyle = .none, end: HeadStyle = .triangle) {
        self.start = start
        self.end = end
    }
}

public enum ShapeType: Codable, Equatable, Sendable {
    case rectangle
    case roundedRectangle(cornerRadius: Double)
    case ellipse
}

public struct CalloutTail: Codable, Equatable, Sendable {
    /// Tail tip, in absolute document coordinates.
    public var tip: CGPoint
    public var baseWidth: Double

    public init(tip: CGPoint, baseWidth: Double = 24) {
        self.tip = tip
        self.baseWidth = baseWidth
    }
}

public enum StepSequence: String, Codable, Sendable {
    case numbers, uppercaseLetters, lowercaseLetters
}

public struct StepLabel: Codable, Equatable, Sendable {
    public var sequence: StepSequence
    /// If set, replaces the automatically computed value.
    public var override: String?

    public init(sequence: StepSequence = .numbers, override: String? = nil) {
        self.sequence = sequence
        self.override = override
    }
}

public struct ArrowData: Codable, Equatable, Sendable {
    public var line: LineGeometry
    public var heads: ArrowHeads
    public init(line: LineGeometry, heads: ArrowHeads = ArrowHeads()) { self.line = line; self.heads = heads }
}

public struct LineData: Codable, Equatable, Sendable {
    public var line: LineGeometry
    public init(line: LineGeometry) { self.line = line }
}

public struct ShapeData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var shape: ShapeType
    public init(rect: CGRect, shape: ShapeType) { self.rect = rect; self.shape = shape }
}

public struct TextData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var text: RichText
    public init(rect: CGRect, text: RichText) { self.rect = rect; self.text = text }
}

public struct CalloutData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var text: RichText
    public var tail: CalloutTail
    public init(rect: CGRect, text: RichText, tail: CalloutTail) { self.rect = rect; self.text = text; self.tail = tail }
}

public struct StepData: Codable, Equatable, Sendable {
    public var center: CGPoint
    public var diameter: Double
    public var label: StepLabel
    public init(center: CGPoint, diameter: Double, label: StepLabel = StepLabel()) {
        self.center = center; self.diameter = diameter; self.label = label
    }
}

public struct MagnifierData: Codable, Equatable, Sendable {
    public var source: CGRect
    public var target: CGRect
    public var shape: ShapeType
    public var showsConnector: Bool
    public init(source: CGRect, target: CGRect, shape: ShapeType = .ellipse, showsConnector: Bool = true) {
        self.source = source; self.target = target; self.shape = shape; self.showsConnector = showsConnector
    }
}

public struct BlurData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var radius: Double
    public init(rect: CGRect, radius: Double = 12) { self.rect = rect; self.radius = radius }
}

public struct PixelateData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var blockSize: Double
    public init(rect: CGRect, blockSize: Double = 12) { self.rect = rect; self.blockSize = blockSize }
}

public struct HighlightData: Codable, Equatable, Sendable {
    public var path: PathGeometry
    public init(path: PathGeometry) { self.path = path }
}

public struct PenData: Codable, Equatable, Sendable {
    public var path: PathGeometry
    public var smoothing: Double
    public init(path: PathGeometry, smoothing: Double = 1) { self.path = path; self.smoothing = smoothing }
}

public struct PlacedImageData: Codable, Equatable, Sendable {
    public var rect: CGRect
    public var asset: ImageAssetRef
    public init(rect: CGRect, asset: ImageAssetRef) { self.rect = rect; self.asset = asset }
}
