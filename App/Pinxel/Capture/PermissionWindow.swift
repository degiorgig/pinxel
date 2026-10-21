import AppKit
import CaptureKit
import SwiftUI

@MainActor
final class PermissionWindowController: NSWindowController {
    convenience init(permission: any ScreenRecordingPermission) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260), styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = String(localized: "Screen Recording Permission")
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
            Text("Pinxel needs to record the screen").font(.title3).bold()
            Text("It needs this to take screenshots. Images stay on your Mac. Grant access in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch Pinxel.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Grant Access…") {
                    permission.request()
                    permission.openSystemSettings()
                }
                .keyboardShortcut(.defaultAction)
                Button("Relaunch Pinxel", action: relaunch)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// Frees the global shortcuts first, so the new instance can register them, then quits once it is launched.
    /// `NSWorkspace` rather than a shell: it also works inside the App Sandbox.
    private func relaunch() {
        AppEnvironment.shared.releaseHotKeys()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
