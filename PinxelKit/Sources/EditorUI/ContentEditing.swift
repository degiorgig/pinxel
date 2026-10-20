import CoreGraphics
import DocumentModel
import Foundation
import Rendering

/// Crop, resize and cut and stitch on all the content (spec §5). Pure functions on the list of objects:
/// new pixels go through `add`, which registers them among the document's images.
public enum ContentEditing {
    public typealias Images = (ImageAssetRef) -> CGImage?
    public typealias AddImage = (CGImage) -> ImageAssetRef?

    /// Images cut by the frame lose the pixels outside it; objects entirely outside disappear;
    /// annotations and rotated images straddling the edge stay whole.
    public static func cropped(_ annotations: [Annotation], to rect: PixelRect, images: Images, add: AddImage) -> [Annotation] {
        let area = rect.cgRect
        return annotations.compactMap { annotation in
            let bounds = annotation.visualBounds
            guard !bounds.isNull, bounds.intersects(area) else { return nil }
            guard case .image(var data) = annotation.kind, annotation.rotation == 0 else { return annotation }
            let frame = data.rect.standardized
            guard !area.contains(frame) else { return annotation }
            let inside = frame.intersection(area)
            // Only the shadow falls inside the frame: the pixels are all outside.
            guard !inside.isNull, !inside.isEmpty else { return nil }
            var copy = annotation
            if let source = images(data.asset), let part = crop(source, frame: frame, to: inside), let ref = add(part) {
                data.asset = ref
            }
            data.rect = inside
            copy.kind = .image(data)
            return copy
        }
    }

    /// All the content scaled relative to the top-left corner; images only change their frame.
    public static func scaled(_ annotations: [Annotation], from size: PixelSize, to target: PixelSize) -> [Annotation] {
        let mapping = ImageOperation.resize(target).mapping(from: size)
        return annotations.map { $0.transformed(by: mapping) }
    }

    /// Removes the band from the non-rotated images it crosses; everything beyond it moves closer.
    public static func cut(_ annotations: [Annotation], _ cut: CutOut, canvas: PixelSize, images: Images, add: AddImage) -> [Annotation] {
        let start = Double(cut.clampedStart(in: canvas))
        let end = start + Double(cut.clampedLength(in: canvas))
        let mapping = ImageOperation.cutOut(cut).mapping(from: canvas)
        let horizontal = cut.axis == .horizontal
        return annotations.map { annotation in
            guard case .image(var data) = annotation.kind, annotation.rotation == 0 else { return annotation.transformed(by: mapping) }
            let frame = data.rect.standardized
            let low = horizontal ? frame.minY : frame.minX
            let high = horizontal ? frame.maxY : frame.maxX
            let overlap = min(end, high) - max(start, low)
            guard overlap > 0 else { return annotation.transformed(by: mapping) }
            var copy = annotation
            let pixels = images(data.asset)
            let density = pixels.map { horizontal ? Double($0.height) / frame.height : Double($0.width) / frame.width } ?? 1
            let local = CutOut(axis: cut.axis, start: Int(((max(start, low) - low) * density).rounded()),
                               length: Int((overlap * density).rounded()), edge: cut.edge)
            if let pixels, let result = BackgroundProcessor.process(pixels, operations: [.cutOut(local)]), let ref = add(result) {
                data.asset = ref
            }
            let origin = mapping.map(frame.origin)
            data.rect = horizontal
                ? CGRect(x: frame.minX, y: origin.y, width: frame.width, height: frame.height - overlap)
                : CGRect(x: origin.x, y: frame.minY, width: frame.width - overlap, height: frame.height)
            copy.kind = .image(data)
            return copy
        }
    }

    /// ⌘V with an image: it takes the place of the first image from the bottom, in the same corner, keeping the annotations;
    /// with no images it adds one at the bottom.
    public static func replacingBottomImage(in annotations: [Annotation], asset: ImageAssetRef, size: CGSize, newID: UUID) -> any EditCommand {
        if let bottom = annotations.first(where: { if case .image = $0.kind { true } else { false } }),
           case .image(var data) = bottom.kind {
            var after = bottom
            data.asset = asset
            data.rect = CGRect(origin: data.rect.standardized.origin, size: size)
            after.kind = .image(data)
            after.rotation = 0
            return UpdateAnnotations(name: CommandName.pasteImage, before: [bottom], after: [after])
        }
        let image = Annotation(id: newID, kind: .image(PlacedImageData(rect: CGRect(origin: .zero, size: size), asset: asset)),
                               style: Style(stroke: nil, lineWidth: 0))
        return AddAnnotations([image], at: 0, name: CommandName.pasteImage)
    }

    /// The image pixels that fall in `inside` (document coordinates), at the image's density.
    private static func crop(_ image: CGImage, frame: CGRect, to inside: CGRect) -> CGImage? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let sx = Double(image.width) / frame.width, sy = Double(image.height) / frame.height
        let pixels = CGRect(x: ((inside.minX - frame.minX) * sx).rounded(), y: ((inside.minY - frame.minY) * sy).rounded(),
                            width: (inside.width * sx).rounded(), height: (inside.height * sy).rounded())
        guard pixels.width >= 1, pixels.height >= 1 else { return nil }
        return image.cropping(to: pixels)
    }
}
