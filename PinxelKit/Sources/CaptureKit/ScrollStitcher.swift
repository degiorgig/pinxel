import CoreGraphics
import Foundation

/// Outcome of adding a frame to `ScrollStitcher`.
public enum StitchStep: Equatable, Sendable {
    /// First frame: it becomes the start of the image.
    case first
    /// The content moved down; these rows were added (0 if they had already been captured).
    case appended(Int)
    /// No movement (end of page or content at rest).
    case unchanged
    /// The content moved up: only the position is updated.
    case movedBack
    /// Uniform content with no hint: frame discarded.
    case ambiguous
    /// No recognizable overlap: frame discarded, the previous frame stays the reference.
    case noMatch
    /// Maximum height reached: the image ends here.
    case reachedLimit
    /// Frame with a different size from the first.
    case sizeMismatch
}

/// Stitches the frames of an area that scrolls vertically (spec §4). Pure logic: no screens or events.
/// It is a class because it keeps the image in a buffer reserved once (no copies at every step).
public final class ScrollStitcher: @unchecked Sendable {
    static let blocks = 32
    /// Most different blocks ignored when comparing two rows (see `distance`).
    static let ignoredBlocks = 2
    /// Blocks that count in the comparison.
    static var comparedBlocks: Int { blocks - ignoredBlocks }
    /// Mean error (0–255) below which two rows match.
    static let matchThreshold = 3.0
    /// Margin around the best one within which shifts move on to the next phase of the search.
    static let tieTolerance = 0.75
    /// Shifts compared over all rows, at the end.
    static let finalists = 16
    /// Moved blocks needed for a row to count in the comparison of only the parts that move.
    static let minimumMovingBlocks = 8

    /// Two shifts are equivalent if the second one's error exceeds the best one's by a small amount, absolute or in
    /// proportion: between real frames even the right shift has a small error.
    static func ties(_ error: Double, best: Double) -> Bool {
        error <= best + max(0.15, best * 0.3)
    }
    /// A row whose difference between the lightest and darkest block is below this threshold is uniform (white, solid color):
    /// it says nothing about the shift and does not enter the comparison.
    static let uniformRowRange: Int16 = 4
    /// Rows with detail needed for a shift to be judgeable.
    static let minimumInformativeRows = 4
    /// Rows with detail compared at most, per frame, in the coarse search and in the fine one.
    static let coarseRows = 40
    static let fineRows = 300
    /// Share of the worst rows ignored in the fallback comparison: a row highlighted under the resting pointer stays
    /// at the same screen position while the content scrolls, and must not cause the right shift to be discarded.
    static let ignoredWorstRows = 0.3
    /// A first change touching fewer than this fraction of the rows (highlighting, text cursor) is not a
    /// scroll: it is not used to recognize the fixed bands.
    static let moveFraction = 8

    struct Frame {
        let bytes: [UInt8]
        /// One signature per row: the mean gray of `blocks` horizontal blocks.
        let signatures: [SIMD32<Int16>]
        /// Rows with detail, from the top.
        let informative: [Bool]
    }

    enum Match {
        case shift(Int)
        case ambiguous
        case noMatch
    }

    public let maxHeight: Int
    public private(set) var width = 0
    public private(set) var frameHeight = 0
    public private(set) var topBand = 0
    public private(set) var bottomBand = 0
    /// Shift of the last recognized frame, in pixels.
    public private(set) var lastShift: Int?
    private var bandsKnown = false
    /// Top band + scrolling content, premultiplied sRGB RGBA, rows from the top.
    private var canvas: PixelRows?
    /// Bottom band of the frame that reached the end of the capture: it goes at the bottom of the image.
    private var bottomRows: [UInt8] = []
    private var previous: Frame?
    /// Content row at the top of the scrolling zone of the reference frame.
    private var position = 0
    /// Rows of scrolling content in the image: from `firstRow` (negative if scrolled up past the start) to `captured`.
    private var firstRow = 0
    private var captured = 0
    /// For each content row in the image, how far it was from the center of the scrolling zone in the frame it
    /// comes from: the most central copy is kept, away from what stays fixed at the edges (the "scroll to bottom" button of a
    /// chat, a date that appears at the top).
    private var rowDistance: [Int32] = []

