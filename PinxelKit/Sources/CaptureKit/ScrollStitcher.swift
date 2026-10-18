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
/// È una classe perché tiene l'immagine in un buffer riservato una volta sola (niente copie a ogni passo).
public final class ScrollStitcher: @unchecked Sendable {
    static let blocks = 32
    /// Blocchi più diversi ignorati nel confronto di due righe (vedi `distance`).
    static let ignoredBlocks = 2
    /// Blocchi che contano nel confronto.
    static var comparedBlocks: Int { blocks - ignoredBlocks }
    /// Errore medio (0–255) sotto cui due righe combaciano.
    static let matchThreshold = 3.0
    /// Margine attorno al migliore entro cui gli spostamenti passano alla fase successiva della ricerca.
    static let tieTolerance = 0.75
    /// Spostamenti confrontati su tutte le righe, alla fine.
    static let finalists = 16

    /// Due spostamenti sono equivalenti se l'errore del secondo supera quello del migliore di poco, in assoluto o in
    /// proporzione: fra fotogrammi reali anche lo spostamento giusto ha un piccolo errore.
    static func ties(_ error: Double, best: Double) -> Bool {
        error <= best + max(0.15, best * 0.3)
    }
    /// Una riga con differenza fra il blocco più chiaro e il più scuro sotto questa soglia è uniforme (bianca, a tinta unita):
    /// non dice nulla sullo spostamento e non entra nel confronto.
    static let uniformRowRange: Int16 = 4
    /// Righe con dettagli necessarie perché uno spostamento sia giudicabile.
    static let minimumInformativeRows = 4
    /// Righe con dettagli confrontate al massimo, per fotogramma, nella ricerca grossolana e in quella fine.
    static let coarseRows = 40
    static let fineRows = 300
    /// Quota delle righe peggiori ignorata nel confronto di ripiego: una riga evidenziata sotto il puntatore fermo resta
    /// nello stesso punto dello schermo mentre il contenuto scorre, e non deve far scartare lo spostamento giusto.
    static let ignoredWorstRows = 0.3
    /// Un primo cambiamento che tocca meno di questa frazione delle righe (evidenziazione, cursore del testo) non è uno
    /// scorrimento: non serve a riconoscere le fasce fisse.
    static let moveFraction = 8

    struct Frame {
        let bytes: [UInt8]
        /// Una firma per riga: il grigio medio di `blocks` blocchi orizzontali.
        let signatures: [SIMD32<Int16>]
        /// Righe con dettagli, dall'alto.
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
    /// Spostamento dell'ultimo fotogramma riconosciuto, in pixel.
    public private(set) var lastShift: Int?
    private var bandsKnown = false
    /// Fascia superiore + contenuto che scorre, RGBA premoltiplicato sRGB, righe dall'alto.
    private var canvas: PixelRows?
    /// Fascia inferiore del fotogramma che ha raggiunto la fine della cattura: va in fondo all'immagine.
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
    /// Sovrapposizione minima fra due fotogrammi perché lo spostamento sia misurabile.
    public var minimumOverlap: Int { max(8, regionHeight / 4) }
    /// Spostamento massimo misurabile fra due fotogrammi: chi scorre più in fretta perde il riferimento.
    public var maxShift: Int { max(0, regionHeight - minimumOverlap) }
    public var height: Int { rowBytes == 0 ? 0 : (canvas?.rows ?? 0) + bottomRows.count / rowBytes }

