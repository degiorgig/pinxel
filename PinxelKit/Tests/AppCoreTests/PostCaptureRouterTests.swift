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

    @Test func quickPreviewSavesWhenItExpires() {
        #expect(PostCaptureRouter.plan(for: settings(.quickPreview, autoSave: true))
            == PostCapturePlan(immediate: [], showsQuickPreview: true, afterPreview: [.autoSave]))
        #expect(PostCaptureRouter.plan(for: settings(.quickPreview, autoSave: false))
            == PostCapturePlan(immediate: [], showsQuickPreview: true, afterPreview: []))
    }

    @Test func clipboard() {
        #expect(PostCaptureRouter.plan(for: settings(.clipboardOnly, autoSave: false))
            == PostCapturePlan(immediate: [.copyToClipboard], showsQuickPreview: false, afterPreview: []))
        #expect(PostCaptureRouter.plan(for: settings(.clipboardOnly, autoSave: true))
            == PostCapturePlan(immediate: [.copyToClipboard, .autoSave], showsQuickPreview: false, afterPreview: []))
    }
}
