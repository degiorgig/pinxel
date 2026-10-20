import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

/// Fake time: `sleep` advances the clock without waiting.
@MainActor
final class FakeTime {
    var now: Double = 0
    func sleep(_ duration: Duration) async {
        now += Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        await Task.yield()
    }
}

@MainActor
struct ScrollCaptureSessionTests {
    let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 1)
    let rect = CGRect(x: 0, y: 0, width: 64, height: 120)

    func makeSession(_ page: FakeScrollingPage, time: FakeTime = FakeTime(), maxHeight: Int = 32768) -> ScrollCaptureSession {
        ScrollCaptureSession(source: page, rect: rect, display: display, maxHeight: maxHeight,
                             sleep: { await time.sleep($0) }, now: { time.now })
    }

    /// The user scrolls `speed` pixels between one frame and the next, from the second, and presses Done `pause` frames after
    /// reaching the bottom. `onFrame` arrives before the frame.
    func scrollByHand(_ page: FakeScrollingPage, _ session: ScrollCaptureSession, speed: Int, pause: Int = 3) {
        page.onFrame = { count in
            page.scrollTo((count - 1) * speed)
            if count > 1 + page.maxPosition / speed + pause { session.finish() }
        }
    }

    @Test func theUserScrollsAndPinxelStitches() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 400), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        scrollByHand(page, session, speed: 50)
        let image = await session.run()
        #expect(session.outcome == .finishedByUser)
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
        #expect(session.height == 400)
        #expect(session.preview != nil)
    }

    @Test func fineKeepsWhatIsStitched() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in
            page.scrollTo((count - 1) * 50)
            if count == 3 { session.finish() }
        }
        let image = await session.run()
        #expect(session.outcome == .finishedByUser)
        #expect(image != nil)
        #expect((image?.height ?? 0) < 900)
    }

    @Test func cancelDiscardsEverything() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in
            page.scrollTo((count - 1) * 50)
            if count == 3 { session.cancel() }
        }
        #expect(await session.run() == nil)
        #expect(session.outcome == .cancelled)
    }

    @Test func contentThatChangesByItselfAsksToGoBackWithoutStopping() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        var asked = false
        page.onFrame = { count in
            if count == 2 { page.isAnimating = true }
            if count == 10 { asked = session.pause == .scrollBack; session.finish() }
        }
        let image = await session.run()
        #expect(asked)
        #expect(session.outcome == .finishedByUser)
        #expect(image?.height == 120) // the first frame remains
    }

    @Test func stopsAtTheHeightLimit() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page, maxHeight: 400)
        scrollByHand(page, session, speed: 50)
        let image = await session.run()
        #expect(session.outcome == .reachedLimit)
        #expect(image?.height == 400)
    }

    /// White page with paragraphs of 1–3 lines of "text" 10 px tall, separated by white gaps of 120–`maxGap` px,
    /// sometimes stretched by `extra`: the hardest page to stitch.
    static func sparsePage(seed: UInt64, maxGap: Int, extra: Int) -> CGImage {
        let width = 640, height = 6000
        let ctx = FakeScrollingPage.context(width: width, height: height)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var state = seed
        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state >> 33)
        }
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1))
        var y = 40
        while y < height - 20 {
            for _ in 0...(next() % 3) {
                ctx.fill(CGRect(x: 40 + next() % 60, y: y, width: 100 + next() % 400, height: 10))
                y += 22
            }
            y += 120 + next() % (maxGap - 120) + (next() % 2 == 0 ? extra : 0)
        }
        return ctx.makeImage()!
    }

    /// The non-white rows, in order: the page's "text".
    static func textRows(_ buffer: PixelBuffer) -> [[RGBA8]] {
        let white = RGBA8(r: 255, g: 255, b: 255)
        return (0..<buffer.height).compactMap { y in
            let row = (0..<buffer.width).map { buffer.pixel(x: $0, y: y) }
            return row.allSatisfy { $0 == white } ? nil : row
        }
    }

    @Test(arguments: [(UInt64(1), 320, 200), (1, 320, 80), (2, 320, 80), (3, 420, 80)])
    func pagesWithLongBlankStretchesAreStitchedWhole(seed: UInt64, maxGap: Int, extra: Int) async {
        let page = FakeScrollingPage(content: Self.sparsePage(seed: seed, maxGap: maxGap, extra: extra), viewportHeight: 600, scale: 1)
        let session = ScrollCaptureSession(source: page, rect: CGRect(x: 0, y: 0, width: 640, height: 600), display: display,
                                           sleep: { _ in await Task.yield() }, now: { 0 })
        scrollByHand(page, session, speed: 120)
        let image = await session.run()
        guard let image else { Issue.record("no image"); return }
        // All the text, in order, with no duplicated or missing rows.
        #expect(Self.textRows(PixelBuffer(image)) == Self.textRows(PixelBuffer(page.expectedImage)))
        #expect((6000...6000 + 600 / 4).contains(image.height), "\(image.height)")
    }

    @Test func scrollingByHandSamplesThirtyTimesASecondIncludingTheWorkTime() async {
        let time = FakeTime()
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page, time: time)
        var captureTimes: [Double] = []
        page.onFrame = { count in
            captureTimes.append(time.now)
            time.now += 0.02 // capturing and stitching takes time
            if count == 6 { session.finish() }
        }
        _ = await session.run()
        let gaps = zip(captureTimes.dropFirst(), captureTimes.dropFirst(2)).map { $1 - $0 }
        // In a small area a normal scroll exceeds the measurable shift within a tenth of a second.
        #expect(gaps.allSatisfy { abs($0 - 1.0 / 30) < 0.001 }, "\(gaps)")
    }

    @Test func aTooFastManualScrollAsksToGoBackAndRecovers() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 600), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        var askedToGoBack = false
        page.onFrame = { count in
            switch count {
            case 2: page.scrollTo(60)
            case 3: page.scrollTo(400) // too fast: outside the overlap
            case 8: askedToGoBack = session.pause == .scrollBack; page.scrollTo(120) // the user scrolls back up
            case 9...20: page.scrollTo(min(page.maxPosition, 120 + (count - 8) * 50))
            case 21: session.finish()
            default: break
            }
        }
        let image = await session.run()
        #expect(askedToGoBack)
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }

    @Test func rowsThatAllLookAlikeAskToScrollSlowlyNotThatItWasTooFast() async {
        // Identical stripes every 20 px: every shift that is a multiple of 40 matches equally well.
        let ctx = FakeScrollingPage.context(width: 64, height: 900)
        for row in 0..<45 {
            ctx.setFillColor(CGColor(srgbRed: row % 2 == 0 ? 0.9 : 0.2, green: 0.4, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: row * 20, width: 64, height: 20))
        }
        let page = FakeScrollingPage(content: ctx.makeImage()!, viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        var pause: ScrollCaptureSession.Pause?
        page.onFrame = { count in
            // Steps of 25 px: no position matches the first one within one period, so no frame is identical.
            page.scrollTo((count - 1) * 25)
            if count == 6 { pause = session.pause; session.finish() }
        }
        _ = await session.run()
        #expect(pause == .similarRows)
    }

    /// Identical stripes every 20 px under `noiseRows` rows of noise: where there are only stripes, the shift tells
    /// only how far the user scrolled.
    static func stripedPage(noiseRows: Int, height: Int = 900) -> CGImage {
        let ctx = FakeScrollingPage.context(width: 64, height: height)
        for row in 0..<(height / 20) {
            ctx.setFillColor(CGColor(srgbRed: row % 2 == 0 ? 0.9 : 0.2, green: 0.4, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: row * 20, width: 64, height: 20))
        }
        if noiseRows > 0 {
            ctx.draw(TestImages.noise(width: 64, height: noiseRows), in: CGRect(x: 0, y: height - noiseRows, width: 64, height: noiseRows))
        }
        return ctx.makeImage()!
    }

    @Test func whatTheUserScrolledPicksAmongLookAlikeRows() async {
        let page = FakeScrollingPage(content: Self.stripedPage(noiseRows: 0), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in
            guard count > 1 else { return }
            if page.position < page.maxPosition {
                let before = page.position
                page.scrollTo(page.position + 25)
                session.userScrolled(by: Double(page.position - before), precise: true)
            } else if count > 50 {
                session.finish()
            }
        }
        let image = await session.run()
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }

    @Test func wheelNotchesAreMeasuredOnClearContentFirst() async {
        // A notched wheel: the value of one notch is learned on the noise, then used on the stripes.
        let page = FakeScrollingPage(content: Self.stripedPage(noiseRows: 300), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in
            guard count > 1 else { return }
            if page.position < page.maxPosition {
                let before = page.position
                page.scrollTo(page.position + 30)
                session.userScrolled(by: Double(page.position - before) / 10, precise: false)
            } else if count > 50 {
                session.finish()
            }
        }
        let image = await session.run()
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }

    @Test func aChatCanBeCapturedFromTheBottomUp() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 600), viewportHeight: 120, scale: 1)
        page.scrollTo(page.maxPosition)
        let session = makeSession(page)
        page.onFrame = { count in
            guard count > 1 else { return }
            if page.position > 0 { page.scrollTo(page.position - 50) } else if count > 30 { session.finish() }
        }
        let image = await session.run()
        #expect(session.height == 600)
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }

    @Test func scrollingBackUpAddsNothingTwice() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        let positions = [0, 50, 100, 150, 200, 120, 60, 110, 160, 210, 260, 310, 360, 410, 460, 510, 560, 610, 660, 710, 760, 780, 780]
        page.onFrame = { count in
            if count <= positions.count { page.scrollTo(positions[count - 1]) } else { session.finish() }
        }
        let image = await session.run()
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }
}
