import Foundation
import Testing
@testable import AppCore

struct KeyComboTests {
    @Test func defaultsAreControlShiftDigits() {
        #expect(HotKeyAction.area.defaultCombo.displayString == "⌃⇧1")
        #expect(HotKeyAction.window.defaultCombo.displayString == "⌃⇧2")
        #expect(HotKeyAction.screen.defaultCombo.displayString == "⌃⇧3")
        #expect(HotKeyAction.repeatLastArea.defaultCombo.displayString == "⌃⇧4")
    }

    @Test func modifierGlyphOrder() {
        let combo = KeyCombo(keyCode: 0x00, modifiers: KeyCombo.command | KeyCombo.shift | KeyCombo.option | KeyCombo.control)
        #expect(combo.displayString == "⌃⌥⇧⌘A")
        #expect(KeyCombo(keyCode: 0x7A, modifiers: KeyCombo.command).displayString == "⌘F1")
        #expect(KeyCombo(keyCode: 0x31, modifiers: KeyCombo.option).displayString == "⌥Spazio")
        #expect(KeyCombo(keyCode: 0x5A, modifiers: KeyCombo.control).displayString == "⌃Tasto 90")
    }

    @Test func cocoaFlagsMapToCarbon() {
        let cocoa: UInt = (1 << 18) | (1 << 17) // control + shift
        #expect(KeyCombo.carbonModifiers(fromCocoa: cocoa) == KeyCombo.control | KeyCombo.shift)
        let all: UInt = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 16) // + caps lock (ignorato)
        #expect(KeyCombo.carbonModifiers(fromCocoa: all) == KeyCombo.control | KeyCombo.shift | KeyCombo.option | KeyCombo.command)
    }

    @Test func bareKeyHasNoModifier() {
        #expect(!KeyCombo(keyCode: 0x12, modifiers: 0).hasModifier)
        #expect(KeyCombo(keyCode: 0x12, modifiers: KeyCombo.shift).hasModifier)
    }

    @Test func codableRoundTrip() throws {
        let combo = HotKeyAction.screen.defaultCombo
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        #expect(decoded == combo)
    }
}
