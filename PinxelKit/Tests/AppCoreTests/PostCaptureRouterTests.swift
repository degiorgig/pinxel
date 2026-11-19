import Testing
@testable import AppCore

struct PostCaptureRouterTests {
    func settings(_ action: PostCaptureAction, autoSave: Bool) -> CaptureSettings {
        var settings = CaptureSettings()
        settings.postCaptureAction = action
        settings.autoSave = autoSave
        return settings
    }

    @Test func editor() {
        #expect(PostCaptureRouter.plan(for: settings(.openEditor, autoSave: false))
            == PostCapturePlan(immediate: [.openEditor], showsQuickPreview: false, afterPreview: []))
        #expect(PostCaptureRouter.plan(for: settings(.openEditor, autoSave: true))
            == PostCapturePlan(immediate: [.autoSave, .openEditor], showsQuickPreview: false, afterPreview: []))
    }

    @Test(arguments: [false, true]) func quickPreviewHandlesAutoSaveOnOpenAndExpiry(autoSave: Bool) {
        let plan = PostCaptureRouter.plan(for: settings(.quickPreview, autoSave: autoSave))
        let save: [PostCaptureStep] = autoSave ? [.autoSave] : []
        #expect(plan.showsQuickPreview)
        #expect(plan.immediate.isEmpty)
        #expect(plan.stepsAfterPreview(openEditor: false) == save)
        // The editor opens first: saving a large capture must not delay it.
        #expect(plan.stepsAfterPreview(openEditor: true) == [.openEditor] + save)
    }

    @Test func anIncompleteCaptureOnlyOpensTheEditor() {
        // Neither saved nor copied as if it were complete: the user sees what was captured and decides.
        #expect(PostCaptureRouter.planForIncompleteCapture()
            == PostCapturePlan(immediate: [.openEditor], showsQuickPreview: false, afterPreview: []))
    }

    @Test func clipboard() {
        #expect(PostCaptureRouter.plan(for: settings(.clipboardOnly, autoSave: false))
            == PostCapturePlan(immediate: [.copyToClipboard], showsQuickPreview: false, afterPreview: []))
        #expect(PostCaptureRouter.plan(for: settings(.clipboardOnly, autoSave: true))
            == PostCapturePlan(immediate: [.copyToClipboard, .autoSave], showsQuickPreview: false, afterPreview: []))
    }
}
