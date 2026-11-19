import CoreGraphics
import Testing
import AppCore

struct QuickPreviewLayoutTests {
    private let screen = CGRect(x: -1280, y: 32, width: 1280, height: 720)
    private let portrait = CGSize(width: 60, height: 220)
    private let landscape = CGSize(width: 220, height: 40)
    private let square = CGSize(width: 100, height: 100)

    @Test func previewsStackUsingTheHeightOfEachPrecedingPreview() {
        let frames = QuickPreviewLayout.frames(for: [portrait, landscape, square], in: screen)
        #expect(frames == [
            CGRect(origin: CGPoint(x: -80, y: 52), size: portrait),
            CGRect(origin: CGPoint(x: -240, y: 284), size: landscape),
            CGRect(origin: CGPoint(x: -120, y: 336), size: square),
        ])
    }

    @Test func closingAPreviewRepositionsTheRemainingPreviews() {
        let frames = QuickPreviewLayout.frames(for: [landscape, square], in: screen)
        #expect(frames == [
            CGRect(origin: CGPoint(x: -240, y: 52), size: landscape),
            CGRect(origin: CGPoint(x: -120, y: 104), size: square),
        ])
    }

    @Test func previewsThatDoNotFitStartANewColumnToTheLeft() {
        let frames = QuickPreviewLayout.frames(for: [portrait, portrait, portrait, square], in: screen)
        #expect(frames == [
            CGRect(origin: CGPoint(x: -80, y: 52), size: portrait),
            CGRect(origin: CGPoint(x: -80, y: 284), size: portrait),
            CGRect(origin: CGPoint(x: -152, y: 52), size: portrait),
            CGRect(origin: CGPoint(x: -192, y: 284), size: square),
        ])
        #expect(frames.allSatisfy { screen.insetBy(dx: QuickPreviewLayout.margin, dy: QuickPreviewLayout.margin).contains($0) })
    }
}
