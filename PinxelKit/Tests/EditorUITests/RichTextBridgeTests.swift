import AppKit
import DocumentModel
import PinxelTestSupport
import Testing
@testable import EditorUI

struct RichTextBridgeTests {
    private let styled = RichText(
        runs: [
            TextRun(text: "Ciao ", bold: true),
            TextRun(text: "mondo"),
            TextRun(text: "!", italic: true, underline: true, color: .accentRed),
        ],
        fontFamily: "Helvetica", fontSize: 30, color: .black, alignment: .center
    )

    @Test func roundTripKeepsRunsAndTemplate() {
        let string = RichTextBridge.attributedString(styled)
        #expect(string.string == "Ciao mondo!")
        var template = styled
        template.runs = []
        #expect(RichTextBridge.richText(from: string, template: template) == styled)
    }

    @Test func attributesCarryFontSizeColorAndAlignment() throws {
        let string = RichTextBridge.attributedString(RichText("x", fontSize: 40, color: .accentRed, alignment: .right))
        let attributes = string.attributes(at: 0, effectiveRange: nil)
        let font = try #require(attributes[.font] as? NSFont)
        #expect(font.pointSize == 40)
        let paragraph = try #require(attributes[.paragraphStyle] as? NSParagraphStyle)
        #expect(paragraph.alignment == .right)
        let color = try #require(attributes[.foregroundColor] as? NSColor)
        #expect(RGBA(nsColor: color).isClose(to: .accentRed))
    }

    @Test func adjacentRunsWithTheSameStyleMerge() {
        let template = RichText(runs: [])
        let string = NSMutableAttributedString(string: "Ciao", attributes: RichTextBridge.attributes(template))
        string.append(NSAttributedString(string: " Pinxel", attributes: RichTextBridge.attributes(template)))
        #expect(RichTextBridge.richText(from: string, template: template).runs == [TextRun(text: "Ciao Pinxel")])
    }

    @Test func emptyStringGivesNoRuns() {
        let text = RichTextBridge.richText(from: NSAttributedString(), template: RichText("vecchio"))
        #expect(text.runs.isEmpty)
        #expect(text.plainText.isEmpty)
    }

    @Test func colorEqualToTheTemplateIsDropped() {
        let template = RichText(runs: [], color: .accentRed)
        let string = NSAttributedString(string: "a", attributes: RichTextBridge.attributes(template))
        #expect(RichTextBridge.richText(from: string, template: template).runs[0].color == nil)
    }

    @Test func wholeTextStylingTogglesEveryRun() {
        var text = styled
        #expect(!text.isBold)
        text.setBold(true)
        #expect(text.isBold && text.runs.allSatisfy(\.bold))
        text.setItalic(true)
        text.setUnderline(true)
        #expect(text.isItalic && text.isUnderlined)
        text.setColor(.white)
        #expect(text.color == .white && text.runs.allSatisfy { $0.color == nil })
        #expect(!RichText(runs: []).isBold)
    }

    @Test func textAccessorsReadAndWriteTextAndCallout() {
        var text = Annotation(id: TestDocuments.id(1), kind: .text(TextData(rect: CGRect(x: 10, y: 10, width: 100, height: 30), text: RichText("a"))))
        var callout = Annotation(id: TestDocuments.id(2), kind: .callout(CalloutData(
            rect: CGRect(x: 0, y: 0, width: 80, height: 40), text: RichText("b"), tail: CalloutTail(tip: CGPoint(x: 0, y: 90)))))
        var shape = Annotation(id: TestDocuments.id(3), kind: .shape(ShapeData(rect: .zero, shape: .rectangle)))
        #expect(text.richText?.plainText == "a" && callout.richText?.plainText == "b" && shape.richText == nil)
        #expect(text.textInset == 4 && callout.textInset == 10)
        text.richText = RichText("nuovo")
        callout.richText = RichText("altro")
        shape.richText = RichText("ignorato")
        #expect(text.richText?.plainText == "nuovo" && callout.richText?.plainText == "altro" && shape.richText == nil)
        #expect(callout.textRect == CGRect(x: 0, y: 0, width: 80, height: 40))
    }

    @Test func growTextHeightNeverShrinks() {
        var text = Annotation(kind: .text(TextData(rect: CGRect(x: 0, y: 0, width: 100, height: 30), text: RichText("a"))))
        text.growTextHeight(to: 20)
        #expect(text.textRect?.height == 30)
        text.growTextHeight(to: 55)
        #expect(text.textRect == CGRect(x: 0, y: 0, width: 100, height: 55))
    }
}
