import AppCore
import AppKit
import Persistence

@MainActor
final class PostCaptureActions {
    private let notifier: Notifier
    private let autoSaver: AutoSaver
    private var previews: [QuickPreviewController] = []

    init(notifier: Notifier, autoSaver: AutoSaver = AutoSaver()) {
        self.notifier = notifier
        self.autoSaver = autoSaver
    }

    func perform(_ plan: PostCapturePlan, contents: PinxelFileContents, image: CGImage, settings: CaptureSettings) {
        var editorOpened = false
        run(plan.immediate, contents: contents, image: image, settings: settings, editorOpened: &editorOpened)
        guard plan.showsQuickPreview else { return }
        let preview = QuickPreviewController(
            image: image, scale: contents.document.scale,
            onOpen: { [weak self] in
                DocumentOpener.open(contents)
                self?.previews.removeAll()
            },
            onExpire: { [weak self] in
                guard let self else { return }
                var opened = false
                self.run(plan.afterPreview, contents: contents, image: image, settings: settings, editorOpened: &opened)
                self.previews.removeAll()
            }
        )
        previews.append(preview)
        preview.show()
    }

    private func run(_ steps: [PostCaptureStep], contents: PinxelFileContents, image: CGImage, settings: CaptureSettings, editorOpened: inout Bool) {
        for step in steps {
            switch step {
            case .openEditor:
                if !editorOpened {
                    DocumentOpener.open(contents)
                    editorOpened = true
                }
            case .copyToClipboard:
                Clipboard.copy(image)
                notifier.info("Cattura copiata negli appunti")
            case .autoSave:
                do {
                    _ = try autoSaver.save(contents, settings: settings, date: contents.document.metadata.captureDate)
                } catch {
                    notifier.failure(error)
                    // La cattura non va persa: resta aperta in una finestra.
                    if !editorOpened {
                        DocumentOpener.open(contents)
                        editorOpened = true
                    }
                }
            }
        }
    }
}
