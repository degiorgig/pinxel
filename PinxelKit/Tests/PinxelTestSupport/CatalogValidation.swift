import Foundation

/// Checks on the String Catalogs (`.xcstrings`): every text translated into all languages, no empty values,
/// same placeholders as the base language (the order may change with positional placeholders `%2$lld`).
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

    /// The `stringUnit`s of a localization, also inside variations (plurals, devices).
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

    /// Placeholders in canonical order: `%2$lld` counts as `%lld`; `%%` is not a placeholder.
    static func placeholders(in text: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(lld|ld|d|@|f|\.\d+f|s)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let clean = text.replacingOccurrences(of: "%%", with: "")
        return regex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean))
            .map { "%" + (clean as NSString).substring(with: $0.range(at: 1)) }
            .sorted()
    }
}

/// Path of the modules' catalogs starting from the test file (tests do not read the bundle: they check the source).
public enum Catalogs {
    public static func url(module: String, file: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: file)
        while url.lastPathComponent != "Tests", url.path != "/" { url.deleteLastPathComponent() }
        return url.deletingLastPathComponent().appendingPathComponent("Sources/\(module)/Localizable.xcstrings")
    }
}

extension Bundle {
    /// The resource bundle of a PinxelKit module (`PinxelKit_<Module>.bundle`), looked up next to the tests.
    public static func module(for module: String) -> Bundle? {
        let name = "PinxelKit_\(module).bundle"
        // Under `swift test` the resource bundles sit next to the `.xctest` that contains this code.
        let candidates = [Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent(),
                          Bundle.main.bundleURL, Bundle.main.bundleURL.deletingLastPathComponent()]
            + Bundle.allBundles.map { $0.bundleURL.deletingLastPathComponent() }
        return candidates.lazy.map { $0.appendingPathComponent(name) }.compactMap { Bundle(url: $0) }.first
    }
}

private final class BundleMarker {}
