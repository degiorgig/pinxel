import CoreGraphics
import Foundation
import Observation
import os

/// Il ciclo della cattura a scorrimento (spec §2, §4): l'utente scorre, Pinxel cattura ogni `manualInterval` e cuce,
/// finché si preme Fine. La cucitura gira fuori dal main thread, così pannello e tasti restano reattivi.
@MainActor
@Observable
public final class ScrollCaptureSession {
    public enum Outcome: Equatable, Sendable {
        case finishedByUser, reachedLimit, contentChanging, cancelled
    }

    /// Perché la cucitura è ferma, da mostrare nel pannello.
    public enum Pause: Equatable, Sendable {
        case none
        /// Si è andati oltre l'ultimo punto riconosciuto: bisogna tornare un po' su.
        case scrollBack
        /// Righe tutte simili (tabelle, liste): più spostamenti combaciano allo stesso modo. Si torna su e si scorre piano.
        case similarRows
    }

    /// 30 al secondo: in un'area piccola uno scorrimento normale supera in un decimo di secondo lo spostamento misurabile.
    public static let manualInterval: Duration = .seconds(1.0 / 30)
    /// Mancate di fila prima di chiedere di tornare su.
    public static let missLimit = 3
    /// Spostamento minimo, in pixel, perché tari le unità di scorrimento.
    static let calibrationMinimumShift = 16

    /// Altezza in pixel dell'immagine cucita finora.
    public private(set) var height = 0
    public private(set) var preview: CGImage?
    public private(set) var outcome: Outcome?
    public private(set) var pause: Pause = .none

