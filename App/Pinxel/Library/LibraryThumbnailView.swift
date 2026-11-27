import AppKit
import Library
import SwiftUI

/// A thumbnail: the image is read when it scrolls into view; accent border if it is the open one, outline if selected.
/// Under the pointer it shows an X in its top right corner that moves it to the Trash.
struct LibraryThumbnailView: View {
    let item: Library.LibraryItem
    let url: URL
    let revision: Date
    let isCurrent: Bool
    let isSelected: Bool
    let size: CGSize
    let onTap: () -> Void
    let dragProvider: () -> NSItemProvider
    let onDelete: () -> Void
    @State private var image: NSImage?
    @State private var failed = false
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnail
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .onDrag(dragProvider)
            deleteButton
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .accessibilityHidden(!hovering)
        }
        // A fitted image can leave empty space between its pixels and the delete button.
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task(id: revision) {
            image = await ThumbnailCache.shared.load(url, revision: revision)
            failed = image == nil
        }
    }

    private var thumbnail: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: size.width, height: size.height)
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
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.65))
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(2)
        .help(String(localized: "Delete"))
        .accessibilityLabel(String(localized: "Delete"))
        .accessibilityIdentifier("pinxel.library.item.delete")
    }
}
