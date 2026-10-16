import AppKit

/// Text view della modifica sulla tela: grassetto e corsivo per il menu Formato, sulle parole selezionate
/// (o sul testo che si scriverà, senza selezione). Il sottolineato usa `underline(_:)` di `NSText`.
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
        // Se tutto il tratto ha già lo stile lo toglie, altrimenti lo mette a tutto.
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
