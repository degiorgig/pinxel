import CoreGraphics
import DocumentModel

extension RichText {
    public var isBold: Bool { !runs.isEmpty && runs.allSatisfy(\.bold) }
    public var isItalic: Bool { !runs.isEmpty && runs.allSatisfy(\.italic) }
    public var isUnderlined: Bool { !runs.isEmpty && runs.allSatisfy(\.underline) }

    public mutating func setBold(_ on: Bool) {
        for index in runs.indices { runs[index].bold = on }
    }

    public mutating func setItalic(_ on: Bool) {
        for index in runs.indices { runs[index].italic = on }
    }

    public mutating func setUnderline(_ on: Bool) {
        for index in runs.indices { runs[index].underline = on }
    }

    /// Colore di tutto il testo: i colori dei singoli run vengono tolti.
    public mutating func setColor(_ color: RGBA) {
        self.color = color
        for index in runs.indices { runs[index].color = nil }
    }
}

extension Annotation {
    /// Testo di un testo o di un callout; `nil` per gli altri tipi (e assegnarlo non fa nulla).
    public var richText: RichText? {
        get {
            switch kind {
            case .text(let data): return data.text
            case .callout(let data): return data.text
            default: return nil
            }
        }
        set {
            guard let newValue else { return }
            switch kind {
            case .text(var data):
                data.text = newValue
                kind = .text(data)
            case .callout(var data):
                data.text = newValue
                kind = .callout(data)
            default:
                break
            }
        }
    }

    public var textRect: CGRect? {
        switch kind {
        case .text(let data): return data.rect.standardized
        case .callout(let data): return data.rect.standardized
        default: return nil
        }
    }

    /// Margine fra il riquadro e il testo, uguale a quello usato da `TextRenderer`.
    public var textInset: Double {
        if case .callout = kind { return 10 }
        return 4
    }

    /// Alza il riquadro del testo fino a `height`; non lo abbassa mai.
    public mutating func growTextHeight(to height: Double) {
        switch kind {
        case .text(var data):
            data.rect = data.rect.standardized
            data.rect.size.height = max(data.rect.height, height)
            kind = .text(data)
        case .callout(var data):
            data.rect = data.rect.standardized
            data.rect.size.height = max(data.rect.height, height)
            kind = .callout(data)
        default:
            break
        }
    }
}
