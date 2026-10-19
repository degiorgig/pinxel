import Foundation

public enum FileNamer {
    /// Il predefinito delle versioni precedenti: chi lo ha ancora nelle impostazioni non l'ha personalizzato.
    public static let legacyDefaultTemplate = "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss"

    /// Modello `DateFormatter` predefinito nella lingua dell'app: il testo fisso va tra apici.
    public static var defaultTemplate: String {
        String(localized: "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss", bundle: .module, comment: "Default file name: keep the quotes around fixed text")
    }

    /// Il predefinito in una lingua precisa (per i test e per le impostazioni).
    public static func defaultTemplate(for language: String) -> String {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else {
            return legacyDefaultTemplate
        }
        return bundle.localizedString(forKey: legacyDefaultTemplate, value: legacyDefaultTemplate, table: nil)
    }

    public static func baseName(template: String, date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = template
        let name = formatter.string(from: date)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Pinxel" : name
    }

    /// Primo URL libero: "Nome.ext", poi "Nome 2.ext", "Nome 3.ext"…
    public static func uniqueURL(in folder: URL, baseName: String, fileExtension: String, fileManager: FileManager = .default) -> URL {
        var candidate = folder.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        return candidate
    }
}
