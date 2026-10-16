import CoreGraphics
import Foundation

/// Esito dell'aggiunta di un fotogramma a `ScrollStitcher`.
public enum StitchStep: Equatable, Sendable {
    /// Primo fotogramma: diventa l'inizio dell'immagine.
    case first
    /// Il contenuto è sceso; aggiunte queste righe (0 se erano già state catturate).
    case appended(Int)
    /// Nessuno spostamento (fine pagina o contenuto fermo).
    case unchanged
    /// Il contenuto è salito: si aggiorna solo la posizione.
    case movedBack
    /// Contenuto uniforme senza indizio: fotogramma scartato.
    case ambiguous
    /// Nessuna sovrapposizione riconoscibile: fotogramma scartato, il riferimento resta il precedente.
    case noMatch
    /// Raggiunta l'altezza massima: l'immagine finisce qui.
    case reachedLimit
    /// Fotogramma di dimensioni diverse dal primo.
    case sizeMismatch
}

/// Cuce i fotogrammi di un'area che scorre in verticale (spec §4). Logica pura: niente schermi né eventi.
public struct ScrollStitcher {
    static let blocks = 32
    /// Errore medio (0–255) sotto cui due righe combaciano.
    static let matchThreshold: Float = 3
    /// Spostamenti con errore entro questa distanza dal migliore sono equivalenti.
    static let tieTolerance: Float = 0.75
    /// Righe confrontate al massimo per ogni spostamento provato.
    static let maxSampledRows = 400

    struct Frame {
        let bytes: [UInt8]
        let signatures: [Float]
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
    private var bandsKnown = false
    /// Fascia superiore + contenuto che scorre, RGBA premoltiplicato sRGB, righe dall'alto.
    private var canvas: [UInt8] = []
    /// Fascia inferiore dell'ultimo fotogramma: va in fondo all'immagine.
    private var bottomRows: [UInt8] = []
    private var previous: Frame?
    /// Riga del contenuto in cima alla zona che scorre del fotogramma di riferimento.
    private var position = 0
    /// Righe di contenuto che scorre già nell'immagine.
    private var captured = 0

    public init(maxHeight: Int) {
        self.maxHeight = maxHeight
    }

    private var rowBytes: Int { width * 4 }
    /// Altezza in pixel della parte che scorre, senza fasce fisse.
    public var regionHeight: Int { frameHeight - topBand - bottomBand }
    public var height: Int { rowBytes == 0 ? 0 : (canvas.count + bottomRows.count) / rowBytes }

    public mutating func add(_ image: CGImage, hint: Int?) -> StitchStep {
        guard let previous else {
            width = image.width
            frameHeight = image.height
            let frame = Self.makeFrame(image)
            let rows = min(frameHeight, maxHeight)
            canvas = Array(frame.bytes[0..<rows * rowBytes])
            captured = rows
            self.previous = frame
            return rows < frameHeight ? .reachedLimit : .first
        }
        guard image.width == width, image.height == frameHeight else { return .sizeMismatch }
        let frame = Self.makeFrame(image)
        if frame.bytes == previous.bytes { return .unchanged }
        if !bandsKnown { detectBands(previous, frame) }

        switch match(previous, frame, hint: hint) {
        case .ambiguous:
            return .ambiguous
        case .noMatch:
            return .noMatch
        case .shift(let shift):
            self.previous = frame
            bottomRows = Array(frame.bytes[(frameHeight - bottomBand) * rowBytes ..< frameHeight * rowBytes])
            if shift == 0 { return .unchanged }
            position += shift
            if shift < 0 { return .movedBack }
            let newBottom = position + regionHeight
            guard newBottom > captured else { return .appended(0) }
            let wanted = newBottom - captured
            let room = max(0, maxHeight - (topBand + captured + bottomBand))
            let rows = min(wanted, room)
            let start = topBand + regionHeight - wanted
            canvas += frame.bytes[start * rowBytes ..< (start + rows) * rowBytes]
            captured += rows
            return rows < wanted ? .reachedLimit : .appended(rows)
        }
    }

    /// Righe in cima e in fondo identiche alla stessa posizione mentre il centro cambia: intestazioni e barre fisse.
    /// Al massimo un quarto del fotogramma ciascuna. Si decide una volta, al primo movimento.
    private mutating func detectBands(_ old: Frame, _ new: Frame) {
        bandsKnown = true
        let limit = frameHeight / 4
        func same(_ row: Int) -> Bool {
            old.bytes[row * rowBytes ..< (row + 1) * rowBytes] == new.bytes[row * rowBytes ..< (row + 1) * rowBytes]
        }
        var top = 0
        while top < limit, same(top) { top += 1 }
        var bottom = 0
        while bottom < limit, same(frameHeight - 1 - bottom) { bottom += 1 }
        topBand = top
        bottomBand = bottom
        // Finora l'immagine è il primo fotogramma intero: la fascia inferiore va tolta e rimessa in fondo alla fine.
        let keep = min(canvas.count / rowBytes, frameHeight - bottom)
        canvas.removeSubrange(keep * rowBytes ..< canvas.count)
        captured = keep - top
        position = 0
    }

