import AppCore
import CaptureKit
import Foundation
import Library
import os
import UserNotifications

@MainActor
final class Notifier {
    private let enabled: Bool
    private let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "notifications")

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func failure(_ error: Error) {
        let message = Self.message(for: error)
        logger.error("\(message, privacy: .public)")
        post(title: String(localized: "Capture Failed"), body: message)
    }

    func info(_ text: String) {
        post(title: "Pinxel", body: text)
    }

    static func message(for error: Error) -> String {
        switch error {
        case CaptureError.windowNotFound: String(localized: "The window was closed before the capture.")
        case CaptureError.displayNotFound: String(localized: "The display is no longer available.")
        case CaptureError.emptySelection: String(localized: "The selection is empty.")
        case AutoSaveError.folderNotWritable(let path): String(localized: "Can't write to \(path). Choose another folder in Settings.")
        case AutoSaveError.writeFailed(let path): String(localized: "Saving failed: \(path).")
        case LibraryError.notWritable(let path): String(localized: "Can't write to the library (\(path)). The capture stays outside the library.")
        case LibraryError.writeFailed(let path): String(localized: "Saving to the library failed: \(path).")
        case LibraryError.unsupportedFile(let name): String(localized: "“\(name)” is neither an image nor a Pinxel document.")
        case LibraryError.trashUnavailable: String(localized: "The Trash isn't available for these files.")
        default: error.localizedDescription
        }
    }

    private func post(title: String, body: String) {
        guard enabled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
