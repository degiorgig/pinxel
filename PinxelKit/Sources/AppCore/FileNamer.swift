import Foundation

public enum FileNamer {
    /// The default of earlier versions: whoever still has it in settings has not customized it.
    public static let legacyDefaultTemplate = "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss"

    /// Default `DateFormatter` pattern in the app's language: fixed text goes between quotes.
    public static var defaultTemplate: String {
        String(localized: "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss", bundle: .module, comment: "Default file name: keep the quotes around fixed text")
    }

    /// The default in a specific language (for tests and settings).
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

    /// First free URL: "Name.ext", then "Name 2.ext", "Name 3.ext"…
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
