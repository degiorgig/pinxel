import Carbon.HIToolbox
import AppCore

/// Global shortcuts with `RegisterEventHotKey` (does not require the Accessibility permission).
@MainActor
final class HotKeyCenter {
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x5058_4C21 // 'PXL!'

    /// `false` if the combination is already used by another app or has no modifiers.
    func register(_ combo: KeyCombo, id: UInt32, action: @escaping @MainActor () -> Void) -> Bool {
        guard combo.hasModifier else { unregister(id: id); return false }
        return register(keyCode: combo.keyCode, modifiers: combo.modifiers, id: id, action: action)
    }

    /// A key with no modifiers too (Esc and Return during the scrolling capture): only while it is needed, since
    /// it takes the key away from every other app.
    func register(keyCode: UInt32, modifiers: UInt32 = 0, id: UInt32, action: @escaping @MainActor () -> Void) -> Bool {
        unregister(id: id)
        installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        references[id] = reference
        actions[id] = action
        return true
    }

    func unregister(id: UInt32) {
        if let reference = references.removeValue(forKey: id) { UnregisterEventHotKey(reference) }
        actions[id] = nil
    }

    func unregisterAll() {
        for id in Array(references.keys) { unregister(id: id) }
    }

    /// `false` if the shortcut belongs to another `HotKeyCenter`: its handler gets the event then.
    fileprivate func fire(_ id: UInt32) -> Bool {
        guard let action = actions[id] else { return false }
        action()
        return true
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            // Carbon events arrive on the main thread.
            let handled = MainActor.assumeIsolated { center.fire(id) }
            return handled ? noErr : OSStatus(eventNotHandledErr)
        }, 1, &spec, userData, nil)
    }
}
