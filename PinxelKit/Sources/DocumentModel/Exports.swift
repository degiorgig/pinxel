// Con l'SDK di macOS 27, Foundation da sola espone CGPoint/CGRect/CGSize senza l'API
// di CoreGraphics (`.null`, init con Int, Codable/Equatable). Il modello usa questi tipi
// nell'interfaccia pubblica, quindi CoreGraphics viene riesportato a chi importa DocumentModel.
@_exported import CoreGraphics
