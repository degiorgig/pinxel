import AppKit

/// Text view for on-canvas editing: bold and italic for the Format menu, on the selected words
/// (or on the text that will be typed, with no selection). Underline uses `underline(_:)` of `NSText`.
public final class PinxelTextView: NSTextView {
    @objc public func toggleBoldface(_ sender: Any?) {
        toggle(.boldFontMask)
    }

    @objc public func toggleItalics(_ sender: Any?) {
        toggle(.italicFontMask)
    }

    private func toggle(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else {
            if let font = typingAttributes[.font] as? NSFont {
                typingAttributes[.font] = Self.toggled(font, trait, manager: manager)
            }
            return
        }
        // If the whole run already has the style it removes it, otherwise it applies it to all.
        var allHave = true
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            if let font = value as? NSFont, !manager.traits(of: font).contains(trait) { allHave = false }
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            let converted = allHave ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: subrange)
        }
        storage.endEditing()
        didChangeText()
    }

    private static func toggled(_ font: NSFont, _ trait: NSFontTraitMask, manager: NSFontManager) -> NSFont {
        manager.traits(of: font).contains(trait) ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
    }
}
