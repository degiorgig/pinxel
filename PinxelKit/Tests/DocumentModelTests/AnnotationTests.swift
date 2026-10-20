import Foundation
import Testing
@testable import DocumentModel
import PinxelTestSupport

struct AnnotationTests {
    @Test func everyKindRoundTrips() throws {
        let annotations = TestDocuments.allKindsAnnotations()
        #expect(annotations.count == 14)
        for annotation in annotations {
            #expect(try roundTrip(annotation) == annotation, "kind \(annotation.kind.typeName)")
        }
    }

    @Test func jsonShapeUsesTypeAndData() throws {
        let annotation = TestDocuments.allKindsAnnotations()[0]
        let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(annotation))
        guard case .object(let object) = json else {
            Issue.record("annotation must encode as an object")
            return
        }
        #expect(object["type"] == .string("arrow"))
        #expect(object["data"] != nil)
        #expect(object["style"] != nil)
    }

    @Test func unknownKindIsPreserved() throws {
        let json = #"""
        {"id":"00000000-0000-0000-0000-000000000099","type":"sticker",
         "data":{"emoji":"🔥","size":3,"ratio":1.5,"flags":[true,null],"nested":{"a":"b"}},
         "rotation":0.5,"style":{"lineWidth":4,"dash":"solid","opacity":1},"isLocked":true}
        """#
        let decoded = try JSONDecoder().decode(Annotation.self, from: Data(json.utf8))
        guard case .unknown(let type, let raw) = decoded.kind else {
            Issue.record("expected unknown kind, got \(decoded.kind.typeName)")
            return
        }
        #expect(type == "sticker")
        #expect(decoded.rotation == 0.5)
        #expect(decoded.isLocked)

        let reencoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(decoded))
        let original = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        guard case .object(let a) = reencoded, case .object(let b) = original else {
            Issue.record("expected objects")
            return
        }
        #expect(a["data"] == b["data"])
        #expect(a["type"] == .string("sticker"))
        #expect(raw == b["data"])
    }

    @Test func jsonValueKeepsNumbersAndBoolsApart() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"n":1,"b":true,"z":0,"f":false}"#.utf8))
        #expect(value == .object(["n": .number(1), "b": .bool(true), "z": .number(0), "f": .bool(false)]))
        #expect(try roundTrip(value) == value)
    }

    @Test func unicodeTextRoundTrips() throws {
        for sample in ["", "👋🏽 Ciao — مرحبا — 日本語", "a\nb\tc \"quoted\" \\ /"] {
            let text = RichText(runs: [TextRun(text: sample, bold: true), TextRun(text: sample, italic: true, color: .accentRed)])
            let annotation = Annotation(kind: .text(TextData(rect: CGRect(x: 0, y: 0, width: 10, height: 10), text: text)))
            let decoded = try roundTrip(annotation)
            #expect(decoded == annotation)
            if case .text(let data) = decoded.kind {
                #expect(data.text.plainText == sample + sample)
            }
        }
    }

    @Test func boundsPerKind() {
        let byID = Dictionary(uniqueKeysWithValues: TestDocuments.allKindsAnnotations().map { ($0.id, $0) })
        #expect(byID[TestDocuments.id(1)]?.bounds == CGRect(x: 20, y: 20, width: 120, height: 60))
        #expect(byID[TestDocuments.id(3)]?.bounds == CGRect(x: 180, y: 20, width: 100, height: 60))
        #expect(byID[TestDocuments.id(7)]?.bounds == CGRect(x: 22, y: 212, width: 36, height: 36))
        #expect(byID[TestDocuments.id(13)]?.bounds == CGRect(x: 190, y: 90, width: 190, height: 70))
        // The callout includes the tail tip.
        #expect(byID[TestDocuments.id(6)]?.bounds == CGRect(x: 180, y: 110, width: 180, height: 110))
    }

    @Test func boundsNormalizeNegativeRects() {
        let annotation = Annotation(kind: .shape(ShapeData(rect: CGRect(x: 50, y: 50, width: -20, height: -10), shape: .rectangle)))
        #expect(annotation.bounds == CGRect(x: 30, y: 40, width: 20, height: 10))
    }
}
