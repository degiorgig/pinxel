import CoreGraphics

/// Calcoli dell'area e del pannello della cattura a scorrimento. Coordinate globali in punti, origine in alto a sinistra.
public enum ScrollCaptureGeometry {
    public static let minimumHeight: CGFloat = 100
    /// Memoria massima per l'immagine più lunga possibile.
    public static let byteBudget = 1 << 30

    /// L'area limitata al suo schermo, ristretta ai pixel interi e, se serve, in larghezza per il budget di memoria.
    /// `nil` se resta più bassa di `minimumHeight`.
    public static func prepare(_ rect: CGRect, on display: DisplayInfo, maxHeight: Int) -> (rect: CGRect, narrowed: Bool)? {
        let visible = rect.standardized.intersection(display.frame)
        guard !visible.isNull else { return nil }
        let clipped = wholePixels(visible, on: display)
        guard clipped.height >= minimumHeight else { return nil }
        let maxWidth = (Double(byteBudget / (max(maxHeight, 1) * 4)) / display.scale).rounded(.down)
        guard clipped.width > maxWidth else { return (clipped, false) }
        return (CGRect(x: clipped.minX, y: clipped.minY, width: maxWidth, height: clipped.height), true)
    }

    /// Il rettangolo più grande fatto di pixel interi dello schermo dentro `rect`: con bordi a metà pixel l'ultima riga
    /// catturata prenderebbe un po' di ciò che sta appena fuori, come la cornice dell'area.
    static func wholePixels(_ rect: CGRect, on display: DisplayInfo) -> CGRect {
        let scale = display.scale, origin = display.frame.origin
        let minX = ((rect.minX - origin.x) * scale).rounded(.up), maxX = ((rect.maxX - origin.x) * scale).rounded(.down)
        let minY = ((rect.minY - origin.y) * scale).rounded(.up), maxY = ((rect.maxY - origin.y) * scale).rounded(.down)
        return CGRect(x: origin.x + minX / scale, y: origin.y + minY / scale,
                      width: max(0, maxX - minX) / scale, height: max(0, maxY - minY) / scale)
    }

    /// Pannello fuori dall'area: sotto, sopra, a destra, a sinistra; se non c'è posto, in basso a destra dentro lo schermo
    /// (la cattura esclude comunque le finestre di Pinxel).
    public static func panelFrame(size: CGSize, around rect: CGRect, in screen: CGRect, gap: CGFloat = 12) -> CGRect {
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, screen.minX), screen.maxX - size.width) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, screen.minY), screen.maxY - size.height) }
        let centeredX = clampX(rect.midX - size.width / 2)
        if rect.maxY + gap + size.height <= screen.maxY {
            return CGRect(origin: CGPoint(x: centeredX, y: rect.maxY + gap), size: size)
        }
        if rect.minY - gap - size.height >= screen.minY {
            return CGRect(origin: CGPoint(x: centeredX, y: rect.minY - gap - size.height), size: size)
        }
        if rect.maxX + gap + size.width <= screen.maxX {
            return CGRect(origin: CGPoint(x: rect.maxX + gap, y: clampY(rect.minY)), size: size)
        }
        if rect.minX - gap - size.width >= screen.minX {
            return CGRect(origin: CGPoint(x: rect.minX - gap - size.width, y: clampY(rect.minY)), size: size)
        }
        return CGRect(origin: CGPoint(x: screen.maxX - size.width - gap, y: screen.maxY - size.height - gap), size: size)
    }
}
