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
        do {
            libraryURL = try library.add(contents)
        } catch {
            notifier.failure(error)
        }
        onCapture?(libraryURL.map { .file($0) } ?? .contents(contents))
        var editorOpened = false
        run(plan.immediate, contents: contents, libraryURL: libraryURL, image: image, settings: settings, editorOpened: &editorOpened)
        guard plan.showsQuickPreview else { return }
        // Each preview removes only itself from the list: the others still visible must stay alive.
        weak var finished: QuickPreviewController?
        let preview = QuickPreviewController(
            image: image, scale: contents.document.scale,
            onOpen: { [weak self] in
                self?.openEditor(contents, libraryURL: libraryURL)
                self?.removePreview(finished)
            },
            onExpire: { [weak self] in
                guard let self else { return }
                var opened = false
                self.run(plan.afterPreview, contents: contents, libraryURL: libraryURL, image: image, settings: settings, editorOpened: &opened)
                self.removePreview(finished)
            }
        )
        finished = preview
        previews.append(preview)
        preview.show(stackIndex: previews.count - 1)
    }

    /// Removes the finished preview and moves the remaining ones down.
    private func removePreview(_ preview: QuickPreviewController?) {
        previews.removeAll { $0 === preview }
        for (index, remaining) in previews.enumerated() { remaining.move(toStackIndex: index) }
    }

    private func openEditor(_ contents: PinxelFileContents, libraryURL: URL?) {
        if let libraryURL { DocumentOpener.open(url: libraryURL) } else { DocumentOpener.open(contents) }
    }

    private func run(_ steps: [PostCaptureStep], contents: PinxelFileContents, libraryURL: URL?, image: CGImage, settings: CaptureSettings, editorOpened: inout Bool) {
        for step in steps {
            switch step {
            case .openEditor:
                if !editorOpened {
                    openEditor(contents, libraryURL: libraryURL)
                    editorOpened = true
                }
            case .copyToClipboard:
                Clipboard.copy(image)
                notifier.info(String(localized: "Capture copied to the clipboard"))
            case .autoSave:
                do {
                    _ = try autoSaver.save(contents, settings: settings, date: contents.document.metadata.captureDate)
                } catch {
                    notifier.failure(error)
                    // The capture must not be lost: it stays open in a window.
                    if !editorOpened {
                        openEditor(contents, libraryURL: libraryURL)
                        editorOpened = true
                    }
                }
            }
        }
    }
}