    private func match(_ old: Frame, _ new: Frame, hint: Int?) -> Match {
        let region = regionHeight
        let minimumOverlap = max(8, region / 4)
        guard region > minimumOverlap else { return .noMatch }
        let range = -(region - minimumOverlap)...(region - minimumOverlap)
        var errors: [(shift: Int, error: Float)] = []
        errors.reserveCapacity(range.count)
        for shift in range {
            errors.append((shift, error(old, new, shift: shift)))
        }
        let best = errors.min { $0.error < $1.error }!
        guard best.error <= Self.matchThreshold else { return .noMatch }
        let candidates = errors.filter { $0.error <= best.error + Self.tieTolerance }.map(\.shift)
        let spread = candidates.max()! - candidates.min()!
        guard spread > 2 else { return .shift(best.shift) }
        // Più spostamenti equivalenti (contenuto uniforme o ripetuto): decide l'indizio, se c'è.
        guard let hint else { return .ambiguous }
        return .shift(candidates.min { abs($0 - hint) < abs($1 - hint) }!)
    }

    /// Errore medio tra le righe vecchie da `shift` in giù e le nuove dall'inizio (o viceversa se `shift` < 0).
    private func error(_ old: Frame, _ new: Frame, shift: Int) -> Float {
        let overlap = regionHeight - abs(shift)
        let stride = max(1, overlap / Self.maxSampledRows)
        var total: Float = 0
        var count = 0
        var i = 0
        while i < overlap {
            let oldRow = topBand + (shift >= 0 ? i + shift : i)
            let newRow = topBand + (shift >= 0 ? i : i - shift)
            let a = oldRow * Self.blocks, b = newRow * Self.blocks
            for k in 0..<Self.blocks { total += abs(old.signatures[a + k] - new.signatures[b + k]) }
            count += Self.blocks
            i += stride
        }
        return count == 0 ? .infinity : total / Float(count)
    }

    static func makeFrame(_ image: CGImage) -> Frame {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var signatures = [Float](repeating: 0, count: height * blocks)
        for y in 0..<height {
            let row = y * width * 4
            for block in 0..<blocks {
                let x0 = min(width - 1, block * width / blocks)
                let x1 = max(x0 + 1, (block + 1) * width / blocks)
                var sum = 0
                for x in x0..<x1 {
                    let p = row + x * 4
                    sum += (Int(bytes[p]) * 299 + Int(bytes[p + 1]) * 587 + Int(bytes[p + 2]) * 114) / 1000
                }
                signatures[y * blocks + block] = Float(sum) / Float(x1 - x0)
            }
        }
        return Frame(bytes: bytes, signatures: signatures)
    }

    /// L'immagine cucita finora.
    public func image() -> CGImage? {
        guard rowBytes > 0 else { return nil }
        return Self.makeImage(bytes: canvas + bottomRows, width: width)
    }

    /// Miniatura larga `width` pixel per il pannello, campionando le righe senza copiare l'immagine intera.
    public func thumbnail(width thumbnailWidth: Int) -> CGImage? {
        let total = height
        guard rowBytes > 0, total > 0, thumbnailWidth > 0 else { return nil }
        let thumbnailHeight = max(1, total * thumbnailWidth / width)
        var bytes = [UInt8](repeating: 0, count: thumbnailWidth * thumbnailHeight * 4)
        let canvasRows = canvas.count / rowBytes
        for y in 0..<thumbnailHeight {
            let sourceRow = min(total - 1, y * total / thumbnailHeight)
            for x in 0..<thumbnailWidth {
                let sourceX = min(width - 1, x * width / thumbnailWidth)
                let offset = sourceX * 4
                let target = (y * thumbnailWidth + x) * 4
                if sourceRow < canvasRows {
                    let p = sourceRow * rowBytes + offset
                    bytes[target ..< target + 4] = canvas[p ..< p + 4]
                } else {
                    let p = (sourceRow - canvasRows) * rowBytes + offset
                    bytes[target ..< target + 4] = bottomRows[p ..< p + 4]
                }
            }
        }
        return Self.makeImage(bytes: bytes, width: thumbnailWidth)
    }

    static func makeImage(bytes: [UInt8], width: Int) -> CGImage? {
        let height = bytes.count / (width * 4)
        guard height > 0, let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