    public init(maxHeight: Int) {
        self.maxHeight = maxHeight
    }

    private var rowBytes: Int { width * 4 }
    /// Height in pixels of the scrolling part, without fixed bands.
    public var regionHeight: Int { frameHeight - topBand - bottomBand }
    /// Minimum overlap between two frames for the shift to be measurable.
    public var minimumOverlap: Int { max(8, regionHeight / 4) }
    /// Maximum measurable shift between two frames: whoever scrolls faster loses the reference.
    public var maxShift: Int { max(0, regionHeight - minimumOverlap) }
    public var height: Int { rowBytes == 0 ? 0 : (canvas?.rows ?? 0) + bottomRows.count / rowBytes }

    /// `hint`: the expected shift in pixels, if known; it decides between equivalent shifts and in stretches without detail.
    public func add(_ image: CGImage, hint: Int?) -> StitchStep {
        guard let previous else {
            width = image.width
            frameHeight = image.height
            let frame = Self.makeFrame(image)
            let rows = min(frameHeight, maxHeight)
            let canvas = PixelRows(rowBytes: rowBytes, capacityRows: maxHeight)
            frame.bytes.withUnsafeBytes { canvas.append($0.baseAddress!, rows: rows) }
            self.canvas = canvas
            captured = rows
            rowDistance = (0..<rows).map { Int32(abs($0 - frameHeight / 2)) }
            self.previous = frame
            return rows < frameHeight ? .reachedLimit : .first
        }
        guard image.width == width, image.height == frameHeight else { return .sizeMismatch }
        let frame = Self.makeFrame(image)
        if Self.equal(frame.bytes, previous.bytes) { return .unchanged }
        if !bandsKnown, Self.changedRows(previous, frame) * Self.moveFraction >= frameHeight { detectBands(previous, frame) }

        switch match(previous, frame, hint: hint) {
        case .ambiguous:
            return .ambiguous
        case .noMatch:
            return .noMatch
        case .shift(let shift):
            self.previous = frame
            lastShift = shift
            if shift == 0 { return .unchanged }
            // The first movement has happened: from here on the bands are no longer searched for (the image is no longer a single frame).
            bandsKnown = true
            position += shift
            refresh(from: frame)
            if position < firstRow { return prepend(from: frame) }
            if shift < 0 { return .movedBack }
            let newBottom = position + regionHeight
            guard newBottom >= captured else { return .appended(0) }
            // This frame reaches the end of the capture: its bottom band is the one that closes the image.
            bottomRows = Array(frame.bytes[(frameHeight - bottomBand) * rowBytes ..< frameHeight * rowBytes])
            guard newBottom > captured, let canvas else { return .appended(0) }
            let wanted = newBottom - captured
            let room = max(0, maxHeight - (canvas.rows + bottomBand))
            let rows = min(wanted, room)
            let start = topBand + regionHeight - wanted
            frame.bytes.withUnsafeBytes { canvas.append($0.baseAddress! + start * rowBytes, rows: rows) }
            rowDistance += (0..<rows).map { Int32(abs(regionHeight - wanted + $0 - regionHeight / 2)) }
            captured += rows
            return rows < wanted ? .reachedLimit : .appended(rows)
        }
    }

    /// Rows at the top and bottom identical at the same position while the center changes: fixed headers and bars.
    /// At most a quarter of the frame each. Decided once, at the first movement; if white rows of the
    /// content are mistaken for a band the result is still right, because the final bottom band comes
    /// from the last frame and the top one from the first.
    private func detectBands(_ old: Frame, _ new: Frame) {
        bandsKnown = true
        let limit = frameHeight / 4
        let rowBytes = rowBytes
        func same(_ row: Int) -> Bool {
            old.bytes.withUnsafeBytes { a in
                new.bytes.withUnsafeBytes { b in memcmp(a.baseAddress! + row * rowBytes, b.baseAddress! + row * rowBytes, rowBytes) == 0 }
            }
        }
        var top = 0
        while top < limit, same(top) { top += 1 }
        var bottom = 0
        while bottom < limit, same(frameHeight - 1 - bottom) { bottom += 1 }
        topBand = top
        bottomBand = bottom
        // So far the image is the whole first frame: the bottom band must be removed and put back at the bottom at the end.
        guard let canvas else { return }
        let keep = min(canvas.rows, frameHeight - bottom)
        canvas.truncate(to: keep)
        bottomRows = Array(old.bytes[(frameHeight - bottom) * rowBytes ..< frameHeight * rowBytes])
        captured = keep - top
        firstRow = 0
        position = 0
        rowDistance = (0..<captured).map { Int32(abs($0 - regionHeight / 2)) }
    }

