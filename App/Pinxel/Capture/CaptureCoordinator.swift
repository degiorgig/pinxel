import AppCore
import AppKit
import CaptureKit
import DocumentModel
import os

/// Ciò che serve alla cattura a scorrimento; nei UI test la pagina finta fa da sorgente.
/// Scorre sempre l'utente: Pinxel cattura e cuce finché si preme Fine o Invio.
@MainActor
struct ScrollCaptureDependencies {
    /// Serve solo perché Esc e Invio non arrivino anche all'app sotto.
    let accessibility: any AccessibilityPermission
    let makeSource: () -> any RegionFrameSource
    let presenter: any ScrollCapturePresenting
    let defaults: UserDefaults
}

@MainActor
final class CaptureCoordinator {
    private let engine: any CaptureEngine
    private let permission: any ScreenRecordingPermission
    private let selection: any SelectionProvider
    private let actions: PostCaptureActions
    private let settings: () -> CaptureSettings
    private let scrolling: ScrollCaptureDependencies
    private var isCapturing = false
    private var lastArea: CGRect?
    private var permissionWindow: PermissionWindowController?
    private let logger = Logger(subsystem: "com.degiorgi.pinxel", category: "capture")

    init(engine: any CaptureEngine, permission: any ScreenRecordingPermission, selection: any SelectionProvider,
         actions: PostCaptureActions, scrolling: ScrollCaptureDependencies, settings: @escaping () -> CaptureSettings) {
        self.engine = engine
        self.permission = permission
        self.selection = selection
        self.actions = actions
        self.settings = settings
        self.scrolling = scrolling
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
        guard !isCapturing else {
            logger.info("capture ignored: already capturing")
            return
        }
        isCapturing = true
        defer { isCapturing = false }

        guard permission.isGranted else {
            logger.info("capture blocked: screen recording permission not granted")
            showPermissionWindow()
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let current = settings()
        do {
            logger.info("capture: taking snapshot")
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
            logger.error("capture failed: \(String(describing: error), privacy: .public)")
            AppEnvironment.shared.notifier.failure(error)
            frontmost?.activate()
        }
    }

    static let maxScrollingHeight = 32768 // PinxelDocument.maxImageSide
    private static let accessibilityAskedKey = "PinxelAccessibilityRequested"

    func captureScrolling() async {
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
            logger.notice("scrolling capture: taking snapshot")
            let snapshot = try await engine.snapshot(excludingBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.degiorgi.pinxel")
            let choice: SelectionResult
            if let debugRect = Self.debugScrollRect() {
                choice = .area(debugRect)
            } else {
                choice = await selection.select(mode: .area, snapshot: snapshot)
            }
            guard case .area(let selected) = choice else {
                frontmost?.activate()
                return
            }
            let center = CGPoint(x: selected.midX, y: selected.midY)
            guard let display = ScreenGeometry.display(at: center, in: snapshot.displays.map(\.info)) else { throw CaptureError.displayNotFound }
            logger.notice("scrolling capture: area \(String(describing: selected), privacy: .public) on display \(String(describing: display.frame), privacy: .public) scale \(display.scale, privacy: .public), accessibility \(self.scrolling.accessibility.isGranted, privacy: .public)")
            guard let prepared = ScrollCaptureGeometry.prepare(selected, on: display, maxHeight: Self.maxScrollingHeight) else {
                AppEnvironment.shared.notifier.info("Area troppo bassa per la cattura a scorrimento: almeno \(Int(ScrollCaptureGeometry.minimumHeight)) punti")
                frontmost?.activate()
                return
            }
            if !scrolling.accessibility.isGranted, !scrolling.defaults.bool(forKey: Self.accessibilityAskedKey) {
                scrolling.defaults.set(true, forKey: Self.accessibilityAskedKey)
                scrolling.accessibility.request()
            }
            // L'app sotto l'area deve ricevere lo scorrimento dell'utente: torna davanti prima di iniziare.
            frontmost?.activate()
            let session = ScrollCaptureSession(source: scrolling.makeSource(), rect: prepared.rect,
                                               display: display, maxHeight: Self.maxScrollingHeight)
            guard let image = await scrolling.presenter.run(session, rect: prepared.rect, display: display, narrowed: prepared.narrowed) else { return }
            var metadata = CaptureMetadata(captureDate: Date(), appName: frontmost?.localizedName, bundleIdentifier: frontmost?.bundleIdentifier)
            metadata.windowTitle = nil
            let contents = try CaptureDocumentBuilder.make(image: image, scale: display.scale, metadata: metadata)
            let plan = PostCaptureRouter.plan(for: current)
            actions.perform(plan, contents: contents, image: image, settings: current)
            if session.outcome == .reachedLimit {
                AppEnvironment.shared.notifier.info("Raggiunta l'altezza massima di \(Self.maxScrollingHeight) pixel")
            } else if session.outcome == .contentChanging {
                AppEnvironment.shared.notifier.info("Il contenuto cambia da solo: cattura fermata")
            }
        } catch {
            logger.error("scrolling capture failed: \(String(describing: error), privacy: .public)")
            AppEnvironment.shared.notifier.failure(error)
            frontmost?.activate()
        }
    }

    /// Solo in Debug: `-PinxelDebugScrollRect x,y,w,h` salta la selezione, per provare la cattura vera da script.
    private static func debugScrollRect() -> CGRect? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PinxelDebugScrollRect"), index + 1 < arguments.count else { return nil }
        let values = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
        guard values.count == 4 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        #else
        return nil
        #endif
    }

    private func showPermissionWindow() {
        let controller = permissionWindow ?? PermissionWindowController(permission: permission)
        permissionWindow = controller
        controller.showWindow(nil)
        // Un'app agente non sempre viene attivata: la finestra va comunque davanti alle altre.
        controller.window?.level = .floating
        controller.window?.orderFrontRegardless()
        NSApp.activate()
    }
}
