import AppCore
import AppKit

/// "Open the image" option of the damaged-file error: opens the intact background in a new document.
final class RecoveryAttempter: NSObject {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    override func attemptRecovery(fromError error: Error, optionIndex recoveryOptionIndex: Int) -> Bool {
        guard recoveryOptionIndex == 0 else { return false }
        let data = self.data
        return MainActor.assumeIsolated {
            guard let contents = DocumentRecovery.contents(fromDamaged: data, scale: Double(NSScreen.main?.backingScaleFactor ?? 2)) else {
                return false
            }
            DocumentOpener.open(contents)
            return true
        }
    }
}
