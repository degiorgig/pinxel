import AppCore
import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var environment: AppEnvironment

    var body: some View {
        Form {
            Section("Dopo la cattura") {
                Picker("Azione", selection: binding(\.postCaptureAction)) {
                    ForEach(PostCaptureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Includi l'ombra nelle catture di finestre", isOn: binding(\.includeWindowShadow))
            }
            Section("Salvataggio automatico") {
                Toggle("Salva automaticamente ogni cattura", isOn: binding(\.autoSave))
                LabeledContent("Cartella") {
                    HStack {
                        Text(environment.settings.saveFolderURL.path).lineLimit(1).truncationMode(.middle)
                        Button("Scegli…", action: chooseFolder)
                    }
                }
                Picker("Formato", selection: binding(\.saveFormat)) {
                    Text("Documento Pinxel (.pinxel)").tag(SaveFormat.pinxel)
                    Text("Immagine PNG").tag(SaveFormat.png)
                }
                TextField("Nome file", text: binding(\.fileNameTemplate))
                Text("Esempio: \(FileNamer.baseName(template: environment.settings.fileNameTemplate, date: Date()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Scorciatoie globali") {
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        VStack(alignment: .trailing) {
                            ShortcutRecorder(combo: Binding(
                                get: { environment.settings.combo(for: action) },
                                set: { combo in environment.update { $0.hotKeys[action] = combo } }
                            ))
                            if environment.hotKeyConflicts.contains(action) {
                                Text("Combinazione già in uso da un'altra app").font(.caption).foregroundStyle(.red)
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
        Button(recording ? "Premi la combinazione…" : combo.displayString) {
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
