import CoreGraphics

/// Immagini di un rettangolo dello schermo, una alla volta, per la cattura a scorrimento.
@MainActor
public protocol RegionFrameSource {
    /// Prepara la cattura dopo che le finestre di Pinxel (cornice, pannello) sono comparse, per escluderle.
    func prepare(display: DisplayInfo) async throws
    /// `rect` in punti globali con origine in alto a sinistra; l'immagine è alla risoluzione dello schermo.
    func frame(of rect: CGRect, on display: DisplayInfo) async throws -> CGImage
}

public extension RegionFrameSource {
    func prepare(display: DisplayInfo) async throws {}
}
