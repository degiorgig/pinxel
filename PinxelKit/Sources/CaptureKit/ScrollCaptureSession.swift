import CoreGraphics
import Foundation
import Observation
import os

/// The scrolling capture loop (spec §2, §4): the user scrolls, Pinxel captures every `manualInterval` and stitches,
/// until Done is pressed. Stitching runs off the main thread, so the panel and keys stay responsive.
@MainActor
@Observable
public final class ScrollCaptureSession {
    public enum Outcome: Equatable, Sendable {
        case finishedByUser, reachedLimit, contentChanging, cancelled
    }

    /// Why stitching is stalled, to show in the panel.
    public enum Pause: Equatable, Sendable {
        case none
        /// Went past the last recognized point: the user needs to scroll back up a little.
        case scrollBack
        /// All rows look alike (tables, lists): several shifts match equally well. Scroll back up and scroll slowly.
        case similarRows
    }

    /// 30 per second: in a small area a normal scroll exceeds the measurable shift within a tenth of a second.
    public static let manualInterval: Duration = .seconds(1.0 / 30)
    /// Consecutive misses before asking to scroll back up.
    public static let missLimit = 3
    /// Minimum shift, in pixels, to calibrate the scroll units.
    static let calibrationMinimumShift = 16

    /// Height in pixels of the image stitched so far.
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
    /// User scrolling since the last recognized frame: trackpad (points) and notched wheel, kept separate.
    @ObservationIgnored private var pendingPrecise = 0.0
    @ObservationIgnored private var pendingNotches = 0.0
    /// Pixels per scroll unit, learned from shifts recognized with certainty; their sign decides the direction.
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

    /// The user scrolled over the area; positive toward the bottom of the document. `precise`: trackpad or continuous-scroll mouse
    /// in points; otherwise wheel notches, whose pixel value depends on the app.
    public func userScrolled(by amount: Double, precise: Bool) {
        if precise { pendingPrecise += amount } else { pendingNotches += amount }
    }

    /// How far the content is expected to have moved, in pixels; `nil` if the user did not scroll or if the notch value
    /// is not known yet.
    private var expectedShift: Int? {
        guard pendingPrecise != 0 || pendingNotches != 0 else { return nil }
        var pixels = pendingPrecise * pixelsPerPoint
        if pendingNotches != 0 {
            guard let pixelsPerNotch else { return nil }
            pixels += pendingNotches * pixelsPerNotch
        }
        return Int(pixels.rounded())
    }

    /// After a recognized frame: the measured shift calibrates the scroll units, then it starts again from zero.
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

    /// Captures until Done; `nil` if cancelled.
    public func run() async -> CGImage? {
        do {
            try await source.prepare(display: display)
            // Sample every `manualInterval`, counting capture and stitching time too.
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
                // After the capture: also count the scrolling that arrived while capturing.
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

    /// Monotonic clock in seconds: the session only uses differences.
    public static func secondsSinceLaunch() -> Double {
        let components = clockStart.duration(to: .now).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// What the session reads after each frame.
struct StitchReport: @unchecked Sendable {
    let step: StitchStep
    let height: Int
    let width: Int
    let frameHeight: Int
    /// Shift of the last recognized frame.
    let shift: Int?
    let thumbnail: CGImage?
}

/// Stitches off the main thread: comparing frames takes tens of milliseconds (seconds in Debug).
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
