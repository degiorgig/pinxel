import AppCore
import AppKit
import DocumentModel
import Persistence
import Rendering
import SwiftUI

@MainActor
@Observable
final class ExportOptions {
    var choice: ExportChoice

    init(choice: ExportChoice) {
        self.choice = choice
    }
}

private struct ExportOptionsView: View {
    @Bindable var options: ExportOptions
    let onFileTypeChange: @MainActor (ExportFileType) -> Void

    var body: some View {
        Form {
            Picker("Format", selection: $options.choice.fileType) {
                ForEach(ExportFileType.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if options.choice.fileType.hasQuality {
                LabeledContent("Quality") {
                    HStack {
                        Slider(value: $options.choice.quality, in: 0...100)
                        Text(verbatim: "\(Int(options.choice.quality))").monospacedDigit().frame(width: 32, alignment: .trailing)
                    }
                }
            }
            Picker("Scale", selection: $options.choice.scale) {
                Text(verbatim: "1x").tag(ExportScale.oneX)
                Text(verbatim: "2x").tag(ExportScale.twoX)
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onChange(of: options.choice.fileType) { _, newValue in onFileTypeChange(newValue) }
    }
}

/// Esporta… (spec §9): pannello di salvataggio con formato, qualità e scala; passa da `Exporter`.
@MainActor
enum ExportPanel {
    static func run(document: PinxelDocument, assets: any AssetProvider, suggestedName: String, window: NSWindow) async {
        let options = ExportOptions(choice: ExportChoice(documentScale: document.scale))
        let panel = NSSavePanel()
        panel.title = String(localized: "Export")
        panel.prompt = String(localized: "Export")
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [options.choice.fileType.contentType]
        panel.nameFieldStringValue = options.choice.fileName(from: suggestedName)
        panel.accessoryView = NSHostingView(rootView: ExportOptionsView(options: options) { fileType in
            panel.allowedContentTypes = [fileType.contentType]
            panel.nameFieldStringValue = options.choice.fileName(from: panel.nameFieldStringValue)
        })

        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
        do {
            let data = try Exporter.export(document, assets: assets, format: options.choice.format, scale: options.choice.scale)
            try data.write(to: url, options: .atomic)
        } catch {
            window.presentError(error)
        }
    }
}
