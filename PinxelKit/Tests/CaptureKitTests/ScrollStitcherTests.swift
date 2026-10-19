import CoreGraphics
import Testing
@testable import CaptureKit
import PinxelTestSupport

@MainActor
struct ScrollStitcherTests {
    /// Scorre la pagina a passi di `step` pixel attesi (`factor` decide quelli veri) fino in fondo, con lo spostamento
    /// atteso come indizio. Dopo un `noMatch` torna su di mezzo passo e dimezza il passo.
    func stitch(_ page: FakeScrollingPage, step initialStep: Int, factor: Double = 1, hint: Bool = true,
                maxHeight: Int = 32768) -> (ScrollStitcher, [StitchStep]) {
        let stitcher = ScrollStitcher(maxHeight: maxHeight)
        var steps = [stitcher.add(page.currentFrame(), hint: nil)]
        var unchanged = 0
        var step = initialStep
        var backedOff = false
        while unchanged < 2, steps.count < 200 {
            // Dopo essere tornati su di mezzo passo si cattura senza scorrere: lo spostamento netto è il nuovo passo.
            if !backedOff { page.scrollTo(page.position + Int((Double(step) * factor).rounded())) }
            backedOff = false
            let result = stitcher.add(page.currentFrame(), hint: hint ? step : nil)
            steps.append(result)
            if result == .reachedLimit { break }
            if result == .noMatch {
                page.scrollTo(page.position - Int((Double(step / 2) * factor).rounded()))
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
    func shiftsDifferentFromTheExpectedOneStillRebuildThePage(factor: Double) {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let (stitcher, _) = stitch(page, step: 70, factor: factor)
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
        ctx.fill(CGRect(x: 0, y: 700 - 100, width: 64, height: 100)) // 100 righe bianche in cima, più del passo
        let page = FakeScrollingPage(content: ctx.makeImage()!, viewportHeight: 120, scale: 1)
        let (stitcher, _) = stitch(page, step: 80)
        #expect(stitcher.topBand > 0) // le righe bianche sembrano un'intestazione fissa
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test func theBottomBandComesFromTheLastFrameOfTheCapture() {
        // Righe bianche 100..<140 nel contenuto: al primo movimento sembrano una barra fissa in basso.
        let ctx = FakeScrollingPage.context(width: 64, height: 700)
        ctx.draw(TestImages.noise(width: 64, height: 700), in: CGRect(x: 0, y: 0, width: 64, height: 700))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 700 - 140, width: 64, height: 40))
        let page = FakeScrollingPage(content: ctx.makeImage()!, viewportHeight: 120, scale: 1)
        let stitcher = ScrollStitcher(maxHeight: 32768)
        for position in [0, 20, 70, 130, 190, 250, 300, 240] {
            page.scrollTo(position)
            _ = stitcher.add(page.currentFrame(), hint: nil)
        }
        let image = PixelBuffer(stitcher.image()!)
        let expected = PixelBuffer(page.expectedImage)
        // Si è scesi fino a 300: l'immagine è il contenuto fino a 420, anche dopo essere tornati su a 240.
        #expect(image.height == 420)
        #expect((0..<image.height).allSatisfy { y in (0..<64).allSatisfy { image.pixel(x: $0, y: y) == expected.pixel(x: $0, y: y) } })
    }

    @Test func aRetinaFrameIsStitchedQuickly() {
        // 800×1000 px, come un'area di 400×500 punti a 2x: nella build di debug deve restare reattivo.
        let page = FakeScrollingPage(content: TestImages.noise(width: 800, height: 3000), viewportHeight: 1000, scale: 2)
        let stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(600)
        let frame = page.currentFrame()
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = stitcher.add(frame, hint: 600) }
        #expect(elapsed < .milliseconds(400), "\(elapsed)")
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
        let stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(70)
        #expect(stitcher.add(page.currentFrame(), hint: 70) == .appended(70))
        page.scrollTo(140)
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .ambiguous)
    }

