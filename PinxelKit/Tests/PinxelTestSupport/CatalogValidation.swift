import Foundation

/// Controlli sui String Catalog (`.xcstrings`): ogni testo tradotto in tutte le lingue, niente valori vuoti,
/// stessi segnaposto della lingua di base (l'ordine può cambiare con i segnaposto posizionali `%2$lld`).
public enum CatalogValidation {
    public static func problems(inCatalogAt url: URL, languages: [String] = ["it", "de", "fr"]) throws -> [String] {
        try problems(inCatalog: Data(contentsOf: url), languages: languages)
    }

    public static func problems(inCatalog data: Data, languages: [String]) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else { return ["not a string catalog"] }
        var problems: [String] = []
        for key in strings.keys.sorted() {
            guard let entry = strings[key] as? [String: Any] else { continue }
            if entry["shouldTranslate"] as? Bool == false { continue }
            let source = placeholders(in: key)
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in languages {
                guard let localization = localizations[language] as? [String: Any] else {
                    problems.append("\(key): missing \(language)")
                    continue
                }
                for unit in units(in: localization) {
                    let state = unit["state"] as? String ?? ""
                    let value = unit["value"] as? String ?? ""
                    if value.isEmpty {
                        problems.append("\(key): empty \(language)")
                    } else if state != "translated" {
                        problems.append("\(key): \(language) is \(state)")
                    } else if placeholders(in: value) != source {
                        problems.append("\(key): placeholders \(language) \(list(placeholders(in: value))) ≠ \(list(source))")
                    }
                }
            }
        }
        return problems
    }

    /// Le `stringUnit` di una localizzazione, anche dentro le varianti (plurali, dispositivi).
    private static func units(in node: [String: Any]) -> [[String: Any]] {
        var found: [[String: Any]] = []
        if let unit = node["stringUnit"] as? [String: Any] { found.append(unit) }
        if let variations = node["variations"] as? [String: Any] {
            for case let group as [String: Any] in variations.values {
                for case let child as [String: Any] in group.values { found += units(in: child) }
            }
        }
        return found
    }

    private static func list(_ items: [String]) -> String { "[" + items.joined(separator: ", ") + "]" }

    /// Segnaposto in ordine canonico: `%2$lld` conta come `%lld`; `%%` non è un segnaposto.
    static func placeholders(in text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(lld|ld|d|@|f|\.\d+f|s)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let clean = text.replacingOccurrences(of: "%%", with: "")
        return regex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean))
            .map { "%" + (clean as NSString).substring(with: $0.range(at: 1)) }
            .sorted()
    }
}

/// Percorso dei cataloghi dei moduli a partire dal file del test (i test non leggono il bundle: controllano il sorgente).
public enum Catalogs {
    public static func url(module: String, file: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: file)
        while url.lastPathComponent != "Tests", url.path != "/" { url.deleteLastPathComponent() }
        return url.deletingLastPathComponent().appendingPathComponent("Sources/\(module)/Localizable.xcstrings")
    }
}
