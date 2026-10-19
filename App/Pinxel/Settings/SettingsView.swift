import AppCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        Form {
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
                // Il predefinito si mostra nella lingua dell'app; tornarci (o non toccarlo) lo lascia seguire la lingua.
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
            environment.update { $0.saveFolderPath = url.path }
        }
    }
}

/// Registra una combinazione: richiede almeno un modificatore; Esc annulla.
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

/// Pinxel è un'app agente e non sempre viene attivata: porta davanti la finestra che contiene questa vista.
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