    @Test func uniformContentUsesTheHintOrWaits() {
        let blank = TestImages.solid(width: 64, height: 600, red: 1, green: 1, blue: 1)
        let page = FakeScrollingPage(content: blank, viewportHeight: 120, scale: 1)
        let stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(page.position + 50)
        // Fotogrammi identici: nessun movimento visibile.
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .unchanged)
    }

    @Test func scrollingBackUpAppendsNothingTwice() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 600), viewportHeight: 120, scale: 1)
        let stitcher = ScrollStitcher(maxHeight: 32768)
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
        let stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        page.scrollTo(400)
        #expect(stitcher.add(page.currentFrame(), hint: 400) == .noMatch)
        // Il riferimento resta il fotogramma buono: tornando vicino si riprende.
        page.scrollTo(60)
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .appended(60))
    }

    /// Tabella larga 640 px: righe alte 40 px con lo stesso fondo e un "testo" diverso in ciascuna.
    func table(height: Int) -> CGImage {
        let ctx = FakeScrollingPage.context(width: 640, height: height)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 640, height: height))
        for row in 0..<(height / 40) {
            let top = height - (row + 1) * 40
            ctx.setFillColor(CGColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1))
            ctx.fill(CGRect(x: 0, y: top, width: 640, height: 1))
            ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1))
            // Stessa impaginazione in ogni riga (date, etichette, barre); cambia solo qualche cifra.
            for x in stride(from: 20, to: 600, by: 70) { ctx.fill(CGRect(x: x, y: top + 15, width: 50, height: 10)) }
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            for (column, factor) in [(1, 7), (3, 11), (5, 5), (7, 13)] {
                ctx.fill(CGRect(x: 25 + column * 70 + (row * factor) % 40, y: top + 17, width: 3, height: 6))
            }
        }
        return ctx.makeImage()!
    }

    /// Copia di `image` con la barra di scorrimento che macOS mostra a destra mentre si scorre.
    func withScrollbar(_ image: CGImage) -> CGImage {
        let ctx = FakeScrollingPage.context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: image.width - 20, y: 0, width: 20, height: image.height))
        ctx.setFillColor(CGColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1))
        ctx.fill(CGRect(x: image.width - 14, y: image.height / 3, width: 8, height: image.height / 3))
        return ctx.makeImage()!
    }

    @Test func theScrollbarShownWhileScrollingDoesNotBreakMatching() {
        let page = FakeScrollingPage(content: table(height: 1600), viewportHeight: 400, scale: 1)
        let stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        var steps: [StitchStep] = []
        for position in stride(from: 90, through: page.maxPosition, by: 90) {
            page.scrollTo(position)
            steps.append(stitcher.add(withScrollbar(page.currentFrame()), hint: nil))
        }
        #expect(steps.allSatisfy { $0 == .appended(90) }, "\(steps)")
    }

    /// Fotogramma di una chat: i fumetti (`bubbles`, trasparente fra l'uno e l'altro) scorrono sopra una tappezzeria ferma.
    func chatFrame(bubbles: CGImage, wallpaper: CGImage, position: Int, height: Int) -> CGImage {
        let width = bubbles.width
        let ctx = FakeScrollingPage.context(width: width, height: height)
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.9, blue: 0.85, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setAlpha(0.35)
        ctx.interpolationQuality = .none
        ctx.draw(wallpaper, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setAlpha(1)
        let visible = bubbles.cropping(to: CGRect(x: 0, y: position, width: width, height: height))!
        ctx.draw(visible, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Fumetti alti 40–70 px, alternati a sinistra e a destra, con 20 px di tappezzeria fra l'uno e l'altro.
    func bubbles(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let text = TestImages.noise(width: width, height: height)
        var top = 10, index = 0
        while top < height - 80 {
            let bubbleHeight = 40 + (index * 17) % 31
            let rect = CGRect(x: index % 2 == 0 ? 10 : width / 3, y: height - top - bubbleHeight, width: width * 2 / 3 - 10, height: bubbleHeight)
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.draw(text, in: CGRect(x: 0, y: 0, width: width, height: height))
            ctx.restoreGState()
            top += bubbleHeight + 20
            index += 1
        }
        return ctx.makeImage()!
    }

    @Test func aChatOverAStillWallpaperIsStitched() {
        let content = bubbles(width: 320, height: 1600)
        // Disegni grandi come quelli di WhatsApp: macchie di circa 13×12 px, non rumore fine che si annulla nella media.
        let wallpaper = TestImages.noise(width: 24, height: 25)
        let stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(chatFrame(bubbles: content, wallpaper: wallpaper, position: 0, height: 300), hint: nil)
        var steps: [StitchStep] = []
        for position in stride(from: 70, through: 1300, by: 70) {
            steps.append(stitcher.add(chatFrame(bubbles: content, wallpaper: wallpaper, position: position, height: 300), hint: nil))
        }
        #expect(steps.allSatisfy { $0 == .appended(70) }, "\(steps)")
    }

    /// Copia di `frame` con un pulsante rotondo fermo in basso a destra, come "vai in fondo" nelle chat.
    func withFloatingButton(_ frame: CGImage) -> CGImage {
        let ctx = FakeScrollingPage.context(width: frame.width, height: frame.height)
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: frame.width - 34, y: 10, width: 24, height: 24))
        return ctx.makeImage()!
    }

    @Test func aButtonThatStaysStillIsNotRepeatedDownTheImage() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 200, height: 1200), viewportHeight: 300, scale: 1)
        let stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(withFloatingButton(page.currentFrame()), hint: nil)
        for position in Array(stride(from: 40, to: page.maxPosition, by: 40)) + [page.maxPosition] {
            page.scrollTo(position)
            _ = stitcher.add(withFloatingButton(page.currentFrame()), hint: nil)
        }
        let image = PixelBuffer(stitcher.image()!)
        let expected = PixelBuffer(page.expectedImage)
        #expect(image.height == expected.height)
        // Ogni riga viene dal fotogramma in cui stava più vicina al centro: il pulsante resta solo nell'ultima mezza
        // schermata, dove c'era davvero alla fine.
        let clean = expected.height - page.viewportHeight / 2
        let wrong = (0..<clean).filter { y in (0..<image.width).contains { image.pixel(x: $0, y: y) != expected.pixel(x: $0, y: y) } }
        #expect(wrong.isEmpty, "\(wrong.count) righe sporche, la prima \(wrong.first ?? -1)")
    }

    /// Copia di `image` con le righe `rows` (dall'alto) scurite, come una riga evidenziata sotto il puntatore.
    func highlighted(_ image: CGImage, rows: Range<Int>) -> CGImage {
        let ctx = FakeScrollingPage.context(width: image.width, height: image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0.3, alpha: 0.35))
        ctx.fill(CGRect(x: 0, y: image.height - rows.upperBound, width: image.width, height: rows.count))
        return ctx.makeImage()!
    }

    @Test func aSmallChangeBeforeScrollingIsNotTakenForFixedBands() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 200, scale: 1)
        let stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(page.currentFrame(), hint: nil)
        // Solo una riga cambia (evidenziazione al passaggio del puntatore): non è uno scorrimento.
        #expect(stitcher.add(highlighted(page.currentFrame(), rows: 180..<184), hint: nil) == .unchanged)
        page.scrollTo(100)
        #expect(stitcher.add(page.currentFrame(), hint: nil) == .appended(100))
        #expect(stitcher.topBand == 0)
        #expect(stitcher.bottomBand == 0)
        for position in stride(from: 200, through: page.maxPosition, by: 100) {
            page.scrollTo(position)
            _ = stitcher.add(page.currentFrame(), hint: nil)
        }
        expectEqual(stitcher.image(), page.expectedImage)
    }

    @Test func aHighlightedRowUnderAStillPointerDoesNotBreakMatching() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 1500), viewportHeight: 300, scale: 1)
        let stitcher = ScrollStitcher(maxHeight: 32768)
        _ = stitcher.add(highlighted(page.currentFrame(), rows: 140..<160), hint: nil)
        for position in stride(from: 80, through: 800, by: 80) {
            page.scrollTo(position)
            #expect(stitcher.add(highlighted(page.currentFrame(), rows: 140..<160), hint: nil) == .appended(80), "at \(position)")
        }
    }

    @Test func stopsAtTheHeightLimit() {
        let page = FakeScrollingPage(content: TestImages.noise(width: 64, height: 900), viewportHeight: 120, scale: 1)
        let (stitcher, steps) = stitch(page, step: 80, maxHeight: 300)
        #expect(steps.last == .reachedLimit)
        #expect(stitcher.height == 300)
        #expect(PixelBuffer(stitcher.image()!).pixel(x: 5, y: 299) == PixelBuffer(page.expectedImage).pixel(x: 5, y: 299))
    }

    @Test func framesOfAnotherSizeAreRejected() {
        let stitcher = ScrollStitcher(maxHeight: 32768)
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

