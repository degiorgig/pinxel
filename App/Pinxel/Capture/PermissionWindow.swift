import AppKit
import CaptureKit
import SwiftUI

@MainActor
final class PermissionWindowController: NSWindowController {
    convenience init(permission: any ScreenRecordingPermission) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Permesso di registrazione schermo"
        window.contentView = NSHostingView(rootView: PermissionView(permission: permission))
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}

private struct PermissionView: View {
    let permission: any ScreenRecordingPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pinxel deve poter registrare lo schermo").font(.title3).bold()
            Text("Serve per catturare schermate. Le immagini restano sul tuo Mac. Concedi l'accesso in Impostazioni di Sistema → Privacy e sicurezza → Registrazione schermo e audio, poi riavvia Pinxel.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Concedi accesso…") {
                    permission.request()
                    permission.openSystemSettings()
                }
                .keyboardShortcut(.defaultAction)
                Button("Riavvia Pinxel", action: relaunch)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// Riavvia dopo l'uscita di questo processo, così la nuova istanza trova libere le scorciatoie globali.
    private func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
