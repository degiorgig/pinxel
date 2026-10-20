import CaptureKit
import SwiftUI

/// Floating scrolling-capture panel: growing thumbnail, height, Done and Cancel.
struct ScrollCapturePanel: View {
    let session: ScrollCaptureSession
    let narrowed: Bool

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text("Scrolling Capture")
                    .font(.headline)
                Text(verbatim: "\(session.height) px")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Text(message)
                    .font(session.pause != .none ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(session.pause != .none ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Cancel") { session.cancel() }
            Button("Done") { session.finish() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.smooth(duration: 0.25), value: session.height)
    }

    private var message: String {
        if session.pause == .scrollBack { return String(localized: "Too fast: scroll back up a little to resume.") }
        if session.pause == .similarRows { return String(localized: "Rows too similar to match: scroll back up a little and scroll more slowly.") }
        if narrowed { return String(localized: "Area narrowed to save memory. Scroll down or up, then Done.") }
        return String(localized: "Scroll down or up, then press Done or Return.")
    }

    @ViewBuilder private var thumbnail: some View {
        Group {
            if let preview = session.preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: 36, height: 48, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }
}
