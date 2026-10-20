import CoreGraphics
import DocumentModel
import Foundation

public enum AnnotationEditing {
    /// Command that applies `change` to the indicated, unlocked annotations; `nil` if nothing changes.
    public static func update(_ ids: Set<UUID>, in document: PinxelDocument, name: String, _ change: (inout Annotation) -> Void) -> UpdateAnnotations? {
        var before: [Annotation] = []
        var after: [Annotation] = []
        for annotation in document.annotations where ids.contains(annotation.id) && !annotation.isLocked {
            var changed = annotation
            change(&changed)
            if changed != annotation {
                before.append(annotation)
                after.append(changed)
            }
        }
        return before.isEmpty ? nil : UpdateAnnotations(name: name, before: before, after: after)
    }

    public static func setLocked(_ locked: Bool, ids: Set<UUID>, in document: PinxelDocument) -> UpdateAnnotations? {
        let before = document.annotations.filter { ids.contains($0.id) && $0.isLocked != locked }
        guard !before.isEmpty else { return nil }
        let after = before.map { annotation -> Annotation in
            var copy = annotation
            copy.isLocked = locked
            return copy
        }
        return UpdateAnnotations(name: locked ? CommandName.lock : CommandName.unlock, before: before, after: after)
    }

    /// Copies moved by `offset`, with new IDs and unlocked.
    public static func duplicates(of annotations: [Annotation], offset: CGSize, makeID: () -> UUID = { UUID() }) -> [Annotation] {
        annotations.map { annotation in
            let moved = AnnotationGeometry.moved(annotation, by: offset)
            return Annotation(id: makeID(), kind: moved.kind, style: moved.style, rotation: moved.rotation, isLocked: false)
        }
    }
}

extension Annotation {
    public var arrowHeads: ArrowHeads? {
        get {
            guard case .arrow(let data) = kind else { return nil }
            return data.heads
        }
        set {
            guard case .arrow(var data) = kind, let newValue else { return }
            data.heads = newValue
            kind = .arrow(data)
        }
    }

    public var shapeType: ShapeType? {
        get {
            guard case .shape(let data) = kind else { return nil }
            return data.shape
        }
        set {
            guard case .shape(var data) = kind, let newValue else { return }
            data.shape = newValue
            kind = .shape(data)
        }
    }

    public var stepSequence: StepSequence? {
        get {
            guard case .step(let data) = kind else { return nil }
            return data.label.sequence
        }
        set {
            guard case .step(var data) = kind, let newValue else { return }
            data.label.sequence = newValue
            kind = .step(data)
        }
    }

    /// Blur radius or side of the pixelation blocks.
    public var effectAmount: Double? {
        get {
            switch kind {
            case .blur(let data): data.radius
            case .pixelate(let data): data.blockSize
            default: nil
            }
        }
        set {
            guard let newValue else { return }
            switch kind {
            case .blur(var data):
                data.radius = newValue
                kind = .blur(data)
            case .pixelate(var data):
                data.blockSize = newValue
                kind = .pixelate(data)
            default:
                break
            }
        }
    }

    public var effectMode: EffectMode? {
        switch kind {
        case .blur: .blur
        case .pixelate: .pixelate
        default: nil
        }
    }

    public var magnifierShape: ShapeType? {
        get {
            guard case .magnifier(let data) = kind else { return nil }
            return data.shape
        }
        set {
            guard case .magnifier(var data) = kind, let newValue else { return }
            data.shape = newValue
            kind = .magnifier(data)
        }
    }

    public var magnifierConnector: Bool? {
        get {
            guard case .magnifier(let data) = kind else { return nil }
            return data.showsConnector
        }
        set {
            guard case .magnifier(var data) = kind, let newValue else { return }
            data.showsConnector = newValue
            kind = .magnifier(data)
        }
    }

    /// Magnification (side of the magnified view / side of the source); changing it resizes the magnified view
    /// around its center.
    public var magnifierZoom: Double? {
        get {
            guard case .magnifier(let data) = kind else { return nil }
            let source = data.source.standardized
            return source.width > 0 ? data.target.standardized.width / source.width : nil
        }
        set {
            guard case .magnifier(var data) = kind, let newValue, newValue > 0 else { return }
            let source = data.source.standardized
            let center = data.target.standardized.center
            let size = CGSize(width: source.width * newValue, height: source.height * newValue)
            data.target = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
            kind = .magnifier(data)
        }
    }

    mutating func convertEffect(to mode: EffectMode) {
        switch (kind, mode) {
        case (.blur(let data), .pixelate): kind = .pixelate(PixelateData(rect: data.rect, blockSize: data.radius))
        case (.pixelate(let data), .blur): kind = .blur(BlurData(rect: data.rect, radius: data.blockSize))
        default: break
        }
    }
}
