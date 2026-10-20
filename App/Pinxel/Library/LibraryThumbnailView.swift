import AppKit
import Library
import SwiftUI

/// A thumbnail: the image is read when it scrolls into view; accent border if it is the open one, outline if selected.
struct LibraryThumbnailView: View {
    let item: Library.LibraryItem
    let url: URL
    let revision: Date
    let isCurrent: Bool
    let isSelected: Bool
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: 112, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isCurrent ? Color.accentColor : isSelected ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                              lineWidth: isCurrent || isSelected ? 2.5 : 0.5)
        }
        .help([item.appName, item.windowTitle].compactMap { $0 }.joined(separator: " — "))
        .accessibilityElement()
        .accessibilityLabel(item.file)
        .accessibilityIdentifier("pinxel.library.item")
        .task(id: revision) {
            image = await ThumbnailCache.shared.load(url, revision: revision)
            failed = image == nil
        }
    }
}
