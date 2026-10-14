import Foundation

public enum StepNumbering {
    /// Etichetta visualizzata per ogni step, calcolata dall'ordine in `annotations`.
    public static func labels(for annotations: [Annotation]) -> [UUID: String] {
        var counters: [StepSequence: Int] = [:]
        var result: [UUID: String] = [:]
        for annotation in annotations {
            guard case .step(let data) = annotation.kind else { continue }
            let n = (counters[data.label.sequence] ?? 0) + 1
            counters[data.label.sequence] = n
            result[annotation.id] = data.label.override ?? format(n, data.label.sequence)
        }
        return result
    }

    /// 1 → "1" / "A" / "a"; le lettere usano la numerazione biiettiva in base 26 (27 → "AA").
    public static func format(_ n: Int, _ sequence: StepSequence) -> String {
        switch sequence {
        case .numbers:
            return String(n)
        case .uppercaseLetters, .lowercaseLetters:
            var value = max(n, 1)
            var letters: [Character] = []
            while value > 0 {
                value -= 1
                letters.append(Character(UnicodeScalar(UInt8(65 + value % 26))))
                value /= 26
            }
            let text = String(letters.reversed())
            return sequence == .uppercaseLetters ? text : text.lowercased()
        }
    }
}
