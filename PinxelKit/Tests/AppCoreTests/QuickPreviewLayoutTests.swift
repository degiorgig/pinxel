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

    @Test func whenTheColumnsRunOutTheStackStartsAgainFromTheCorner() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 600)
        let big = CGSize(width: 220, height: 220)
        let frames = QuickPreviewLayout.frames(for: Array(repeating: big, count: 7), in: small)
        // Two per column, three columns; the seventh starts again near the corner, moved so the first still shows.
        let step = QuickPreviewLayout.roundOffset
        #expect(frames[6] == frames[0].offsetBy(dx: -step, dy: step))
        #expect(frames.allSatisfy { small.insetBy(dx: QuickPreviewLayout.margin, dy: QuickPreviewLayout.margin).contains($0) })
    }

    /// Three full rounds (eighteen previews): each lands somewhere else, so no preview covers an older one exactly.
    @Test func noPreviewHidesAnOlderOneEntirely() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 600)
        let frames = QuickPreviewLayout.frames(for: Array(repeating: CGSize(width: 220, height: 220), count: 18), in: small)
        #expect(Set(frames.map { "\($0)" }).count == frames.count)
        #expect(frames.allSatisfy { small.insetBy(dx: QuickPreviewLayout.margin, dy: QuickPreviewLayout.margin).contains($0) })
    }

    /// A screen with no room for the moved round: it starts from the corner, still on screen.
    @Test func aTightScreenStartsAgainFromTheCorner() {
        let tight = CGRect(x: 0, y: 0, width: 300, height: 280)
        let size = CGSize(width: 250, height: 230)
        let frames = QuickPreviewLayout.frames(for: [size, size], in: tight)
        #expect(frames[1] == frames[0])
        #expect(frames.allSatisfy { tight.insetBy(dx: QuickPreviewLayout.margin, dy: QuickPreviewLayout.margin).contains($0) })
    }
}