    /// Scrolled up past the first captured row: the uncovered rows go at the top, below the top band, which comes
    /// from this frame just as the bottom one comes from the last frame at the bottom.
    private func prepend(from frame: Frame) -> StitchStep {
        guard let canvas else { return .appended(0) }
        let wanted = firstRow - position
        let room = max(0, maxHeight - (canvas.rows + bottomBand))
        let rows = min(wanted, room)
        guard rows > 0 else { return .reachedLimit }
        frame.bytes.withUnsafeBytes { source in
            // The ones closest to those already captured, if there is no room for all of them.
            canvas.insert(source.baseAddress! + (topBand + wanted - rows) * rowBytes, rows: rows, after: topBand)
            memcpy(canvas.pointer, source.baseAddress!, topBand * rowBytes)
        }
        rowDistance.insert(contentsOf: (0..<rows).map { Int32(abs(wanted - rows + $0 - regionHeight / 2)) }, at: 0)
        firstRow -= rows
        return rows < wanted ? .reachedLimit : .appended(rows)
    }

    /// The rows already in the image that are closest to the center in this frame take its pixels.
    private func refresh(from frame: Frame) {
        guard let canvas else { return }
        let rowBytes = rowBytes, center = regionHeight / 2
        frame.bytes.withUnsafeBytes { source in
            for y in 0..<regionHeight {
                let row = position + y - firstRow
                guard row >= 0, position + y < captured else { continue }
                let distance = Int32(abs(y - center))
                guard distance < rowDistance[row] else { continue }
                memcpy(canvas.pointer + (topBand + row) * rowBytes, source.baseAddress! + (topBand + y) * rowBytes, rowBytes)
                rowDistance[row] = distance
            }
        }
    }

