import CoreGraphics
import Testing
@testable import CaptureKit

struct SelectionModelTests {
    let displays = [
        DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 400, height: 300), scale: 2),
        DisplayInfo(id: 2, frame: CGRect(x: 400, y: 0, width: 400, height: 300), scale: 1),
    ]
    let window = WindowInfo(id: 7, frame: CGRect(x: 200, y: 100, width: 100, height: 100), title: "Note", appName: "Note", bundleIdentifier: "com.apple.Notes")

    func model(_ mode: CaptureMode) -> SelectionModel {
        SelectionModel(mode: mode, windows: [window], displays: displays)
    }

    @Test func dragCreatesArea() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 110, y: 60), square: false)
        #expect(m.selectionRect == CGRect(x: 10, y: 10, width: 100, height: 50))
        #expect(m.mouseUp(at: CGPoint(x: 110, y: 60)) == .area(CGRect(x: 10, y: 10, width: 100, height: 50)))
        #expect(m.phase == .hovering)
    }

    @Test func reverseDragIsNormalized() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 110, y: 60))
        m.mouseDragged(to: CGPoint(x: 10, y: 10), square: false)
        #expect(m.mouseUp(at: CGPoint(x: 10, y: 10)) == .area(CGRect(x: 10, y: 10, width: 100, height: 50)))
    }

    @Test func clickCapturesWindowOrScreen() {
        var m = model(.area)
        m.mouseMoved(to: CGPoint(x: 250, y: 150))
        #expect(m.highlightedWindow == window)
        m.mouseDown(at: CGPoint(x: 250, y: 150))
        m.mouseDragged(to: CGPoint(x: 251, y: 151), square: false) // sotto la soglia
        #expect(m.mouseUp(at: CGPoint(x: 251, y: 151)) == .window(window))

        m.mouseDown(at: CGPoint(x: 500, y: 50))
        #expect(m.mouseUp(at: CGPoint(x: 500, y: 50)) == .screen(displays[1]))
    }

    @Test func zeroWidthDragProducesNothing() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 10, y: 40), square: false)
        #expect(m.mouseUp(at: CGPoint(x: 10, y: 40)) == nil)
    }

    @Test func squareLock() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 110, y: 40), square: true)
        #expect(m.selectionRect == CGRect(x: 10, y: 10, width: 100, height: 100))
        m.mouseDragged(to: CGPoint(x: -40, y: 0), square: true)
        #expect(m.selectionRect == CGRect(x: -40, y: -40, width: 50, height: 50))
    }

    @Test func spaceMovesSelection() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 60, y: 60), square: false)
        m.moveSelection(by: CGSize(width: 5, height: -3))
        #expect(m.selectionRect == CGRect(x: 15, y: 7, width: 50, height: 50))
    }

    @Test func keys() {
        var m = model(.area)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 60, y: 60), square: false)
        #expect(m.key(.right, shift: false) == nil)
        #expect(m.key(.down, shift: true) == nil)
        #expect(m.selectionRect == CGRect(x: 10, y: 10, width: 51, height: 60))
        #expect(m.key(.enter, shift: false) == .area(CGRect(x: 10, y: 10, width: 51, height: 60)))

        var escaped = model(.area)
        #expect(escaped.key(.escape, shift: false) == .cancelled)

        var hovering = model(.area)
        hovering.mouseMoved(to: CGPoint(x: 250, y: 150))
        #expect(hovering.key(.left, shift: true) == nil)
        #expect(hovering.pointer == CGPoint(x: 240, y: 150))
        #expect(hovering.key(.enter, shift: false) == .window(window))
    }

    @Test func windowModeIgnoresDragsAndEmptyClicks() {
        var m = model(.window)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        m.mouseDragged(to: CGPoint(x: 110, y: 60), square: false)
        #expect(m.selectionRect == nil)
        #expect(m.mouseUp(at: CGPoint(x: 110, y: 60)) == nil)
    }

    @Test func windowModeClickOutsideWindowsDoesNothing() {
        var m = model(.window)
        m.mouseDown(at: CGPoint(x: 10, y: 10))
        #expect(m.mouseUp(at: CGPoint(x: 10, y: 10)) == nil)
        m.mouseDown(at: CGPoint(x: 250, y: 150))
        #expect(m.mouseUp(at: CGPoint(x: 250, y: 150)) == .window(window))
    }

    @Test func screenModeHighlightsAndPicksDisplay() {
        var m = model(.screen)
        m.mouseMoved(to: CGPoint(x: 600, y: 100))
        #expect(m.highlightedDisplay == displays[1])
        #expect(m.highlightedWindow == nil)
        m.mouseDown(at: CGPoint(x: 600, y: 100))
        m.mouseDragged(to: CGPoint(x: 700, y: 200), square: false)
        #expect(m.mouseUp(at: CGPoint(x: 700, y: 200)) == .screen(displays[1]))
    }
}
