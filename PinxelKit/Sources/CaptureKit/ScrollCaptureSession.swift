import CoreGraphics
import Foundation
import Observation

/// Il ciclo della cattura a scorrimento (spec §2, §4): cattura → cuci → scorri → attendi che il contenuto si fermi.
@MainActor
@Observable
public final class ScrollCaptureSession {
    public enum Outcome: Equatable, Sendable {
        case reachedEnd, finishedByUser, reachedLimit, contentChanging, cancelled
    }

    public static let settleTimeout = 0.5
    public static let settleInterval: Duration = .milliseconds(50)
    public static let manualInterval: Duration = .milliseconds(100)
    public static let manualResumeDelay = 1.0
    public static let minimumStep = 20.0

    /// Altezza in pixel dell'immagine cucita finora.
    public private(set) var height = 0
    public private(set) var preview: CGImage?
    public private(set) var outcome: Outcome?
    /// Falso senza permesso Accessibilità: scorre solo l'utente.
    public let scrollsAutomatically: Bool

    @ObservationIgnored private let source: any RegionFrameSource
    @ObservationIgnored private let driver: (any ScrollDriver)?
    @ObservationIgnored private let rect: CGRect
    @ObservationIgnored private let display: DisplayInfo
    @ObservationIgnored private var stitcher: ScrollStitcher
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private let now: @MainActor () -> Double
    @ObservationIgnored private var lastManualScroll = -Double.infinity
    @ObservationIgnored private var stopRequest: Outcome?

    public init(source: any RegionFrameSource, driver: (any ScrollDriver)?, rect: CGRect, display: DisplayInfo,
                maxHeight: Int = 32768,
                sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                now: @escaping @MainActor () -> Double = ScrollCaptureSession.secondsSinceLaunch) {
        self.source = source
        self.driver = driver
        self.rect = rect
        self.display = display
        self.sleep = sleep
        self.now = now
        stitcher = ScrollStitcher(maxHeight: maxHeight)
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
            let first = stitcher.add(try await source.frame(of: rect, on: display), hint: nil)
            publish()
            if first == .reachedLimit { outcome = .reachedLimit }
            var step = Double(stitcher.regionHeight) / display.scale * 2 / 3
            var unchanged = 0
            var noMatch = 0
            var backedOff = false
            while outcome == nil {
                if let stop = stopRequest {
                    outcome = stop
                    break
                }
                guard let driver, now() - lastManualScroll >= Self.manualResumeDelay else {
                    await sleep(Self.manualInterval)
                    if stopRequest != nil { continue }
                    let result = stitcher.add(try await source.frame(of: rect, on: display), hint: nil)
                    publish()
                    if result == .reachedLimit { outcome = .reachedLimit }
                    continue
                }
                // Dopo essere tornati su di mezzo passo si cattura senza scorrere: lo spostamento netto è il nuovo passo.
                if !backedOff { driver.scroll(by: step, at: CGPoint(x: rect.midX, y: rect.midY)) }
                backedOff = false
                let frame = try await settledFrame()
                if stopRequest != nil { continue }
                let result = stitcher.add(frame, hint: Int((step * display.scale).rounded()))
                publish()
                switch result {
                case .unchanged:
                    unchanged += 1
                    if unchanged >= 2 { outcome = .reachedEnd }
                case .appended, .movedBack, .first:
                    unchanged = 0
                    noMatch = 0
                case .noMatch, .ambiguous:
                    noMatch += 1
                    if noMatch >= 3 {
                        outcome = .contentChanging
                    } else {
                        // Troppo lontano: si torna su di mezzo passo e si prosegue con passi più corti.
                        driver.scroll(by: -step / 2, at: CGPoint(x: rect.midX, y: rect.midY))
                        step = max(Self.minimumStep, step / 2)
                        backedOff = true
                    }
                case .reachedLimit:
                    outcome = .reachedLimit
                case .sizeMismatch:
                    outcome = .contentChanging
                }
            }
        } catch {
            outcome = stopRequest ?? .contentChanging
        }
        if outcome == nil { outcome = stopRequest ?? .contentChanging }
        return outcome == .cancelled ? nil : stitcher.image()
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

    private func publish() {
        height = stitcher.height
        preview = stitcher.thumbnail(width: 80)
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