    private func match(_ old: Frame, _ new: Frame, hint: Int?) -> Match {
        let region = regionHeight
        let limit = maxShift
        guard limit > 0 else { return .noMatch }
        let range = -limit...limit
        // Rows with detail of the scrolling zone, in the two frames (indices relative to the zone).
        let oldRows = (0..<region).filter { old.informative[topBand + $0] }
        let newRows = (0..<region).filter { new.informative[topBand + $0] }
        guard oldRows.count + newRows.count >= Self.minimumInformativeRows else {
            // No detail (white stretch): the hint decides, if there is one and it is measurable.
            guard let hint, range.contains(hint) else { return hint == nil ? .ambiguous : .noMatch }
            return .shift(hint)
        }
        // Coarse search over a few rows, then fine search over the candidates close to the best one.
        let coarseOld = Self.thin(oldRows, to: Self.coarseRows), coarseNew = Self.thin(newRows, to: Self.coarseRows)
        var coarse: [(shift: Int, error: Double)] = []
        coarse.reserveCapacity(range.count)
        for shift in range {
            if let error = error(old, new, shift: shift, oldRows: coarseOld, newRows: coarseNew) { coarse.append((shift, error)) }
        }
        guard let coarseBest = coarse.min(by: { $0.error < $1.error }) else { return hint == nil ? .ambiguous : .noMatch }
        let fineOld = Self.thin(oldRows, to: Self.fineRows), fineNew = Self.thin(newRows, to: Self.fineRows)
        var errors: [(shift: Int, error: Double)] = []
        for candidate in coarse where candidate.error <= coarseBest.error + 4 * Self.tieTolerance + 1 {
            if let error = error(old, new, shift: candidate.shift, oldRows: fineOld, newRows: fineNew) { errors.append((candidate.shift, error)) }
        }
        // The best ones are compared over all rows with detail: with few sampled rows a wrong shift
        // on repeating content (cards, tables) can look as good as the right one.
        let fineBest = errors.min(by: { $0.error < $1.error })?.error ?? 0
        let finalists = errors.filter { $0.error <= fineBest + 2 * Self.tieTolerance }.sorted { $0.error < $1.error }.prefix(Self.finalists)
        errors = finalists.compactMap { candidate in
            error(old, new, shift: candidate.shift, oldRows: oldRows, newRows: newRows).map { (candidate.shift, $0) }
        }
        guard let best = errors.min(by: { $0.error < $1.error }), best.error <= Self.matchThreshold else {
            // No shift matches entirely: perhaps a few rows resting on the screen (a highlight) are interfering.
            // Ignoring them, a shift that matches with no equivalent alternatives is the right one.
            if let shift = robustShift(old, new, range: range, oldRows: oldRows, newRows: newRows) { return .shift(shift) }
            // Perhaps a background stays still while the content scrolls (a chat's wallpaper, a fixed column):
            // comparing only the parts that moved, the right shift matches again.
            if let shift = movingPartShift(old, new, range: range) { return .shift(shift) }
            // No verifiable shift matches. If the expected one is not contradicted by any row (the rows with
            // detail fall outside the overlap, as in a white stretch), it is the most credible.
            if let hint, range.contains(hint),
               error(old, new, shift: hint, oldRows: fineOld, newRows: fineNew) == nil,
               !Self.contradicts(old, new, shift: hint, region: region, topBand: topBand) {
                return .shift(hint)
            }
            return .noMatch
        }
        let candidates = errors.filter { Self.ties($0.error, best: best.error) }.map(\.shift)
        let spread = candidates.max()! - candidates.min()!
        guard spread > 2 else { return .shift(best.shift) }
        // Several equivalent shifts (uniform or repeating content): the hint decides, if there is one and it is measurable;
        // out of range means the content has gone past it, and the candidate on the edge would be wrong.
        guard let hint else { return .ambiguous }
        guard range.contains(hint) else { return .noMatch }
        return .shift(candidates.min { abs($0 - hint) < abs($1 - hint) }!)
    }

    /// The shift that matches when comparing only the blocks that changed in place between the two frames, if there is only one
    /// (within 2 pixels). Blocks that stayed the same are resting background: they count equally for every shift and
    /// would mask the right one.
    private func movingPartShift(_ old: Frame, _ new: Frame, range: ClosedRange<Int>) -> Int? {
        let region = regionHeight
        // For each row of the scrolling zone, the blocks that changed in place.
        let moving: [SIMDMask<SIMD32<Int16>>] = (0..<region).map { r in
            let difference = old.signatures[topBand + r] &- new.signatures[topBand + r]
            let absolute = difference.replacing(with: 0 &- difference, where: difference .< 0)
            return absolute .> 1
        }
        let rows = (0..<region).filter { r in Self.count(moving[r]) >= Self.minimumMovingBlocks }
        guard rows.count >= Self.minimumInformativeRows else { return nil }
        func error(_ shift: Int, rows: [Int]) -> Double? {
            var total = 0, lanes = 0, compared = 0
            for r in rows {
                let n = r - shift
                guard n >= 0, n < region else { continue }
                let both = moving[r] .& moving[n]
                let blocks = Self.count(both)
                guard blocks >= Self.minimumMovingBlocks else { continue }
                let difference = old.signatures[topBand + r] &- new.signatures[topBand + n]
                let absolute = difference.replacing(with: 0 &- difference, where: difference .< 0)
                // For the row, the half of the blocks that match best counts: a block that is resting background
                // in one frame and content in the other does not match even with the right shift.
                var values = (0..<32).filter { both[$0] }.map { Int(absolute[$0]) }
                values.sort()
                let kept = max(Self.minimumMovingBlocks / 2, values.count / 2)
                total += values.prefix(kept).reduce(0, +)
                lanes += kept
                compared += 1
            }
            guard compared >= Self.minimumInformativeRows else { return nil }
            return Double(total) / Double(lanes)
        }
        let coarseRows = Self.thin(rows, to: Self.coarseRows)
        var coarse: [(shift: Int, error: Double)] = []
        for shift in range where shift != 0 {
            if let value = error(shift, rows: coarseRows) { coarse.append((shift, value)) }
        }
        guard let coarseBest = coarse.min(by: { $0.error < $1.error }) else { return nil }
        let finalists = coarse.filter { $0.error <= coarseBest.error + 4 * Self.tieTolerance + 1 }
            .sorted { $0.error < $1.error }.prefix(Self.finalists)
        let errors = finalists.compactMap { candidate in error(candidate.shift, rows: rows).map { (shift: candidate.shift, error: $0) } }
        guard let best = errors.min(by: { $0.error < $1.error }), best.error <= Self.matchThreshold else { return nil }
        let candidates = errors.filter { Self.ties($0.error, best: best.error) }.map(\.shift)
        return candidates.max()! - candidates.min()! <= 2 ? best.shift : nil
    }

