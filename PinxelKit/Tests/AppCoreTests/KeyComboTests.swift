import Foundation
import Testing
@testable import AppCore

struct KeyComboTests {
    @Test func defaultsAreControlShiftDigits() {
        #expect(HotKeyAction.area.defaultCombo.displayString == "⌃⇧1")
        #expect(HotKeyAction.window.defaultCombo.displayString == "⌃⇧2")
        #expect(HotKeyAction.screen.defaultCombo.displayString == "⌃⇧3")
        #expect(HotKeyAction.repeatLastArea.defaultCombo.displayString == "⌃⇧4")
        #expect(HotKeyAction.scrolling.defaultCombo.displayString == "⌃⇧5")
        #expect(HotKeyAction.scrolling.title == "Scrolling Capture")
        #expect(Set(HotKeyAction.allCases.map(\.defaultCombo)).count == HotKeyAction.allCases.count)
    }

    @Test func modifierGlyphOrder() {
        let combo = KeyCombo(keyCode: 0x00, modifiers: KeyCombo.command | KeyCombo.shift | KeyCombo.option | KeyCombo.control)
        #expect(combo.displayString == "⌃⌥⇧⌘A")
        #expect(KeyCombo(keyCode: 0x7A, modifiers: KeyCombo.command).displayString == "⌘F1")
        #expect(KeyCombo(keyCode: 0x31, modifiers: KeyCombo.option).displayString == "⌥Space")
        #expect(KeyCombo(keyCode: 0x5A, modifiers: KeyCombo.control).displayString == "⌃Key 90")
    }

    @Test func menuKeyEquivalentForNativeShortcutColumn() {
        #expect(KeyCombo(keyCode: 0x15, modifiers: KeyCombo.command | KeyCombo.shift).menuKeyEquivalent == "4")
        #expect(KeyCombo(keyCode: 0x00, modifiers: KeyCombo.command).menuKeyEquivalent == "a")
        #expect(KeyCombo(keyCode: 0x31, modifiers: KeyCombo.option).menuKeyEquivalent == " ")
        #expect(KeyCombo(keyCode: 0x7A, modifiers: KeyCombo.command).menuKeyEquivalent == "\u{F704}")
        #expect(KeyCombo(keyCode: 0x6F, modifiers: KeyCombo.command).menuKeyEquivalent == "\u{F70F}")
        #expect(KeyCombo(keyCode: 0x5A, modifiers: KeyCombo.control).menuKeyEquivalent == nil)
    }

    @Test func cocoaFlagsMapToCarbon() {
        let cocoa: UInt = (1 << 18) | (1 << 17) // control + shift
        #expect(KeyCombo.carbonModifiers(fromCocoa: cocoa) == KeyCombo.control | KeyCombo.shift)
        let all: UInt = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 16) // + caps lock (ignored)
        #expect(KeyCombo.carbonModifiers(fromCocoa: all) == KeyCombo.control | KeyCombo.shift | KeyCombo.option | KeyCombo.command)
    }

    @Test func bareKeyHasNoModifier() {
        #expect(!KeyCombo(keyCode: 0x12, modifiers: 0).hasModifier)
        // Only ⇧ on a key that types is equivalent to a bare key ("!", capital "A").
        #expect(!KeyCombo(keyCode: 0x12, modifiers: KeyCombo.shift).hasModifier)
        #expect(!KeyCombo(keyCode: 0x00, modifiers: KeyCombo.shift).hasModifier)
        #expect(KeyCombo(keyCode: 0x12, modifiers: KeyCombo.shift | KeyCombo.control).hasModifier)
        #expect(KeyCombo(keyCode: 0x12, modifiers: KeyCombo.command).hasModifier)
        // Function keys can be used on their own or with ⇧.
        #expect(KeyCombo(keyCode: 0x7A, modifiers: KeyCombo.shift).hasModifier)
        #expect(KeyCombo(keyCode: 0x7A, modifiers: 0).hasModifier)
    }

    @Test func codableRoundTrip() throws {
        let combo = HotKeyAction.screen.defaultCombo
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo))
        #expect(decoded == combo)
    }
}
