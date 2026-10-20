import Foundation

/// Names of the commands shown in "Undo …"/"Redo …", translated. Every command in the code takes its name from here,
/// so a name is written (and translated) in one place only.
public enum CommandName {
    private static func text(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: key, bundle: .module, comment: comment)
    }

    public static var add: String { text("Add", "Undo: generic add") }
    public static var addText: String { text("Add Text", "Undo: new text annotation") }
    public static var addCallout: String { text("Add Callout", "Undo: new callout") }
    public static var delete: String { text("Delete", "Undo: delete objects") }
    public static var edit: String { text("Edit", "Undo: generic change") }
    public static var editText: String { text("Edit Text", "Undo: text edited on the canvas") }
    public static var deleteText: String { text("Delete Text", "Undo: text emptied and removed") }
    public static var arrange: String { text("Arrange", "Undo: generic reorder") }
    public static var bringToFront: String { text("Bring to Front", "Undo and menu") }
    public static var bringForward: String { text("Bring Forward", "Undo and menu") }
    public static var sendBackward: String { text("Send Backward", "Undo and menu") }
    public static var sendToBack: String { text("Send to Back", "Undo and menu") }
    public static var move: String { text("Move", "Undo: objects moved") }
    public static var resize: String { text("Resize", "Undo: object or image resized") }
    public static var rotate: String { text("Rotate", "Undo: object rotated") }
    public static var duplicate: String { text("Duplicate", "Undo and menu") }
    public static var lock: String { text("Lock", "Undo and menu") }
    public static var unlock: String { text("Unlock", "Undo and menu") }
    public static var cut: String { text("Cut", "Undo: objects cut to the clipboard") }
    public static var paste: String { text("Paste", "Undo: objects pasted") }
    public static var pasteImage: String { text("Paste Image", "Undo: image pasted") }
    public static var insertImage: String { text("Insert Image", "Undo: image dropped or inserted") }
    public static var crop: String { text("Crop", "Undo: crop") }
    public static var cutOut: String { text("Cut Out", "Undo: remove a band and close the gap") }
    public static var extendCanvas: String { text("Extend Canvas", "Version 1 files only") }
    public static var fitCanvas: String { text("Fit Canvas", "Undo: canvas fitted to the content") }
    public static var canvasStyle: String { text("Canvas Style", "Undo: border, shadow and padding") }
    public static var style: String { text("Style", "Undo: color, width, opacity…") }
    public static var quickStyle: String { text("Quick Style", "Undo: quick style applied") }
    public static var fill: String { text("Fill", "Undo: fill toggled") }
    public static var effect: String { text("Effect", "Undo: blur ↔ pixelate") }
    public static var arrowHeads: String { text("Arrowheads", "Undo: arrow heads changed") }
    public static var shape: String { text("Shape", "Undo: rectangle/ellipse") }
    public static var magnifierShape: String { text("Magnifier Shape", "Undo") }
    public static var connector: String { text("Connector", "Undo: magnifier connector line") }
    public static var magnification: String { text("Magnification", "Undo: magnifier zoom") }
    public static var intensity: String { text("Intensity", "Undo: blur radius / pixel size") }
    public static var sequence: String { text("Sequence", "Undo: step numbering style") }
    public static var font: String { text("Font", "Undo: text font family") }
    public static var textSize: String { text("Text Size", "Undo") }
    public static var textColor: String { text("Text Color", "Undo") }
    public static var alignment: String { text("Alignment", "Undo: text alignment") }
    public static var bold: String { text("Bold", "Undo") }
    public static var italic: String { text("Italic", "Undo") }
    public static var underline: String { text("Underline", "Undo") }
}
