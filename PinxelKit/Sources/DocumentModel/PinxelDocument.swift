import Foundation

/// Riferimento a un'immagine dentro l'archivio `.pinxel` (es. "background.png", "assets/<uuid>.png").
public struct ImageAssetRef: Codable, Hashable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}
