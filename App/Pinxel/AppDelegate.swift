import AppCore
import AppKit
import DocumentModel
import Persistence

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppEnvironment.shared.start()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            // Dopo la chiusura, senza documenti aperti l'app torna agente (niente icona nel Dock).
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if NSDocumentController.shared.documents.isEmpty {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-PinxelUITestOpenSample") {
            openSample()
        }
        if ProcessInfo.processInfo.arguments.contains("-PinxelUITestCaptureOnLaunch") {
            AppEnvironment.shared.capture(.area)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    private func openSample() {
        let size = 200
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let image = ctx.makeImage(),
              let contents = try? CaptureDocumentBuilder.make(image: image, scale: 1, metadata: CaptureMetadata()) else { return }
        DocumentOpener.open(contents)
    }
}
