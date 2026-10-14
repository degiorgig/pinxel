import Carbon.HIToolbox
import AppCore

/// Scorciatoie globali con `RegisterEventHotKey` (non richiede il permesso Accessibilità).
@MainActor
final class HotKeyCenter {
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x5058_4C21 // 'PXL!'

    /// `false` se la combinazione è già usata da un'altra app o non ha modificatori.
    func register(_ combo: KeyCombo, id: UInt32, action: @escaping @MainActor () -> Void) -> Bool {
        unregister(id: id)
        guard combo.hasModifier else { return false }
        installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: id),
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

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
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
            // Gli eventi Carbon arrivano sul thread principale.
            MainActor.assumeIsolated { center.fire(id) }
            return noErr
        }, 1, &spec, userData, nil)
    }
}
