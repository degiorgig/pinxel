// With the macOS 27 SDK, Foundation alone exposes CGPoint/CGRect/CGSize without the
// CoreGraphics API (`.null`, init with Int, Codable/Equatable). The model uses these types
// in its public interface, so CoreGraphics is re-exported to whoever imports DocumentModel.
@_exported import CoreGraphics
