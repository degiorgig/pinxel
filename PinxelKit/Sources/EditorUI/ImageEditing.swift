import CoreGraphics
import DocumentModel

/// Fogli del menu Immagine.
public enum EditorSheet: String, Identifiable, Sendable {
    case resizeImage, canvasStyle

    public var id: String { rawValue }
}

/// Valori del foglio Ridimensiona immagine. Le dimensioni restano in 1...`maxImageSide`.
public struct ResizeDraft: Equatable, Sendable {
    public let original: PixelSize
    public private(set) var width: Int
    public private(set) var height: Int
    public var keepsAspect = true

    public init(original: PixelSize) {
        self.original = original
        width = original.width
        height = original.height
    }

    public mutating func setWidth(_ value: Int) {
        width = Self.clamp(value)
        if keepsAspect { height = Self.clamp(Self.scaled(original.height, by: Double(width) / Double(max(original.width, 1)))) }
    }

    public mutating func setHeight(_ value: Int) {
        height = Self.clamp(value)
        if keepsAspect { width = Self.clamp(Self.scaled(original.width, by: Double(height) / Double(max(original.height, 1)))) }
    }

    public mutating func setPercent(_ percent: Double) {
        width = Self.clamp(Self.scaled(original.width, by: percent / 100))
        height = Self.clamp(Self.scaled(original.height, by: percent / 100))
    }

    /// Larghezza rispetto all'originale, in percento arrotondato.
    public var percent: Int {
        Int((Double(width) / Double(max(original.width, 1)) * 100).rounded())
    }

    /// `nil` se le dimensioni non cambiano.
    public var operation: ImageOperation? {
        let size = PixelSize(width: width, height: height)
        return size == original ? nil : .resize(size)
    }

    private static func scaled(_ value: Int, by factor: Double) -> Int {
        let result = (Double(value) * factor).rounded()
        return result.isFinite ? Int(max(min(result, Double(Int32.max)), 0)) : 1
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, 1), PinxelDocument.maxImageSide)
    }
}

/// Modifiche al bordo, all'ombra, ai margini e allo sfondo della tela (foglio Bordo, ombra e margini).
public enum CanvasStyleEditing {
    public static let defaultBorder = Border(color: .black, width: 4)
    public static let defaultShadow = Shadow(offset: CGSize(width: 0, height: 8), blur: 24, color: RGBA(red: 0, green: 0, blue: 0, alpha: 0.35))

    /// Margine minimo perché l'ombra non venga tagliata dal bordo della tela.
    public static func paddingNeeded(for shadow: Shadow) -> Double {
        (shadow.blur * 1.5 + max(abs(shadow.offset.width), abs(shadow.offset.height))).rounded(.up)
    }

    /// Accendere l'ombra allarga i margini quanto serve; spegnerla non li stringe.
    public static func settingShadow(_ on: Bool, in style: CanvasStyle) -> CanvasStyle {
        var result = style
        result.shadow = on ? (style.shadow ?? defaultShadow) : nil
        if let shadow = result.shadow { result.padding = max(result.padding, paddingNeeded(for: shadow)) }
        return result
    }

    public static func settingBorder(_ on: Bool, in style: CanvasStyle) -> CanvasStyle {
        var result = style
        result.border = on ? (style.border ?? defaultBorder) : nil
        return result
    }

    public static func settingBackground(_ on: Bool, in style: CanvasStyle) -> CanvasStyle {
        var result = style
        result.backgroundColor = on ? (style.backgroundColor ?? .white) : nil
        return result
    }
}
