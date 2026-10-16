import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

@MainActor
struct ScrollStitcherTests {
    /// Scorre la pagina a passi di `step` pixel richiesti (il fattore della pagina decide quelli veri) fino in fondo.
    /// Come la sessione, dopo un `noMatch` torna su di mezzo passo e dimezza il passo.
    func stitch(_ page: FakeScrollingPage, step initialStep: Int, hint: Bool = true, maxHeight: Int = 32768) -> (ScrollStitcher, [StitchStep]) {
        var stitcher = ScrollStitcher(maxHeight: maxHeight)
        var steps = [stitcher.add(page.currentFrame(), hint: nil)]
        var unchanged = 0
        var step = initialStep
        var backedOff = false
        while unchanged < 2, steps.count < 200 {
            // Dopo essere tornati su di mezzo passo si cattura senza scorrere: lo spostamento netto è il nuovo passo.
            if !backedOff { page.scroll(by: Double(step) / page.scale, at: .zero) }
            backedOff = false
            let result = stitcher.add(page.currentFrame(), hint: hint ? step : nil)
            steps.append(result)
            if result == .reachedLimit { break }
            if result == .noMatch {
                page.scroll(by: -Double(step / 2) / page.scale, at: .zero)
                step = max(10, step / 2)
                backedOff = true
            }
            unchanged = result == .unchanged ? unchanged + 1 : 0
        }
        return (stitcher, steps)
    }

    func expectEqual(_ image: CGImage?, _ expected: CGImage, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let image else { Issue.record("no image", sourceLocation: sourceLocation); return }
        #expect(image.width == expected.width && image.height == expected.height, "\(image.width)x\(image.height)", sourceLocation: sourceLocation)
        #expect(PixelBuffer(image) == PixelBuffer(expected), sourceLocation: sourceLocation)
    }

    @Test func exactStepsRebuildThePage() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let (stitcher, steps) = stitch(page, step: 80)
        #expect(steps.first == .first)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test(arguments: [0.7, 1.3])
    func appsThatScrollMoreOrLessStillRebuildThePage(factor: Double) {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1, scrollFactor: factor)
        let (stitcher, _) = stitch(page, step: 70)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test func fixedHeaderAndFooterAppearOnce() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 700), viewportHeight: 120,
                                     header: TestImages.solid(width: 64, height: 20, red: 1, green: 0, blue: 0),
                                     footer: TestImages.solid(width: 64, height: 12, red: 0, green: 0, blue: 1), scale: 1)
        let (stitcher, _) = stitch(page, step: 80)
        #expect(stitcher.topBand == 20)
        #expect(stitcher.bottomBand == 12)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test func blankTopRowsDoNotBreakThePage() {
        let ctx = FakeScrollingPage.context(width: 64, height: 700)
        ctx.draw(TestImages.noise(width: 64, height: 700), in: CGRect(x: 0, y: 0, width: 64, height: 700))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 700 - 30, width: 64, height: 30)) // 30 righe bianche in cima
        let page = FakeScrollingPage(content: ctx.makeImage()!, viewportHeight: 120, scale: 1)
        let (stitcher, _) = stitch(page, step: 80)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    /// Strisce alternate ogni 20 px (periodo 40).
    func stripes(height: Int, markers: Bool) -> CGImage {
        let ctx = FakeScrollingPage.context(width: 64, height: height)
        for row in 0..<(height / 20) {
            ctx.setFillColor(CGColor(srgbRed: row % 2 == 0 ? 0.9 : 0.2, green: 0.4, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: row * 20, width: 64, height: 20))
            if markers {
                // Come il testo di una lista: ogni riga ha qualcosa di suo.
                ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
                ctx.fill(CGRect(x: (row * 13) % 56, y: row * 20 + 6, width: 8, height: 8))
            }
        }
        return ctx.makeImage()!
    }

    @Test func listsOfSimilarRowsAreNotMisaligned() {
        let page = FakeScrollingPage(content: stripes(height: 600, markers: true), viewportHeight: 120, scale: 1)
        let (stitcher, _) = stitch(page, step: 80)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test func equivalentShiftsFollowTheHint() {
        // Strisce identiche: 70, 30, -10… combaciano tutti; l'indizio sceglie 70, non un altro allineamento.
        let page = FakeScrollingPage(content: stripes(height: 600, markers: false), viewportHeight: 120, scale: 1)
        var stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(70)
        #expect(stitcher.add(page.currentFrame(), hint: 70) == .appended(70))
        page.scrollTo(140)
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .ambiguous)
    }

    @Test func uniformContentUsesTheHintOrWaits() {
        let blank = TestImages.solid(width: 64, height: 600, red: 1, green: 1, blue: 1)
        let page = FakeScrollingPage(content: blank, viewportHeight: 120, scale: 1)
        var stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scroll(by: 50, at: .zero)
        // Fotogrammi identici: nessun movimento visibile.
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .unchanged)
    }

    @Test func scrollingBackUpAppendsNothingTwice() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 600), viewportHeight: 120, scale: 1)
        var stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(80); _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(160); _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(100)
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .movedBack)
        page.scrollTo(140)
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .appended(0))
        for position in stride(from: 220, through: page.maxPosition, by: 60) {
            page.scrollTo(position); _ = stitcher.add(page.currentFrame(), hint: nil)
        }
        page.scrollTo(page.maxPosition); _ = stitcher.add(page.currentFrame(), hint: nil)
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test func aJumpLargerThanTheFrameIsNoMatch() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        var stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(400)
        #expect(stitcher.add(page.currentFrame(), hint: 400) == .noMatch)
        // Il riferimento resta il fotogramma buono: tornando vicino si riprende.
        page.scrollTo(60)
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .appended(60))
    }

    @Test func stopsAtTheHeightLimit() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let (stitcher, steps) = stitch(page, step: 80, maxHeight: 300)
        #expect(steps.last == .reachedLimit)
        #expect(stitcher.height == 300)
        #expect(PixelBuffer(stitcher.image()!).pixel(x: 5, y: 299) == PixelBuffer(page.expectedImage).pixel(x: 5, y: 299))
    }

    @Test func framesOfAnotherSizeAreRejected() {
        var stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(TestImages.noise(width: 64, height: 120), hint: nil)
        #expect(stitcher.add(TestImages.noise(width: 64, height: 100), hint: nil) == .sizeMismatch)
    }

    @Test func thumbnailKeepsTheAspectRatio() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 600), viewportHeight: 120, scale: 1)
        let (stitcher, _) = stitch(page, step: 80)
        let thumbnail = stitcher.thumbnail(width: 16)
        #expect(thumbnail?.width == 16)
        #expect(thumbnail?.height == 150)
    }
}

