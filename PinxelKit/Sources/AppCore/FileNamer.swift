import Foundation

public enum FileNamer {
    /// Modello `DateFormatter`: il testo fisso va tra apici.
    public static let defaultTemplate = "'Pinxel' yyyy-MM-dd 'at' HH.mm.ss"

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
