import AppCore
import AppKit
import CaptureKit
import DocumentModel

@MainActor
final class CaptureCoordinator {
    private let engine: any CaptureEngine
    private let permission: any ScreenRecordingPermission
    private let selection: any SelectionProvider
    private let actions: PostCaptureActions
    private let settings: () -> CaptureSettings
    private var isCapturing = false
    private var lastArea: CGRect?
    private var permissionWindow: PermissionWindowController?

    init(engine: any CaptureEngine, permission: any ScreenRecordingPermission, selection: any SelectionProvider,
         actions: PostCaptureActions, settings: @escaping () -> CaptureSettings) {
        self.engine = engine
        self.permission = permission
        self.selection = selection
        self.actions = actions
        self.settings = settings
    }

    func capture(_ mode: CaptureMode) async {
        await run { [selection] snapshot in await selection.select(mode: mode, snapshot: snapshot) }
    }

    func repeatLastArea() async {
        guard let area = lastArea else {
            await capture(.area)
            return
        }
        await run { _ in .area(area) }
    }

    private func run(_ choose: (CaptureSnapshot) async -> SelectionResult) async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        guard permission.isGranted else {
            showPermissionWindow()
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let current = settings()
        do {
            let snapshot = try await engine.snapshot(excludingBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.degiorgi.pinxel")
            let image: CGImage
            let scale: Double
            var metadata = CaptureMetadata(captureDate: Date(), appName: frontmost?.localizedName, bundleIdentifier: frontmost?.bundleIdentifier)

            switch await choose(snapshot) {
            case .cancelled:
                frontmost?.activate()
                return
            case .area(let rect):
                guard let composed = CaptureComposer.compose(rect, from: snapshot.displays) else { throw CaptureError.emptySelection }
                image = composed.image
                scale = composed.scale
                lastArea = rect
            case .window(let window):
                image = try await engine.captureWindow(window.id, includeShadow: current.includeWindowShadow)
                scale = snapshot.scale(for: window)
                metadata.appName = window.appName
                metadata.bundleIdentifier = window.bundleIdentifier
                metadata.windowTitle = window.title
            case .screen(let display):
                guard let frozen = snapshot.displays.first(where: { $0.info.id == display.id }) else { throw CaptureError.displayNotFound }
                image = frozen.image
                scale = display.scale
            }

            let contents = try CaptureDocumentBuilder.make(image: image, scale: scale, metadata: metadata)
            let plan = PostCaptureRouter.plan(for: current)
            actions.perform(plan, contents: contents, image: image, settings: current)
            // L'overlay ha attivato Pinxel: se non si apre una finestra, il focus torna all'app di prima (es. per ⌘V).
            if !plan.immediate.contains(.openEditor), frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
                frontmost?.activate()
            }
        } catch {
            AppEnvironment.shared.notifier.failure(error)
            frontmost?.activate()
        }
    }

    private func showPermissionWindow() {
        let controller = permissionWindow ?? PermissionWindowController(permission: permission)
        permissionWindow = controller
        controller.showWindow(nil)
        NSApp.activate()
    }
}
