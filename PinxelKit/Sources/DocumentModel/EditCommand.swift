import Foundation

/// Reversible change to the document. For every command created from a document `d`,
/// `apply` followed by `revert` must give back exactly `d`.
public protocol EditCommand: Sendable {
    /// Name shown in "Undo <name>".
    var name: String { get }
    func apply(to document: inout PinxelDocument)
    func revert(on document: inout PinxelDocument)
}

/// Added annotations must have new IDs: `revert` removes by ID.
public struct AddAnnotations: EditCommand {
    public let name: String
    public let annotations: [Annotation]
    public let index: Int?

    public init(_ annotations: [Annotation], at index: Int? = nil, name: String = CommandName.add) {
        self.annotations = annotations
        self.index = index
        self.name = name
    }

    public func apply(to document: inout PinxelDocument) {
        if let index {
            document.annotations.insert(contentsOf: annotations, at: min(max(index, 0), document.annotations.count))
        } else {
            document.annotations.append(contentsOf: annotations)
        }
    }

    public func revert(on document: inout PinxelDocument) {
        let ids = Set(annotations.map(\.id))
        document.annotations.removeAll { ids.contains($0.id) }
    }
}

public struct DeleteAnnotations: EditCommand {
    private struct Removed: Sendable {
        let index: Int
        let annotation: Annotation
    }

    public let name: String
    private let removed: [Removed]

    public init(ids: Set<UUID>, in document: PinxelDocument, name: String = CommandName.delete) {
        self.name = name
        removed = document.annotations.enumerated()
            .filter { ids.contains($0.element.id) }
            .map { Removed(index: $0.offset, annotation: $0.element) }
    }

    public func apply(to document: inout PinxelDocument) {
        let ids = Set(removed.map(\.annotation.id))
        document.annotations.removeAll { ids.contains($0.id) }
    }

    public func revert(on document: inout PinxelDocument) {
        for item in removed {
            document.annotations.insert(item.annotation, at: min(item.index, document.annotations.count))
        }
    }
}

public struct UpdateAnnotations: EditCommand {
    public let name: String
    public let before: [Annotation]
    public let after: [Annotation]

    public init(name: String = CommandName.edit, before: [Annotation], after: [Annotation]) {
        self.name = name
        self.before = before
        self.after = after
    }

    public func apply(to document: inout PinxelDocument) { replace(with: after, in: &document) }
    public func revert(on document: inout PinxelDocument) { replace(with: before, in: &document) }

    /// Merges two consecutive changes on the same objects (e.g. moves with the arrow keys).
    public func merged(with next: UpdateAnnotations) -> UpdateAnnotations? {
        guard Set(after.map(\.id)) == Set(next.before.map(\.id)),
              Set(before.map(\.id)) == Set(next.after.map(\.id)) else { return nil }
        return UpdateAnnotations(name: next.name, before: before, after: next.after)
    }

    private func replace(with annotations: [Annotation], in document: inout PinxelDocument) {
        for annotation in annotations {
            if let index = document.annotations.firstIndex(where: { $0.id == annotation.id }) {
                document.annotations[index] = annotation
            }
        }
    }
}

/// Replaces the whole list of objects (crop, resize, cut and stitch): undo puts it back as it was.
public struct SetAnnotations: EditCommand {
    public let name: String
    public let before: [Annotation]
    public let after: [Annotation]

    public init(name: String, before: [Annotation], after: [Annotation]) {
        self.name = name
        self.before = before
        self.after = after
    }

    public func apply(to document: inout PinxelDocument) { document.annotations = after }
    public func revert(on document: inout PinxelDocument) { document.annotations = before }
}

public struct ReorderAnnotations: EditCommand {
    public let name: String
    private let before: [UUID]
    private let after: [UUID]

    public init(name: String = CommandName.arrange, newOrder: [UUID], in document: PinxelDocument) {
        self.name = name
        before = document.annotations.map(\.id)
        after = newOrder
    }

    public func apply(to document: inout PinxelDocument) { reorder(&document, to: after) }
    public func revert(on document: inout PinxelDocument) { reorder(&document, to: before) }

