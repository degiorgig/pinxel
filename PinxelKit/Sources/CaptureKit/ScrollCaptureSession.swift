import CoreGraphics
import Foundation
import Observation
import os

/// Il ciclo della cattura a scorrimento (spec §2, §4): cattura → cuci → scorri → attendi che il contenuto si fermi.
/// La cucitura gira fuori dal main thread, così pannello, tasti e monitor restano reattivi.
@MainActor
@Observable
public final class ScrollCaptureSession {
    public enum Outcome: Equatable, Sendable {
        case reachedEnd, finishedByUser, reachedLimit, contentChanging, cancelled
    }

    /// Perché i passi automatici sono fermi, da mostrare nel pannello.
    public enum Pause: Equatable, Sendable {
        case none
        /// Lo scorrimento va alla finestra sotto il puntatore: fuori dall'area scorrerebbe altro.
        case pointerOutside
        /// Si è andati oltre l'ultimo punto riconosciuto: bisogna tornare un po' su.
        case scrollBack
    }

    public static let settleTimeout = 0.5
    public static let settleInterval: Duration = .milliseconds(50)
    public static let manualInterval: Duration = .milliseconds(100)
    public static let manualResumeDelay = 1.0
    public static let minimumStep = 20.0
    /// Mancate di fila prima di chiedere di tornare su (a mano) o di fermarsi (in automatico).
    public static let missLimit = 3

    /// Altezza in pixel dell'immagine cucita finora.
    public private(set) var height = 0
    public private(set) var preview: CGImage?
    public private(set) var outcome: Outcome?
    public private(set) var pause: Pause = .none
    /// Falso senza permesso Accessibilità: scorre solo l'utente.
    public let scrollsAutomatically: Bool

