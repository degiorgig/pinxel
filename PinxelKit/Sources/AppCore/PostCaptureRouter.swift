public enum PostCaptureStep: Equatable, Sendable {
    case openEditor
    case copyToClipboard
    case autoSave
}

public struct PostCapturePlan: Equatable, Sendable {
    public var immediate: [PostCaptureStep]
    public var showsQuickPreview: Bool
    /// Steps performed when the quick preview expires or is opened.
    public var afterPreview: [PostCaptureStep]
    /// Whether the capture is archived in the library first.
    public var addsToLibrary: Bool

    public init(immediate: [PostCaptureStep], showsQuickPreview: Bool, afterPreview: [PostCaptureStep], addsToLibrary: Bool = true) {
        self.immediate = immediate
        self.showsQuickPreview = showsQuickPreview
        self.afterPreview = afterPreview
        self.addsToLibrary = addsToLibrary
    }

    public func stepsAfterPreview(openEditor: Bool) -> [PostCaptureStep] {
        // The editor first: saving a large capture must not delay it.
        openEditor ? [.openEditor] + afterPreview : afterPreview
    }
}

public enum PostCaptureRouter {
    /// A scrolling capture that stopped on an error: only the editor, as an unsaved document, so the user sees what was
    /// captured before anything archives, saves or copies it as if it were complete.
    public static func planForIncompleteCapture() -> PostCapturePlan {
        PostCapturePlan(immediate: [.openEditor], showsQuickPreview: false, afterPreview: [], addsToLibrary: false)
    }

    public static func plan(for settings: CaptureSettings) -> PostCapturePlan {
        let save: [PostCaptureStep] = settings.autoSave ? [.autoSave] : []
        switch settings.postCaptureAction {
        case .openEditor:
            return PostCapturePlan(immediate: save + [.openEditor], showsQuickPreview: false, afterPreview: [])
        case .quickPreview:
            return PostCapturePlan(immediate: [], showsQuickPreview: true, afterPreview: save)
        case .clipboardOnly:
            return PostCapturePlan(immediate: [.copyToClipboard] + save, showsQuickPreview: false, afterPreview: [])
        }
    }
}
