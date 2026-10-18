import CaptureKit
import SwiftUI

/// Pannello flottante della cattura a scorrimento: miniatura che cresce, altezza, Fine e Annulla.
struct ScrollCapturePanel: View {
    let session: ScrollCaptureSession
    let narrowed: Bool

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text("Cattura a scorrimento")
                    .font(.headline)
                Text("\(session.height) px")
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
            Button("Annulla") { session.cancel() }
            Button("Fine") { session.finish() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.smooth(duration: 0.25), value: session.height)
    }

    private var message: String {
        if session.pause == .scrollBack { return "Troppo veloce: torna un po' su per riprendere." }
        if session.pause == .similarRows { return "Righe troppo simili per agganciarsi: torna un po' su e scorri più piano." }
        if narrowed { return "Area ristretta in larghezza per non esaurire la memoria. Scorri verso il basso, poi Fine." }
        return "Scorri verso il basso, poi premi Fine o Invio."
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
