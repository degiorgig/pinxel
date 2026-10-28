import AppCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Pinxel at login", isOn: Binding(
                    get: { environment.loginItem.isEnabled },
                    set: { environment.loginItem.setEnabled($0) }
                ))
                if environment.loginItem.needsApproval {
                    LabeledContent {
                        Button("Open System Settings…", action: SystemLoginItemService.openSystemSettings)
                    } label: {
                        Text("Allow Pinxel in Login Items to open it at login.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = environment.loginItem.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("After Capture") {
                Picker("Action", selection: binding(\.postCaptureAction)) {
                    ForEach(PostCaptureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Include the shadow in window captures", isOn: binding(\.includeWindowShadow))
            }
            Section("Automatic Saving") {
                Toggle("Save every capture automatically", isOn: binding(\.autoSave))
                LabeledContent("Folder") {
                    HStack {
                        Text(environment.settings.saveFolderURL.path).lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                Picker("Format", selection: binding(\.saveFormat)) {
                    Text("Pinxel Document (.pinxel)").tag(SaveFormat.pinxel)
                    Text("PNG Image").tag(SaveFormat.png)
                }
                // The default is shown in the app's language; going back to it (or not touching it) lets it follow the language.
                TextField("File Name", text: Binding(
                    get: { environment.settings.effectiveFileNameTemplate },
                    set: { value in
                        environment.update {
                            $0.fileNameTemplate = value == FileNamer.defaultTemplate ? FileNamer.legacyDefaultTemplate : value
                        }
                    }
                ))
                Text("Example: \(FileNamer.baseName(template: environment.settings.effectiveFileNameTemplate, date: Date()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Global Shortcuts") {
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        VStack(alignment: .trailing) {
                            ShortcutRecorder(combo: Binding(
                                get: { environment.settings.combo(for: action) },
                                set: { combo in environment.update { $0.hotKeys[action] = combo } }
                            ))
                            if environment.hotKeyConflicts.contains(action) {
                                Text("This shortcut is already used by another app").font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .background(FrontWindowRaiser())
        .padding()
        // The user can also change it in System Settings ▸ General ▸ Login Items.
        .onAppear { environment.loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            environment.loginItem.refresh()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CaptureSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings[keyPath: keyPath] },
            set: { value in environment.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = environment.settings.saveFolderURL
        if panel.runModal() == .OK, let url = panel.url {
            environment.update { $0.chooseSaveFolder(url) }
        }
    }
}

/// Records a combination: requires at least one modifier; Esc cancels.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? String(localized: "Press the shortcut…") : combo.displayString) {
            recording ? stop() : start()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            let candidate = KeyCombo(keyCode: UInt32(event.keyCode),
                                     modifiers: KeyCombo.carbonModifiers(fromCocoa: event.modifierFlags.rawValue))
            if candidate.hasModifier {
                combo = candidate
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Pinxel is an agent app and is not always activated: brings forward the window that contains this view.
private struct FrontWindowRaiser: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { RaisingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class RaisingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async {
                window.orderFrontRegardless()
                window.makeKey()
            }
        }
    }
}
