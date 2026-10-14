import AppCore
import CaptureKit
import Foundation
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
        post(title: "Cattura non riuscita", body: message)
    }

    func info(_ text: String) {
        post(title: "Pinxel", body: text)
    }

    static func message(for error: Error) -> String {
        switch error {
        case CaptureError.windowNotFound: "La finestra è stata chiusa prima della cattura."
        case CaptureError.displayNotFound: "Lo schermo non è più disponibile."
        case CaptureError.emptySelection: "La selezione è vuota."
        case AutoSaveError.folderNotWritable(let path): "Impossibile scrivere in \(path). Scegli un'altra cartella nelle Preferenze."
        case AutoSaveError.writeFailed(let path): "Salvataggio non riuscito: \(path)."
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