    @ObservationIgnored private let source: any RegionFrameSource
    @ObservationIgnored private let rect: CGRect
    @ObservationIgnored private let display: DisplayInfo
    @ObservationIgnored private let worker: StitchWorker
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private let now: @MainActor () -> Double
    @ObservationIgnored private var stopRequest: Outcome?
    /// Scorrimento dell'utente dall'ultimo fotogramma riconosciuto: trackpad (punti) e rotella a scatti, separati.
    @ObservationIgnored private var pendingPrecise = 0.0
    @ObservationIgnored private var pendingNotches = 0.0
    /// Pixel per unità di scorrimento, imparati dagli spostamenti riconosciuti con certezza; il segno lo decidono loro.
    @ObservationIgnored private var pixelsPerPoint: Double
    @ObservationIgnored private var pixelsPerNotch: Double?
    @ObservationIgnored private let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "scrolling")

    public init(source: any RegionFrameSource, rect: CGRect, display: DisplayInfo, maxHeight: Int = 32768,
                sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                now: @escaping @MainActor () -> Double = ScrollCaptureSession.secondsSinceLaunch) {
        self.source = source
        self.rect = rect
        self.display = display
        self.sleep = sleep
        self.now = now
        worker = StitchWorker(maxHeight: maxHeight)
        pixelsPerPoint = display.scale
    }

    /// L'utente ha scorso sopra l'area; positivo verso il fondo del documento. `precise`: trackpad o mouse a scorrimento
    /// continuo, in punti; altrimenti scatti di rotella, il cui valore in pixel dipende dall'app.
    public func userScrolled(by amount: Double, precise: Bool) {
        if precise { pendingPrecise += amount } else { pendingNotches += amount }
    }

    /// Quanto ci si aspetta che il contenuto si sia spostato, in pixel; `nil` se l'utente non ha scorso o se il valore
    /// degli scatti non è ancora noto.
    private var expectedShift: Int? {
        guard pendingPrecise != 0 || pendingNotches != 0 else { return nil }
        var pixels = pendingPrecise * pixelsPerPoint
        if pendingNotches != 0 {
            guard let pixelsPerNotch else { return nil }
            pixels += pendingNotches * pixelsPerNotch
        }
        return Int(pixels.rounded())
    }

    /// Dopo un fotogramma riconosciuto: lo spostamento misurato tara le unità di scorrimento, poi si riparte da zero.
    private func calibrate(measured shift: Int) {
        defer { pendingPrecise = 0; pendingNotches = 0 }
        guard abs(shift) >= Self.calibrationMinimumShift else { return }
        if pendingNotches == 0, pendingPrecise != 0 {
            let ratio = Double(shift) / pendingPrecise
            if (0.25...4).contains(abs(ratio) / display.scale) { pixelsPerPoint = pixelsPerPoint * 0.5 + ratio * 0.5 }
        } else if pendingPrecise == 0, pendingNotches != 0 {
            let ratio = Double(shift) / pendingNotches
            pixelsPerNotch = pixelsPerNotch.map { $0 * 0.5 + ratio * 0.5 } ?? ratio
        }
    }

    public func finish() {
        if stopRequest == nil { stopRequest = .finishedByUser }
    }

    public func cancel() {
        stopRequest = .cancelled
    }

    /// Cattura fino a Fine; `nil` se annullata.
    public func run() async -> CGImage? {
        do {
            try await source.prepare(display: display)
            // Si campiona ogni `manualInterval`, contando anche il tempo di cattura e cucitura.
            var lastSample = now()
            var report = await worker.add(try await source.frame(of: rect, on: display))
            publish(report)
            logger.notice("scrolling capture: frame=\(report.width)x\(report.frameHeight) px")
            if report.step == .reachedLimit { outcome = .reachedLimit }
            var misses = 0
            var lastMiss = StitchStep.noMatch
            while outcome == nil {
                if let stop = stopRequest {
                    outcome = stop
                    break
                }
                let wait = Self.manualInterval - .seconds(now() - lastSample)
                if wait > .zero { await sleep(wait) }
                if stopRequest != nil { continue }
                lastSample = now()
                let frame = try await source.frame(of: rect, on: display)
                // Dopo la cattura: conta anche lo scorrimento arrivato mentre si catturava.
                let expected = expectedShift
                report = await worker.add(frame, expectedShift: expected)
                publish(report)
                if report.step != .unchanged {
                    logger.notice("scrolling frame -> \(String(describing: report.step), privacy: .public), expected \(expected.map(String.init) ?? "-", privacy: .public), height \(report.height, privacy: .public)")
                }
                switch report.step {
                case .appended, .movedBack, .unchanged, .first:
                    misses = 0
                    calibrate(measured: report.step == .unchanged ? 0 : report.shift ?? 0)
                case .noMatch, .ambiguous:
                    misses += 1
                    lastMiss = report.step
                case .reachedLimit:
                    outcome = .reachedLimit
                case .sizeMismatch:
                    outcome = .contentChanging
                }
                let reason: Pause = misses < Self.missLimit ? .none : lastMiss == .ambiguous ? .similarRows : .scrollBack
                if reason != pause { logger.notice("scrolling paused: \(String(describing: reason), privacy: .public)") }
                pause = reason
            }
        } catch {
            logger.error("scrolling capture failed: \(String(describing: error), privacy: .public)")
            outcome = stopRequest ?? .contentChanging
        }
        if outcome == nil { outcome = stopRequest ?? .contentChanging }
        pause = .none
        logger.notice("scrolling capture ended: \(String(describing: self.outcome), privacy: .public), height \(self.height, privacy: .public)")
        return outcome == .cancelled ? nil : await worker.finalImage()
    }

    private func publish(_ report: StitchReport) {
        height = report.height
        preview = report.thumbnail
    }
}

extension ScrollCaptureSession {
    private static let clockStart = ContinuousClock.now

    /// Orologio monotono in secondi: la sessione usa solo differenze.
    public static func secondsSinceLaunch() -> Double {
        let components = clockStart.duration(to: .now).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Ciò che la sessione legge dopo ogni fotogramma.
struct StitchReport: @unchecked Sendable {
    let step: StitchStep
    let height: Int
    let width: Int
    let frameHeight: Int
    /// Spostamento dell'ultimo fotogramma riconosciuto.
    let shift: Int?
    let thumbnail: CGImage?
}

/// Cuce fuori dal main thread: il confronto dei fotogrammi costa decine di millisecondi (secondi in Debug).
actor StitchWorker {
    private let stitcher: ScrollStitcher

    init(maxHeight: Int) {
        stitcher = ScrollStitcher(maxHeight: maxHeight)
    }

    func add(_ frame: CGImage, expectedShift: Int? = nil) -> StitchReport {
        let step = stitcher.add(frame, hint: expectedShift)
        return StitchReport(step: step, height: stitcher.height, width: stitcher.width, frameHeight: stitcher.frameHeight,
                            shift: stitcher.lastShift, thumbnail: stitcher.thumbnail(width: 80))
    }

    func finalImage() -> CGImage? {
        stitcher.finalImage()
    }
}
