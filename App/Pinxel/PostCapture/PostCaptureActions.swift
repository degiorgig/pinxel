import AppCore
import AppKit
import Library
import Persistence

@MainActor
final class PostCaptureActions {
    private let notifier: Notifier
    private let autoSaver: AutoSaver
    private let library: LibraryModel
    private var previews: [QuickPreviewController] = []
    /// Where the current stack of previews lives: the screen of the first one, until the stack is empty.
    private var previewScreen: CGRect?
    /// Called on every capture, whatever the chosen action.
    var onCapture: ((AppEnvironment.LastCapture) -> Void)?

    init(notifier: Notifier, library: LibraryModel, autoSaver: AutoSaver = AutoSaver()) {
        self.notifier = notifier
        self.library = library
        self.autoSaver = autoSaver
    }

    func perform(_ plan: PostCapturePlan, contents: PinxelFileContents, image: CGImage, settings: CaptureSettings) {
        // First of all into the archive; if that fails, the capture follows the usual path.
        var libraryURL: URL?
        if plan.addsToLibrary {
            do {
                libraryURL = try library.add(contents)
            } catch {
                notifier.failure(error)
            }
        }
        onCapture?(libraryURL.map { .file($0) } ?? .contents(contents))
        let editor = EditorState()
        run(plan.immediate, contents: contents, libraryURL: libraryURL, image: image, settings: settings, editor: editor)
        guard plan.showsQuickPreview else { return }
        // Each preview removes only itself from the list: the others still visible must stay alive.
        weak var finished: QuickPreviewController?
        let preview = QuickPreviewController(
            image: image, scale: contents.document.scale,
            onComplete: { [weak self] openEditor in
                guard let self else { return }
                let steps = plan.stepsAfterPreview(openEditor: openEditor)
                self.run(steps, contents: contents, libraryURL: libraryURL, image: image, settings: settings, editor: EditorState())
                self.removePreview(finished)
            }
        )
        finished = preview
        previews.append(preview)
        positionPreviews(adding: preview)
    }

    /// Removes the finished preview and moves the remaining ones down.
    private func removePreview(_ preview: QuickPreviewController?) {
        previews.removeAll { $0 === preview }
        positionPreviews()
    }

    private func positionPreviews(adding newPreview: QuickPreviewController? = nil) {
        // An empty stack forgets its screen: the next one appears where the user is working then.
        guard !previews.isEmpty else {
            previewScreen = nil
            return
        }
        let screen = previewScreen ?? NSScreen.main?.visibleFrame ?? .zero
        previewScreen = screen
        let frames = QuickPreviewLayout.frames(for: previews.map(\.size), in: screen)
        for (preview, frame) in zip(previews, frames) {
            if preview === newPreview {
                preview.show(at: frame)
            } else {
                preview.move(to: frame)
            }
        }
    }

    private func openEditor(_ contents: PinxelFileContents, libraryURL: URL?) {
        if let libraryURL {
            if !LibraryOpener.openCapture(at: libraryURL) { DocumentOpener.open(url: libraryURL) }
        } else {
            DocumentOpener.open(contents)
        }
    }

    /// Whether this capture's editor is open: a save that fails later opens it only once.
    private final class EditorState {
        var opened = false
    }

    private func run(_ steps: [PostCaptureStep], contents: PinxelFileContents, libraryURL: URL?, image: CGImage, settings: CaptureSettings, editor: EditorState) {
        let openOnce = { [weak self] in
            guard !editor.opened else { return }
            editor.opened = true
            self?.openEditor(contents, libraryURL: libraryURL)
        }
        for step in steps {
            switch step {
            case .openEditor:
                openOnce()
            case .copyToClipboard:
                Clipboard.copy(image)
                notifier.info(String(localized: "Capture copied to the clipboard"))
            case .autoSave:
                // Rendering and encoding a tall capture takes time: off the main thread, so the editor and previews stay responsive.
                let saver = autoSaver
                Task { [notifier] in
                    do {
                        _ = try await Task.detached(priority: .userInitiated) {
                            try saver.save(contents, settings: settings, date: contents.document.metadata.captureDate)
                        }.value
                    } catch {
                        notifier.failure(error)
                        // The capture must not be lost: it stays open in a window.
                        openOnce()
                    }
                }
            }
        }
    }
}
