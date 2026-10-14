import Foundation

/// Combinazione di tasti per le scorciatoie globali (codice tasto + modificatori Carbon).
public struct KeyCombo: Codable, Hashable, Sendable {
    public static let control: UInt32 = 0x1000
    public static let option: UInt32 = 0x0800
    public static let shift: UInt32 = 0x0200
    public static let command: UInt32 = 0x0100

    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Una scorciatoia globale senza ⌃, ⌥ o ⌘ ruberebbe il tasto a tutte le app (anche ⇧1 = "!").
    /// Fanno eccezione i tasti funzione, che non scrivono testo.
    public var hasModifier: Bool {
        if Self.functionKeys.contains(keyCode) { return true }
        return modifiers & (Self.control | Self.option | Self.command) != 0
    }

    static let functionKeys: Set<UInt32> = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]

    public var displayString: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Tasto \(keyCode)")
    }

    /// Da `NSEvent.ModifierFlags.rawValue` ai modificatori Carbon.
    public static func carbonModifiers(fromCocoa flags: UInt) -> UInt32 {
        var result: UInt32 = 0
        if flags & (1 << 18) != 0 { result |= control }
        if flags & (1 << 19) != 0 { result |= option }
        if flags & (1 << 17) != 0 { result |= shift }
        if flags & (1 << 20) != 0 { result |= command }
        return result
    }

    /// Carattere per la colonna nativa delle scorciatoie nei menu; `nil` se il tasto non ne ha uno.
    public var menuKeyEquivalent: String? {
        let functionKeyOrder: [UInt32] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        if let index = functionKeyOrder.firstIndex(of: keyCode) {
            // NSF1FunctionKey = 0xF704, poi consecutivi fino a F12.
            return String(UnicodeScalar(0xF704 + UInt32(index))!)
        }
        if keyCode == 0x31 { return " " }
        guard let name = Self.keyNames[keyCode], name.count == 1 else { return nil }
        return name.lowercased()
    }

    static let keyNames: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y",
        0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x19: "9",
        0x1A: "7", 0x1C: "8", 0x1D: "0", 0x1F: "O", 0x20: "U", 0x22: "I", 0x23: "P", 0x25: "L",
        0x26: "J", 0x28: "K", 0x2D: "N", 0x2E: "M", 0x31: "Spazio",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
}

public enum HotKeyAction: String, Codable, CaseIterable, Sendable {
    case area, window, screen, repeatLastArea

    public var title: String {
        switch self {
        case .area: "Cattura area"
        case .window: "Cattura finestra"
        case .screen: "Cattura schermo"
        case .repeatLastArea: "Ripeti ultima area"
        }
    }

    public var defaultCombo: KeyCombo {
        let modifiers = KeyCombo.control | KeyCombo.shift
        switch self {
        case .area: return KeyCombo(keyCode: 0x12, modifiers: modifiers)
        case .window: return KeyCombo(keyCode: 0x13, modifiers: modifiers)
        case .screen: return KeyCombo(keyCode: 0x14, modifiers: modifiers)
        case .repeatLastArea: return KeyCombo(keyCode: 0x15, modifiers: modifiers)
        }
    }
}