    private func reorder(_ document: inout PinxelDocument, to order: [UUID]) {
        let byID = Dictionary(document.annotations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = order.compactMap { byID[$0] }
        let listed = Set(order)
        // Annotations not listed stay on top, in their order.
        document.annotations = ordered + document.annotations.filter { !listed.contains($0.id) }
    }

    public static func bringToFront(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        let order = document.annotations.map(\.id)
        return ReorderAnnotations(name: CommandName.bringToFront, newOrder: order.filter { !ids.contains($0) } + order.filter { ids.contains($0) }, in: document)
    }

    public static func sendToBack(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        let order = document.annotations.map(\.id)
        return ReorderAnnotations(name: CommandName.sendToBack, newOrder: order.filter { ids.contains($0) } + order.filter { !ids.contains($0) }, in: document)
    }

    public static func bringForward(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        var order = document.annotations.map(\.id)
        var i = order.count - 2
        while i >= 0 {
            if ids.contains(order[i]) && !ids.contains(order[i + 1]) { order.swapAt(i, i + 1) }
            i -= 1
        }
        return ReorderAnnotations(name: CommandName.bringForward, newOrder: order, in: document)
    }

    public static func sendBackward(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        var order = document.annotations.map(\.id)
        var i = 1
        while i < order.count {
            if ids.contains(order[i]) && !ids.contains(order[i - 1]) { order.swapAt(i - 1, i) }
            i += 1
        }
        return ReorderAnnotations(name: CommandName.sendBackward, newOrder: order, in: document)
    }
}

public struct UpdateCanvasStyle: EditCommand {
    public let name: String
    public let before: CanvasStyle
    public let after: CanvasStyle

    public init(before: CanvasStyle, after: CanvasStyle, name: String = CommandName.canvasStyle) {
        self.before = before
        self.after = after
        self.name = name
    }

    public func apply(to document: inout PinxelDocument) { document.canvasStyle = after }
    public func revert(on document: inout PinxelDocument) { document.canvasStyle = before }
}

public struct CommandGroup: EditCommand {
    public let name: String
    public let commands: [any EditCommand]

    public init(name: String, commands: [any EditCommand]) {
        self.name = name
        self.commands = commands
    }

    public func apply(to document: inout PinxelDocument) {
        for command in commands { command.apply(to: &document) }
    }

    public func revert(on document: inout PinxelDocument) {
        for command in commands.reversed() { command.revert(on: &document) }
    }
}

/// Moves the content rectangle to start at (0,0) and fits the canvas to it; the session adds it after every command.
/// Keeps the previous annotations: undo is exact even with non-normalized rectangles.
public struct FitCanvas: EditCommand {
    public let name = CommandName.fitCanvas
    /// Shift applied to all objects, in whole document pixels.
    public let offset: CGVector
    public let sizeAfter: PixelSize
    private let sizeBefore: PixelSize
    private let annotationsBefore: [Annotation]

    /// `nil` if the canvas already fits the content.
    public init?(in document: PinxelDocument) {
        let limit = PinxelDocument.maxImageSide
        let target = ContentFit.bounds(of: document.annotations)
        let offset = target.map { CGVector(dx: Double(-$0.x), dy: Double(-$0.y)) } ?? .zero
        let size = target.map { PixelSize(width: min($0.width, limit), height: min($0.height, limit)) } ?? PixelSize(width: 0, height: 0)
        guard offset != .zero || size != document.canvasSize else { return nil }
        self.offset = offset
        sizeAfter = size
        sizeBefore = document.canvasSize
        annotationsBefore = document.annotations
    }

    public func apply(to document: inout PinxelDocument) {
        let dx = offset.dx, dy = offset.dy
        let mapping = PointMapping { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        document.annotations = offset == .zero ? annotationsBefore : annotationsBefore.map { $0.transformed(by: mapping) }
        document.canvasSize = sizeAfter
    }

    public func revert(on document: inout PinxelDocument) {
        document.annotations = annotationsBefore
        document.canvasSize = sizeBefore
    }
}