    @ObservationIgnored private let source: any RegionFrameSource
    @ObservationIgnored private let driver: (any ScrollDriver)?
    @ObservationIgnored private let rect: CGRect
    @ObservationIgnored private let display: DisplayInfo
    @ObservationIgnored private let worker: StitchWorker
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private let now: @MainActor () -> Double
    @ObservationIgnored private let pointerInside: @MainActor () -> Bool
    @ObservationIgnored private var lastManualScroll = -Double.infinity
    @ObservationIgnored private var lastMatch = -Double.infinity
    @ObservationIgnored private var stopRequest: Outcome?
    @ObservationIgnored private let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "scrolling")

    public init(source: any RegionFrameSource, driver: (any ScrollDriver)?, rect: CGRect, display: DisplayInfo,
                maxHeight: Int = 32768,
                sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                now: @escaping @MainActor () -> Double = ScrollCaptureSession.secondsSinceLaunch,
                pointerInside: @escaping @MainActor () -> Bool = { true }) {
        self.source = source
        self.driver = driver
        self.rect = rect
        self.display = display
        self.sleep = sleep
        self.now = now
        self.pointerInside = pointerInside
        worker = StitchWorker(maxHeight: maxHeight)
        scrollsAutomatically = driver != nil
    }

    public func finish() {
        if stopRequest == nil { stopRequest = .finishedByUser }
    }

    public func cancel() {
        stopRequest = .cancelled
    }

    /// L'utente ha scorso a mano: i passi automatici si fermano per `manualResumeDelay`.
    public func userDidScroll() {
        lastManualScroll = now()
    }

    /// Cattura fino alla fine; `nil` se annullata.
    public func run() async -> CGImage? {
        do {
            try await source.prepare(display: display)
            var report = await worker.add(try await source.frame(of: rect, on: display), hint: nil)
            publish(report)
            logger.notice("scrolling capture: automatic=\(self.driver != nil, privacy: .public) frame=\(report.width)x\(report.regionHeight) px")
            if report.step == .reachedLimit { outcome = .reachedLimit }
            let baseStep = Double(report.regionHeight) / display.scale * 2 / 3
            var step = baseStep
            var unchanged = 0
            var misses = 0
            var backedOff = false
            var waitingForMatch = false
            lastMatch = now()
            while outcome == nil {
                if let stop = stopRequest {
                    outcome = stop
                    break
                }
                // Il passo resta dentro lo spostamento misurabile, che cala se si scoprono fasce fisse.
                step = max(Self.minimumStep, min(step, Double(report.maxShift) * 0.9 / display.scale))
                let pointerIsInside = pointerInside()
                let automatic = driver != nil && pointerIsInside && !waitingForMatch
                    && now() - lastManualScroll >= Self.manualResumeDelay
                guard automatic, let driver else {
                    let reason: Pause = waitingForMatch ? .scrollBack : (driver != nil && !pointerIsInside ? .pointerOutside : .none)
                    if reason != pause { logger.notice("scrolling paused: \(String(describing: reason), privacy: .public)") }
                    pause = reason
                    await sleep(Self.manualInterval)
                    if stopRequest != nil { continue }
                    report = await worker.add(try await source.frame(of: rect, on: display), hint: nil)
                    publish(report)
                    if report.step != .unchanged {
                        logger.notice("scrolling manual frame -> \(String(describing: report.step), privacy: .public), height \(report.height, privacy: .public)")
                    }
                    switch report.step {
                    case .appended, .movedBack, .unchanged, .first:
                        if report.step != .unchanged { unchanged = 0 }
                        misses = 0
                        waitingForMatch = false
                        backedOff = false
                        lastMatch = now()
                    case .noMatch, .ambiguous:
                        misses += 1
                        if misses >= Self.missLimit { waitingForMatch = true }
                    case .reachedLimit:
                        outcome = .reachedLimit
                    case .sizeMismatch:
                        outcome = .contentChanging
                    }
                    continue
                }
                pause = .none
                // Dopo essere tornati su di mezzo passo si cattura senza scorrere: lo spostamento netto è il nuovo passo.
                if !backedOff { driver.scroll(by: step, at: CGPoint(x: rect.midX, y: rect.midY)) }
                backedOff = false
                let frame = try await settledFrame()
                if stopRequest != nil { continue }
                let started = now()
                report = await worker.add(frame, hint: Int((step * display.scale).rounded()))
                publish(report)
                logger.notice("scrolling step \(step, privacy: .public) pt -> \(String(describing: report.step), privacy: .public), height \(report.height, privacy: .public), \(Int((self.now() - started) * 1000), privacy: .public) ms")
                switch report.step {
                case .unchanged:
                    unchanged += 1
                    if unchanged >= 2 { outcome = .reachedEnd }
                case .appended, .movedBack, .first:
                    unchanged = 0
                    misses = 0
                    lastMatch = now()
                    // Dopo un passo riuscito il passo torna a crescere verso quello normale.
                    step = min(baseStep, step * 1.5)
                case .noMatch, .ambiguous:
                    misses += 1
                    if lastManualScroll > lastMatch {
                        // Dopo uno scorrimento a mano il riferimento può essere rimasto indietro: non è il contenuto che
                        // cambia, è l'utente che deve tornare su.
                        waitingForMatch = misses >= Self.missLimit
                        if !waitingForMatch { backOff(driver, step: &step, backedOff: &backedOff) }
                    } else if misses >= Self.missLimit {
                        outcome = .contentChanging
                    } else {
                        backOff(driver, step: &step, backedOff: &backedOff)
                    }
                case .reachedLimit:
                    outcome = .reachedLimit
                case .sizeMismatch:
                    outcome = .contentChanging
                }
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

    /// Troppo lontano: si torna su di mezzo passo e si prosegue con passi più corti.
    private func backOff(_ driver: any ScrollDriver, step: inout Double, backedOff: inout Bool) {
        driver.scroll(by: -step / 2, at: CGPoint(x: rect.midX, y: rect.midY))
        step = max(Self.minimumStep, step / 2)
        backedOff = true
    }

    /// Cattura finché due fotogrammi di fila sono uguali, al massimo `settleTimeout`.
    private func settledFrame() async throws -> CGImage {
        var last = try await source.frame(of: rect, on: display)
        let start = now()
        while now() - start < Self.settleTimeout {
            await sleep(Self.settleInterval)
            let next = try await source.frame(of: rect, on: display)
            if Self.sameImage(last, next) { return next }
            last = next
        }
        return last
    }

    static func sameImage(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        return a.dataProvider?.data as Data? == b.dataProvider?.data as Data?
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
    let regionHeight: Int
    let maxShift: Int
    let thumbnail: CGImage?
}

/// Cuce fuori dal main thread: il confronto dei fotogrammi costa decine di millisecondi (secondi in Debug).
actor StitchWorker {
    private let stitcher: ScrollStitcher

    init(maxHeight: Int) {
        stitcher = ScrollStitcher(maxHeight: maxHeight)
    }

    func add(_ frame: CGImage, hint: Int?) -> StitchReport {
        let step = stitcher.add(frame, hint: hint)
        return StitchReport(step: step, height: stitcher.height, width: stitcher.width, regionHeight: stitcher.regionHeight,
                            maxShift: stitcher.maxShift, thumbnail: stitcher.thumbnail(width: 80))
    }

    func finalImage() -> CGImage? {
        stitcher.finalImage()
    }
}
