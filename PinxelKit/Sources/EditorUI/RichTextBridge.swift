import AppKit
import DocumentModel

/// Conversion between the model's `RichText` and `NSAttributedString` for the `NSTextView` used to edit on the canvas.
/// Sizes are in document pixels, as in `Rendering`.
public enum RichTextBridge {
    public static func font(family: String, size: Double, bold: Bool, italic: Bool) -> NSFont {
        let base = NSFont(name: family, size: size) ?? .systemFont(ofSize: size)
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        guard traits != base.fontDescriptor.symbolicTraits else { return base }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
    }

    /// Attributes of a run; with no runs, those of the text typed in an empty field.
    public static func attributes(_ text: RichText, run: TextRun? = nil) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(family: text.fontFamily, size: text.fontSize, bold: run?.bold ?? false, italic: run?.italic ?? false),
            .foregroundColor: (run?.color ?? text.color).nsColor,
            .paragraphStyle: paragraphStyle(text.alignment),
        ]
        if run?.underline == true { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    public static func attributedString(_ text: RichText) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in text.runs where !run.text.isEmpty {
            result.append(NSAttributedString(string: run.text, attributes: attributes(text, run: run)))
        }
        return result
    }

    /// `template` gives family, size, color and alignment; bold, italic, underline and color
    /// of the runs come from the attributes. Adjacent equal runs are merged.
    public static func richText(from string: NSAttributedString, template: RichText) -> RichText {
        var runs: [TextRun] = []
        let content = string.string as NSString
        string.enumerateAttributes(in: NSRange(location: 0, length: string.length)) { attributes, range, _ in
            let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let underline = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
            var color = (attributes[.foregroundColor] as? NSColor).map(RGBA.init(nsColor:))
            if let value = color, value.isClose(to: template.color) { color = nil }
            let run = TextRun(text: content.substring(with: range), bold: traits.contains(.bold), italic: traits.contains(.italic),
                              underline: underline, color: color)
            if let last = runs.last, last.bold == run.bold, last.italic == run.italic,
               last.underline == run.underline, last.color == run.color {
                runs[runs.count - 1].text += run.text
            } else {
                runs.append(run)
            }
        }
        var result = template
        result.runs = runs
        return result
    }

    static func paragraphStyle(_ alignment: RichTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch alignment {
        case .left: style.alignment = .left
        case .center: style.alignment = .center
        case .right: style.alignment = .right
        }
        return style
    }
}

extension RGBA {
    /// Equal within half a step of an 8-bit channel (color conversions round).
    func isClose(to other: RGBA) -> Bool {
        let tolerance = 0.5 / 255
        return abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance
            && abs(blue - other.blue) <= tolerance && abs(alpha - other.alpha) <= tolerance
    }
}
