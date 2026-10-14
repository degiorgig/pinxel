import Foundation

/// Modifica reversibile del documento. Per ogni comando creato da un documento `d`,
/// `apply` seguito da `revert` deve restituire esattamente `d`.
public protocol EditCommand: Sendable {
    /// Nome mostrato in "Annulla <nome>".
    var name: String { get }
    func apply(to document: inout PinxelDocument)
    func revert(on document: inout PinxelDocument)
}

public struct AddAnnotations: EditCommand {
    public let name: String
    public let annotations: [Annotation]
    public let index: Int?

    public init(_ annotations: [Annotation], at index: Int? = nil, name: String = "Aggiungi") {
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

    public init(ids: Set<UUID>, in document: PinxelDocument, name: String = "Elimina") {
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

    public init(name: String = "Modifica", before: [Annotation], after: [Annotation]) {
        self.name = name
        self.before = before
        self.after = after
    }

    public func apply(to document: inout PinxelDocument) { replace(with: after, in: &document) }
    public func revert(on document: inout PinxelDocument) { replace(with: before, in: &document) }

    /// Unisce due modifiche consecutive sugli stessi oggetti (es. spostamenti con le frecce).
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

public struct ReorderAnnotations: EditCommand {
    public let name: String
    private let before: [UUID]
    private let after: [UUID]

    public init(name: String = "Disponi", newOrder: [UUID], in document: PinxelDocument) {
        self.name = name
        before = document.annotations.map(\.id)
        after = newOrder
    }

    public func apply(to document: inout PinxelDocument) { reorder(&document, to: after) }
    public func revert(on document: inout PinxelDocument) { reorder(&document, to: before) }

    private func reorder(_ document: inout PinxelDocument, to order: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: document.annotations.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        let listed = Set(order)
        // Le annotazioni non elencate restano in cima, nel loro ordine.
        document.annotations = ordered + document.annotations.filter { !listed.contains($0.id) }
    }

    public static func bringToFront(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        let order = document.annotations.map(\.id)
        return ReorderAnnotations(name: "Porta in primo piano", newOrder: order.filter { !ids.contains($0) } + order.filter { ids.contains($0) }, in: document)
    }

    public static func sendToBack(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        let order = document.annotations.map(\.id)
        return ReorderAnnotations(name: "Porta in fondo", newOrder: order.filter { ids.contains($0) } + order.filter { !ids.contains($0) }, in: document)
    }

    public static func bringForward(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        var order = document.annotations.map(\.id)
        var i = order.count - 2
        while i >= 0 {
            if ids.contains(order[i]) && !ids.contains(order[i + 1]) { order.swapAt(i, i + 1) }
            i -= 1
        }
        return ReorderAnnotations(name: "Porta avanti", newOrder: order, in: document)
    }

    public static func sendBackward(_ ids: Set<UUID>, in document: PinxelDocument) -> ReorderAnnotations {
        var order = document.annotations.map(\.id)
        var i = 1
        while i < order.count {
            if ids.contains(order[i]) && !ids.contains(order[i - 1]) { order.swapAt(i - 1, i) }
            i += 1
        }
        return ReorderAnnotations(name: "Porta indietro", newOrder: order, in: document)
    }
}

public struct ApplyImageOperation: EditCommand {
    public let operation: ImageOperation
    private let annotationsBefore: [Annotation]

    public var name: String { operation.name }

    public init(_ operation: ImageOperation, in document: PinxelDocument) {
        self.operation = operation
        annotationsBefore = document.annotations
    }

    public func apply(to document: inout PinxelDocument) {
        let mapping = operation.mapping(from: document.imageSize)
        document.annotations = annotationsBefore.map { $0.transformed(by: mapping) }
        document.imageOperations.append(operation)
    }

    public func revert(on document: inout PinxelDocument) {
        if !document.imageOperations.isEmpty { document.imageOperations.removeLast() }
        document.annotations = annotationsBefore
    }
}

public struct UpdateCanvasStyle: EditCommand {
    public let name: String
    public let before: CanvasStyle
    public let after: CanvasStyle

    public init(before: CanvasStyle, after: CanvasStyle, name: String = "Stile tela") {
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