    static func count(_ mask: SIMDMask<SIMD32<Int16>>) -> Int {
        Int(SIMD32<Int16>(repeating: 0).replacing(with: 1, where: mask).wrappedSum())
    }

    /// The shift that matches when ignoring the worst rows, if there is only one (within 2 pixels).
    private func robustShift(_ old: Frame, _ new: Frame, range: ClosedRange<Int>, oldRows: [Int], newRows: [Int]) -> Int? {
        let coarseOld = Self.thin(oldRows, to: Self.coarseRows), coarseNew = Self.thin(newRows, to: Self.coarseRows)
        var coarse: [(shift: Int, error: Double)] = []
        for shift in range {
            if let error = error(old, new, shift: shift, oldRows: coarseOld, newRows: coarseNew, ignoringWorst: true) { coarse.append((shift, error)) }
        }
        guard let coarseBest = coarse.min(by: { $0.error < $1.error }) else { return nil }
        let fineOld = Self.thin(oldRows, to: Self.fineRows), fineNew = Self.thin(newRows, to: Self.fineRows)
        var errors: [(shift: Int, error: Double)] = []
        for candidate in coarse where candidate.error <= coarseBest.error + 4 * Self.tieTolerance + 1 {
            if let error = error(old, new, shift: candidate.shift, oldRows: fineOld, newRows: fineNew, ignoringWorst: true) {
                errors.append((candidate.shift, error))
            }
        }
        guard let best = errors.min(by: { $0.error < $1.error }), best.error <= Self.matchThreshold else { return nil }
        let candidates = errors.filter { $0.error <= best.error + Self.tieTolerance }.map(\.shift)
        return candidates.max()! - candidates.min()! <= 2 ? best.shift : nil
    }

    /// True if at least one row with detail, in either frame, falls in the overlap on a different row.
    static func contradicts(_ old: Frame, _ new: Frame, shift: Int, region: Int, topBand: Int) -> Bool {
        for r in 0..<region where old.informative[topBand + r] {
            let n = r - shift
            if n >= 0, n < region, distance(old.signatures[topBand + r], new.signatures[topBand + n]) > Int16(matchThreshold) * Int16(comparedBlocks) {
                return true
            }
        }
        for n in 0..<region where new.informative[topBand + n] {
            let r = n + shift
            if r >= 0, r < region, distance(old.signatures[topBand + r], new.signatures[topBand + n]) > Int16(matchThreshold) * Int16(comparedBlocks) {
                return true
            }
        }
        return false
    }