    /// `hint`: lo spostamento atteso in pixel, se noto; decide fra spostamenti equivalenti e nei tratti senza dettagli.
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
            // Il primo movimento è avvenuto: da qui le fasce non si cercano più (l'immagine non è più un solo fotogramma).
            bandsKnown = true
            position += shift
            if shift < 0 { return .movedBack }
            let newBottom = position + regionHeight
            guard newBottom >= captured else { return .appended(0) }
            // Questo fotogramma arriva alla fine della cattura: la sua fascia inferiore è quella che chiude l'immagine.
            bottomRows = Array(frame.bytes[(frameHeight - bottomBand) * rowBytes ..< frameHeight * rowBytes])
            guard newBottom > captured, let canvas else { return .appended(0) }
            let wanted = newBottom - captured
            let room = max(0, maxHeight - (topBand + captured + bottomBand))
            let rows = min(wanted, room)
            let start = topBand + regionHeight - wanted
            frame.bytes.withUnsafeBytes { canvas.append($0.baseAddress! + start * rowBytes, rows: rows) }
            captured += rows
            return rows < wanted ? .reachedLimit : .appended(rows)
        }
    }

    /// Righe in cima e in fondo identiche alla stessa posizione mentre il centro cambia: intestazioni e barre fisse.
    /// Al massimo un quarto del fotogramma ciascuna. Si decide una volta, al primo movimento; se righe bianche del
    /// contenuto vengono prese per una fascia il risultato resta giusto, perché la fascia inferiore finale viene
    /// dall'ultimo fotogramma e quella superiore dal primo.
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
        // Finora l'immagine è il primo fotogramma intero: la fascia inferiore va tolta e rimessa in fondo alla fine.
        guard let canvas else { return }
        let keep = min(canvas.rows, frameHeight - bottom)
        canvas.truncate(to: keep)
        bottomRows = Array(old.bytes[(frameHeight - bottom) * rowBytes ..< frameHeight * rowBytes])
        captured = keep - top
        position = 0
    }

    private func match(_ old: Frame, _ new: Frame, hint: Int?) -> Match {
        let region = regionHeight
        let limit = maxShift
        guard limit > 0 else { return .noMatch }
        let range = -limit...limit
        // Righe con dettagli della zona che scorre, nei due fotogrammi (indici relativi alla zona).
        let oldRows = (0..<region).filter { old.informative[topBand + $0] }
        let newRows = (0..<region).filter { new.informative[topBand + $0] }
        guard oldRows.count + newRows.count >= Self.minimumInformativeRows else {
            // Nessun dettaglio (tratto bianco): decide l'indizio, se c'è ed è misurabile.
            guard let hint, range.contains(hint) else { return hint == nil ? .ambiguous : .noMatch }
            return .shift(hint)
        }
        // Ricerca grossolana su poche righe, poi fine sui candidati vicini al migliore.
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
        // I migliori si confrontano su tutte le righe con dettagli: con poche righe campionate uno spostamento sbagliato
        // su contenuto che si ripete (schede, tabelle) può sembrare buono quanto quello giusto.
        let fineBest = errors.min(by: { $0.error < $1.error })?.error ?? 0
        let finalists = errors.filter { $0.error <= fineBest + 2 * Self.tieTolerance }.sorted { $0.error < $1.error }.prefix(Self.finalists)
        errors = finalists.compactMap { candidate in
            error(old, new, shift: candidate.shift, oldRows: oldRows, newRows: newRows).map { (candidate.shift, $0) }
        }
        guard let best = errors.min(by: { $0.error < $1.error }), best.error <= Self.matchThreshold else {
            // Nessuno spostamento combacia del tutto: forse poche righe ferme sullo schermo (un'evidenziazione) disturbano.
            // Ignorandole, uno spostamento che combacia senza alternative equivalenti è quello giusto.
            if let shift = robustShift(old, new, range: range, oldRows: oldRows, newRows: newRows) { return .shift(shift) }
            // Nessuno spostamento verificabile combacia. Se quello atteso non è contraddetto da nessuna riga (le righe con
            // dettagli finiscono fuori dalla sovrapposizione, come in un tratto bianco), è il più credibile.
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
        // Più spostamenti equivalenti (contenuto uniforme o ripetuto): decide l'indizio, se c'è e se è misurabile;
        // fuori portata vuol dire che il contenuto è andato oltre, e il candidato sul bordo sarebbe sbagliato.
        guard let hint else { return .ambiguous }
        guard range.contains(hint) else { return .noMatch }
        return .shift(candidates.min { abs($0 - hint) < abs($1 - hint) }!)
    }

    /// Lo spostamento che combacia ignorando le righe peggiori, se è uno solo (a meno di 2 pixel).
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

    /// Vero se almeno una riga con dettagli, in uno dei due fotogrammi, cade nella sovrapposizione su una riga diversa.
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

    /// Righe la cui firma è cambiata alla stessa posizione.
    static func changedRows(_ old: Frame, _ new: Frame) -> Int {
        zip(old.signatures, new.signatures).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) }
    }

    /// Righe distribuite in modo uniforme, al massimo `count`.
    static func thin(_ rows: [Int], to count: Int) -> [Int] {
        guard rows.count > count else { return rows }
        return (0..<count).map { rows[$0 * rows.count / count] }
    }

    /// Errore medio fra le righe che si sovrappongono con questo spostamento, contando solo quelle con dettagli in
    /// almeno uno dei due fotogrammi (con `ignoringWorst`, senza le peggiori); `nil` se sono troppo poche per giudicare.
    private func error(_ old: Frame, _ new: Frame, shift: Int, oldRows: [Int], newRows: [Int], ignoringWorst: Bool = false) -> Double? {
        let region = regionHeight
        var distances: [Int16] = []
        distances.reserveCapacity(oldRows.count + newRows.count)
        // Riga `r` del vecchio fotogramma ↔ riga `r - shift` del nuovo.
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

    /// Differenza fra due righe senza i `ignoredBlocks` blocchi più diversi: una colonna che cambia da sola, come la barra
    /// di scorrimento che compare mentre si scorre, peserebbe uguale su tutti gli spostamenti e coprirebbe quello giusto.
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

    /// L'immagine cucita finora (una copia: la cattura può continuare).
    public func image() -> CGImage? {
        guard let canvas, rowBytes > 0 else { return nil }
        var bytes = Data(bytes: canvas.pointer, count: canvas.rows * rowBytes)
        bytes.append(contentsOf: bottomRows)
        return Self.makeImage(data: bytes, width: width)
    }

    /// L'immagine finale, senza copiarla: la fascia inferiore va in coda al buffer, che passa all'immagine.
    /// Dopo questa chiamata non si aggiungono più fotogrammi.
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

    /// Miniatura larga `width` pixel per il pannello, campionando le righe senza copiare l'immagine intera.
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

/// Righe RGBA in un buffer riservato per l'altezza massima: la memoria virtuale si occupa solo quando si scrive,
/// e l'immagine finale usa il buffer senza copiarlo.
final class PixelRows: @unchecked Sendable {
    let rowBytes: Int
    let capacityRows: Int
    let pointer: UnsafeMutableRawPointer
    private(set) var rows = 0

    init(rowBytes: Int, capacityRows: Int) {
        self.rowBytes = rowBytes
        self.capacityRows = capacityRows
        pointer = UnsafeMutableRawPointer.allocate(byteCount: max(1, rowBytes * capacityRows), alignment: 16)
    }

    deinit {
        pointer.deallocate()
    }

    func append(_ source: UnsafeRawPointer, rows count: Int) {
        let count = min(count, capacityRows - rows)
        guard count > 0 else { return }
        memcpy(pointer + rows * rowBytes, source, count * rowBytes)
        rows += count
    }

    func truncate(to count: Int) {
        rows = max(0, min(rows, count))
    }

    /// Immagine che legge direttamente dal buffer e lo tiene vivo finché serve.
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
