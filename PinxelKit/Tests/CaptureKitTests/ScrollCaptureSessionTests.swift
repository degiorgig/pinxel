import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

/// Tempo finto: `sleep` avanza l'orologio senza aspettare.
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

    func makeSession(_ page: FakeScrollingPage, automatic: Bool = true, time: FakeTime = FakeTime(), maxHeight: Int = 32768) -> ScrollCaptureSession {
        ScrollCaptureSession(source: page, driver: automatic ? page : nil, rect: rect, display: display, maxHeight: maxHeight,
                             sleep: { await time.sleep($0) }, now: { time.now })
    }

    @Test func automaticCaptureScrollsToTheEnd() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        let image = await session.run()
        #expect(session.outcome == .reachedEnd)
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
        #expect(page.scrollCalls.first == 80) // 2/3 di 120 pt
        #expect(session.height == 900)
        #expect(session.preview != nil)
    }

    @Test func fineKeepsWhatIsStitched() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in if count == 3 { session.finish() } }
        let image = await session.run()
        #expect(session.outcome == .finishedByUser)
        #expect(image != nil)
        #expect((image?.height ?? 0) < 900)
    }

    @Test func cancelDiscardsEverything() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in if count == 3 { session.cancel() } }
        #expect(await session.run() == nil)
        #expect(session.outcome == .cancelled)
    }

    @Test func withoutADriverTheUserScrolls() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 400), viewportHeight: 120, scale: 1)
        let session = makeSession(page, automatic: false)
        #expect(!session.scrollsAutomatically)
        page.onFrame = { count in
            // `onFrame` arriva prima del fotogramma: l'utente scorre di 50 px fra un fotogramma e l'altro, dal secondo.
            page.scrollTo((count - 1) * 50)
            if count == 12 { session.finish() }
        }
        let image = await session.run()
        #expect(page.scrollCalls.isEmpty)
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }

    @Test func manualScrollingPausesTheAutomaticSteps() async {
        let time = FakeTime()
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page, time: time)
        var callsWhilePaused = -1
        page.onFrame = { count in
            if count == 2 { session.userDidScroll() }
            if count == 4 { callsWhilePaused = page.scrollCalls.count }
        }
        _ = await session.run()
        #expect(callsWhilePaused == 1) // dopo lo scorrimento a mano, per 1 s nessun passo automatico
        #expect(session.outcome == .reachedEnd)
    }

    @Test func contentThatChangesStopsTheCapture() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in if count == 2 { page.isAnimating = true } }
        let image = await session.run()
        #expect(session.outcome == .contentChanging)
        #expect(image?.height == 120) // resta il primo fotogramma
    }

    @Test func stopsAtTheHeightLimit() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page, maxHeight: 400)
        let image = await session.run()
        #expect(session.outcome == .reachedLimit)
        #expect(image?.height == 400)
    }

    @Test func appsThatScrollTooFarRecoverByBackingOff() async {
        // Passo di 80 pt, l'app scorre 104 px: oltre la sovrapposizione minima, quindi si torna indietro e si riprova.
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1, scrollFactor: 1.3)
        let session = makeSession(page)
        let image = await session.run()
        #expect(session.outcome == .reachedEnd)
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }

    @Test func scrollingBackDuringAnAutomaticCaptureAddsNothingTwice() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let session = makeSession(page)
        page.onFrame = { count in if count == 4 { page.scrollTo(page.position - 100); session.userDidScroll() } }
        let image = await session.run()
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }
}
