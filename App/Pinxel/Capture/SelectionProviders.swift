import CaptureKit

@MainActor
protocol SelectionProvider {
    func select(mode: CaptureMode, snapshot: CaptureSnapshot) async -> SelectionResult
}

@MainActor
struct OverlaySelectionProvider: SelectionProvider {
    func select(mode: CaptureMode, snapshot: CaptureSnapshot) async -> SelectionResult {
        await OverlayController(snapshot: snapshot, mode: mode).run()
    }
}

/// Per gli UI test: nessun overlay, risultato prestabilito.
@MainActor
struct FixedSelectionProvider: SelectionProvider {
    let result: SelectionResult

    func select(mode: CaptureMode, snapshot: CaptureSnapshot) async -> SelectionResult {
        result
    }
}
