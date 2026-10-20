import Foundation
import Persistence
import UniformTypeIdentifiers

public enum ExportFileType: String, CaseIterable, Sendable {
    case png, jpeg, heic, pdf

    public var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .pdf: "PDF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .pdf: "pdf"
        }
    }

    public var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .pdf: .pdf
        }
    }

    public var hasQuality: Bool { self == .jpeg || self == .heic }
}

/// Choices of the Export… panel translated into `Exporter` formats (spec §9).
public struct ExportChoice: Equatable, Sendable {
    private static let replaceableExtensions: Set<String> = ["pinxel", "png", "jpg", "jpeg", "heic", "pdf"]

    public var fileType: ExportFileType = .png
    /// 0...100.
    public var quality: Double = 90
    public var scale: ExportScale

    /// For a Retina capture the default is 2x (native pixels), otherwise 1x.
    public init(documentScale: Double) {
        scale = documentScale >= 2 ? .twoX : .oneX
    }

    public var format: ExportFormat {
        let normalized = min(max(quality, 0), 100) / 100
        switch fileType {
        case .png: return .png
        case .jpeg: return .jpeg(quality: normalized)
        case .heic: return .heic(quality: normalized)
        case .pdf: return .pdf
        }
    }

    /// Name with the extension of the chosen format; replaces only known extensions.
    public func fileName(from baseName: String) -> String {
        let name = baseName as NSString
        let base = Self.replaceableExtensions.contains(name.pathExtension.lowercased()) ? name.deletingPathExtension : baseName
        return (base.isEmpty ? "Pinxel" : base) + "." + fileType.fileExtension
    }
}