    /// Rows whose signature changed at the same position.
    static func changedRows(_ old: Frame, _ new: Frame) -> Int {
        zip(old.signatures, new.signatures).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) }
    }

    /// Rows evenly distributed, at most `count`.
    static func thin(_ rows: [Int], to count: Int) -> [Int] {
        guard rows.count > count else { return rows }
        return (0..<count).map { rows[$0 * rows.count / count] }
    }

    /// Mean error between the rows that overlap with this shift, counting only those with detail in
    /// at least one of the two frames (with `ignoringWorst`, without the worst ones); `nil` if there are too few to judge.
    private func error(_ old: Frame, _ new: Frame, shift: Int, oldRows: [Int], newRows: [Int], ignoringWorst: Bool = false) -> Double? {
        let region = regionHeight
        var distances: [Int16] = []
        distances.reserveCapacity(oldRows.count + newRows.count)
        // Row `r` of the old frame ↔ row `r - shift` of the new one.
        for r in oldRows {
            let n = r - shift
            guard n >= 0, n < region else { continue }
            distances.append(Self.distance(old.signatures[topBand + r], new.signatures[topBand + n]))
        }
        for n in newRows {
            let r = n + shift
            guard r >= 0, r < region, !old.informative[topBand + r] else { continue }
            distances.append(Self.distance(old.signatures[topBand + r], new.signatures[topBand + n]))
        }
        guard distances.count >= Self.minimumInformativeRows else { return nil }
        var kept = distances.count
        if ignoringWorst {
            distances.sort()
            kept = max(Self.minimumInformativeRows, Int((Double(distances.count) * (1 - Self.ignoredWorstRows)).rounded(.up)))
        }
        let total = distances[..<kept].reduce(0) { $0 + Int($1) }
        return Double(total) / Double(kept * Self.comparedBlocks)
    }

    /// Difference between two rows without the `ignoredBlocks` most different blocks: a column that changes on its own, like the
    /// scroll bar that appears while scrolling, would weigh the same on all shifts and would mask the right one.
    static func distance(_ a: SIMD32<Int16>, _ b: SIMD32<Int16>) -> Int16 {
        let difference = a &- b
        let absolute = difference.replacing(with: 0 &- difference, where: difference .< 0)
        let worst = absolute.max()
        let others = absolute.replacing(with: 0, where: absolute .== worst)
        let worstCount = SIMD32<Int16>(repeating: 0).replacing(with: 1, where: absolute .== worst).wrappedSum()
        let second = worstCount > 1 ? worst : others.max()
        return absolute.wrappedSum() &- worst &- second
    }

    static func equal(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        return a.withUnsafeBytes { x in b.withUnsafeBytes { y in memcmp(x.baseAddress!, y.baseAddress!, a.count) == 0 } }
    }

    static func makeFrame(_ image: CGImage) -> Frame {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var signatures = [SIMD32<Int16>](repeating: .zero, count: height)
        var informative = [Bool](repeating: false, count: height)
        let bounds = (0...blocks).map { min(width, $0 * width / blocks) }
        bytes.withUnsafeBufferPointer { pixels in
            for y in 0..<height {
                let row = y * width * 4
                var signature = SIMD32<Int16>.zero
                for block in 0..<blocks {
                    let x0 = min(bounds[block], width - 1)
                    let x1 = max(x0 + 1, bounds[block + 1])
                    var sum = 0
                    var p = row + x0 * 4
                    for _ in x0..<x1 {
                        sum += (Int(pixels[p]) * 77 + Int(pixels[p + 1]) * 150 + Int(pixels[p + 2]) * 29) >> 8
                        p += 4
                    }
                    signature[block] = Int16(sum / (x1 - x0))
                }
                signatures[y] = signature
                informative[y] = signature.max() - signature.min() >= uniformRowRange
            }
        }
        return Frame(bytes: bytes, signatures: signatures, informative: informative)
    }

    /// The image stitched so far (a copy: the capture can continue).
    public func image() -> CGImage? {
        guard let canvas, rowBytes > 0 else { return nil }
        var bytes = Data(bytes: canvas.pointer, count: canvas.rows * rowBytes)
        bytes.append(contentsOf: bottomRows)
        return Self.makeImage(data: bytes, width: width)
    }

    /// The final image, without copying it: the bottom band goes at the end of the buffer, which is handed to the image.
    /// After this call no more frames are added.
    public func finalImage() -> CGImage? {
        guard let canvas, rowBytes > 0 else { return nil }
        let bottom = bottomRows.count / rowBytes
        if bottom > 0, canvas.rows + bottom <= canvas.capacityRows {
            bottomRows.withUnsafeBytes { canvas.append($0.baseAddress!, rows: bottom) }
            bottomRows = []
        }
        previous = nil
        return canvas.makeImage(width: width)
    }

    /// Thumbnail `width` pixels wide for the panel, sampling the rows without copying the whole image.
    public func thumbnail(width thumbnailWidth: Int) -> CGImage? {
        let total = height
        guard let canvas, rowBytes > 0, total > 0, thumbnailWidth > 0 else { return nil }
        let thumbnailHeight = max(1, total * thumbnailWidth / width)
        var bytes = [UInt8](repeating: 0, count: thumbnailWidth * thumbnailHeight * 4)
        let canvasRows = canvas.rows
        bottomRows.withUnsafeBytes { bottom in
            bytes.withUnsafeMutableBytes { target in
                for y in 0..<thumbnailHeight {
                    let sourceRow = min(total - 1, y * total / thumbnailHeight)
                    let row = sourceRow < canvasRows
                        ? UnsafeRawPointer(canvas.pointer + sourceRow * rowBytes)
                        : bottom.baseAddress! + (sourceRow - canvasRows) * rowBytes
                    for x in 0..<thumbnailWidth {
                        let sourceX = min(width - 1, x * width / thumbnailWidth)
                        memcpy(target.baseAddress! + (y * thumbnailWidth + x) * 4, row + sourceX * 4, 4)
                    }
                }
            }
        }
        return Self.makeImage(data: Data(bytes), width: thumbnailWidth)
    }

    static func makeImage(data: Data, width: Int) -> CGImage? {
        let height = data.count / (width * 4)
        guard height > 0, let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// RGBA rows in a buffer reserved for the maximum height: virtual memory is only used when written to,
/// and the final image uses the buffer without copying it.
final class PixelRows: @unchecked Sendable {
    let rowBytes: Int
    let capacityRows: Int
    private let base: UnsafeMutableRawPointer
    /// First occupied row of the buffer: the free space in front allows adding rows at the top without moving everything.
    private var start = 0
    private(set) var rows = 0

    init(rowBytes: Int, capacityRows: Int) {
        self.rowBytes = rowBytes
        self.capacityRows = capacityRows
        base = UnsafeMutableRawPointer.allocate(byteCount: max(1, rowBytes * capacityRows), alignment: 16)
    }

    deinit {
        base.deallocate()
    }

    /// The first row.
    var pointer: UnsafeMutableRawPointer { base + start * rowBytes }

    func append(_ source: UnsafeRawPointer, rows count: Int) {
        let count = min(count, capacityRows - rows)
        guard count > 0 else { return }
        if start + rows + count > capacityRows { move(to: (capacityRows - rows - count) / 2) }
        memcpy(pointer + rows * rowBytes, source, count * rowBytes)
        rows += count
    }

    /// Inserts `count` rows after the first `after`.
    func insert(_ source: UnsafeRawPointer, rows count: Int, after: Int) {
        let count = min(count, capacityRows - rows)
        guard count > 0 else { return }
        if start < count {
            let free = capacityRows - rows
            move(to: count + (free - count) / 2)
        }
        start -= count
        if after > 0 { memmove(pointer, pointer + count * rowBytes, after * rowBytes) }
        memcpy(pointer + after * rowBytes, source, count * rowBytes)
        rows += count
    }

    /// Moves the rows in the buffer so that the first one is at `newStart`.
    private func move(to newStart: Int) {
        guard newStart != start else { return }
        memmove(base + newStart * rowBytes, pointer, rows * rowBytes)
        start = newStart
    }

    func truncate(to count: Int) {
        rows = max(0, min(rows, count))
    }

    /// Image that reads directly from the buffer and keeps it alive as long as needed.
    func makeImage(width: Int) -> CGImage? {
        guard rows > 0 else { return nil }
        let info = Unmanaged.passRetained(self).toOpaque()
        guard let provider = CGDataProvider(dataInfo: info, data: pointer, size: rows * rowBytes, releaseData: { info, _, _ in
            if let info { Unmanaged<PixelRows>.fromOpaque(info).release() }
        }) else {
            Unmanaged<PixelRows>.fromOpaque(info).release()
            return nil
        }
        return CGImage(width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
