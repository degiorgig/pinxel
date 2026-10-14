public enum PostCaptureStep: Equatable, Sendable {
    case openEditor
    case copyToClipboard
    case autoSave
}

public struct PostCapturePlan: Equatable, Sendable {
    public var immediate: [PostCaptureStep]
    public var showsQuickPreview: Bool
    /// Passi eseguiti quando l'anteprima veloce scade senza essere aperta.
    public var afterPreview: [PostCaptureStep]

    public init(immediate: [PostCaptureStep], showsQuickPreview: Bool, afterPreview: [PostCaptureStep]) {
        self.immediate = immediate
        self.showsQuickPreview = showsQuickPreview
        self.afterPreview = afterPreview
    }
}

public enum PostCaptureRouter {
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
