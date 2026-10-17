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

    /// Pagina bianca con paragrafi di 1–3 righe di "testo" alte 10 px, separati da tratti bianchi di 120–`maxGap` px,
    /// a volte allungati di `extra`: la pagina più difficile da cucire.
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

    /// Le righe non bianche, in ordine: il "testo" della pagina.
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
        let session = makeSession(page)
        let image = await session.run()
        #expect(session.outcome == .reachedEnd)
        guard let image else { Issue.record("no image"); return }
        // Tutto il testo, in ordine, senza righe doppie né mancanti. Dove fra due fotogrammi non c'è nessun dettaglio
        // in comune lo spostamento non si può misurare: un tratto bianco può risultare un po' più lungo.
        #expect(Self.textRows(PixelBuffer(image)) == Self.textRows(PixelBuffer(page.expectedImage)))
        #expect((6000...6000 + 600 / 4).contains(image.height), "\(image.height)")
    }

    @Test func automaticStepsWaitWhileThePointerIsOutsideTheArea() async {
        // Lo scorrimento va alla finestra sotto il puntatore: se l'utente va verso il pannello, Pinxel aspetta.
        let time = FakeTime()
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        var inside = true
        var pausedSeen = false
        var scrollsWhileOutside = 0
        let session = ScrollCaptureSession(source: page, driver: page, rect: rect, display: display,
                                           sleep: { await time.sleep($0) }, now: { time.now }, pointerInside: { inside })
        page.onFrame = { count in
            if count == 3 { inside = false }
            if count == 3 + 10 { scrollsWhileOutside = page.scrollCalls.count; inside = true }
            if count > 3, count < 13, session.pause == .pointerOutside { pausedSeen = true }
        }
        let callsBefore = { page.scrollCalls.count }
        let image = await session.run()
        #expect(pausedSeen)
        #expect(scrollsWhileOutside <= 2) // al massimo il passo già partito
        #expect(callsBefore() > scrollsWhileOutside)
        #expect(session.outcome == .reachedEnd)
        #expect(image.map(PixelBuffer.init) == PixelBuffer(page.expectedImage))
    }

    @Test func aTooFastManualScrollAsksToGoBackAndRecovers() async {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 600), viewportHeight: 120, scale: 1)
        let session = makeSession(page, automatic: false)
        var askedToGoBack = false
        page.onFrame = { count in
            switch count {
            case 2: page.scrollTo(60)
            case 3: page.scrollTo(400) // troppo veloce: fuori dalla sovrapposizione
            case 8: askedToGoBack = session.pause == .scrollBack; page.scrollTo(120) // l'utente torna su
            case 9...20: page.scrollTo(min(page.maxPosition, 120 + (count - 8) * 50))
            case 21: session.finish()
            default: break
            }
        }
        let image = await session.run()
        #expect(askedToGoBack)
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
