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
    /// Chiamato a ogni cattura, qualunque sia l'azione scelta.
    var onCapture: ((AppEnvironment.LastCapture) -> Void)?

    init(notifier: Notifier, library: LibraryModel, autoSaver: AutoSaver = AutoSaver()) {
        self.notifier = notifier
        self.library = library
        self.autoSaver = autoSaver
    }

    func perform(_ plan: PostCapturePlan, contents: PinxelFileContents, image: CGImage, settings: CaptureSettings) {
        // Prima di tutto nell'archivio; se non riesce, la cattura segue la via di sempre.
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
        // Ogni anteprima toglie dall'elenco solo se stessa: le altre ancora visibili devono restare vive.
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

    /// Toglie l'anteprima finita e fa scendere quelle rimaste.
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
                    // La cattura non va persa: resta aperta in una finestra.
                    if !editorOpened {
                        openEditor(contents, libraryURL: libraryURL)
                        editorOpened = true
                    }
                }
            }
        }
    }
}
