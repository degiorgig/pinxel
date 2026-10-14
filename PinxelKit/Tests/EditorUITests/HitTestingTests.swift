import CoreGraphics
import DocumentModel
import PinxelTestSupport
import Testing
@testable import EditorUI

struct HitTestingTests {
    private func rect(_ frame: CGRect, fill: RGBA? = nil, rotation: Double = 0, locked: Bool = false, id: Int) -> Annotation {
        Annotation(
            id: TestDocuments.id(id),
            kind: .shape(ShapeData(rect: frame, shape: .rectangle)),
            style: Style(stroke: .accentRed, fill: fill, lineWidth: 4),
            rotation: rotation,
            isLocked: locked
        )
    }

    private func line(from start: CGPoint, to end: CGPoint, id: Int) -> Annotation {
        Annotation(id: TestDocuments.id(id), kind: .line(LineData(line: LineGeometry(start: start, end: end))), style: Style(lineWidth: 4))
    }

    @Test func topmostAnnotationWins() {
        let below = rect(CGRect(x: 0, y: 0, width: 100, height: 100), fill: .white, id: 1)
        let above = rect(CGRect(x: 50, y: 50, width: 100, height: 100), fill: .white, id: 2)
        #expect(HitTesting.annotation(at: CGPoint(x: 75, y: 75), in: [below, above], tolerance: 4)?.id == above.id)
        #expect(HitTesting.annotation(at: CGPoint(x: 25, y: 25), in: [below, above], tolerance: 4)?.id == below.id)
        #expect(HitTesting.annotation(at: CGPoint(x: 300, y: 300), in: [below, above], tolerance: 4) == nil)
    }

    @Test func unfilledShapeIsHitOnlyNearItsOutline() {
        let shape = rect(CGRect(x: 100, y: 100, width: 200, height: 100), id: 1)
        #expect(!HitTesting.contains(shape, point: CGPoint(x: 200, y: 150), tolerance: 4))
        #expect(HitTesting.contains(shape, point: CGPoint(x: 101, y: 150), tolerance: 4))
        #expect(HitTesting.contains(shape, point: CGPoint(x: 95, y: 150), tolerance: 4))
        #expect(!HitTesting.contains(shape, point: CGPoint(x: 90, y: 150), tolerance: 4))
    }

    @Test func filledShapeIsHitInside() {
        let shape = rect(CGRect(x: 100, y: 100, width: 200, height: 100), fill: .white, id: 1)
        #expect(HitTesting.contains(shape, point: CGPoint(x: 200, y: 150), tolerance: 4))
    }

    @Test func filledEllipseIgnoresItsCorners() {
        let ellipse = Annotation(
            id: TestDocuments.id(1),
            kind: .shape(ShapeData(rect: CGRect(x: 0, y: 0, width: 100, height: 100), shape: .ellipse)),
            style: Style(fill: .white)
        )
        #expect(HitTesting.contains(ellipse, point: CGPoint(x: 50, y: 50), tolerance: 2))
        #expect(!HitTesting.contains(ellipse, point: CGPoint(x: 3, y: 3), tolerance: 2))
    }

    @Test func lineIsHitWithinTolerance() {
        let annotation = line(from: .zero, to: CGPoint(x: 100, y: 0), id: 1)
        #expect(HitTesting.contains(annotation, point: CGPoint(x: 50, y: 5), tolerance: 4))
        #expect(!HitTesting.contains(annotation, point: CGPoint(x: 50, y: 8), tolerance: 4))
        #expect(!HitTesting.contains(annotation, point: CGPoint(x: 120, y: 0), tolerance: 4))
    }

    @Test func rotatedShapeUsesRotatedArea() {
        let shape = rect(CGRect(x: 0, y: 0, width: 200, height: 20), fill: .white, rotation: .pi / 2, id: 1)
        #expect(HitTesting.contains(shape, point: CGPoint(x: 100, y: 80), tolerance: 0))
        #expect(!HitTesting.contains(shape, point: CGPoint(x: 180, y: 10), tolerance: 0))
    }

    @Test func marqueeSelectsIntersectingAnnotations() {
        let a = rect(CGRect(x: 0, y: 0, width: 50, height: 50), id: 1)
        let b = rect(CGRect(x: 200, y: 200, width: 50, height: 50), id: 2)
        #expect(HitTesting.ids(intersecting: CGRect(x: 40, y: 40, width: 20, height: 20), in: [a, b]) == [a.id])
        #expect(HitTesting.ids(intersecting: CGRect(x: 60, y: 60, width: -100, height: -100), in: [a, b]) == [a.id])
    }

    @Test func boxHandlesAndRotationHandle() {
        let shape = rect(CGRect(x: 100, y: 100, width: 200, height: 100), id: 1)
        let handles = HitTesting.handles(for: shape, rotationOffset: 30)
        #expect(handles.count == 9)
        #expect(handles.first { $0.handle == .topLeft }?.point == CGPoint(x: 100, y: 100))
        #expect(handles.first { $0.handle == .right }?.point == CGPoint(x: 300, y: 150))
        #expect(handles.first { $0.handle == .rotation }?.point == CGPoint(x: 200, y: 70))
    }

    @Test func lineHasEndpointHandlesOnly() {
        let handles = HitTesting.handles(for: line(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 40), id: 1), rotationOffset: 30)
        #expect(handles.map(\.handle) == [.lineStart, .lineEnd])
        #expect(handles.last?.point == CGPoint(x: 90, y: 40))
    }

    @Test func stepHasCornerHandlesOnly() {
        let step = Annotation(id: TestDocuments.id(1), kind: .step(StepData(center: CGPoint(x: 50, y: 50), diameter: 20)))
        #expect(HitTesting.handles(for: step, rotationOffset: 30).map(\.handle) == [.topLeft, .topRight, .bottomRight, .bottomLeft])
    }

    @Test func lockedAnnotationHasNoHandles() {
        #expect(HitTesting.handles(for: rect(CGRect(x: 0, y: 0, width: 10, height: 10), locked: true, id: 1), rotationOffset: 30).isEmpty)
    }

    @Test func handleAtPointFindsTheHandleWithinTolerance() {
        let shape = rect(CGRect(x: 100, y: 100, width: 200, height: 100), id: 1)
        #expect(HitTesting.handle(at: CGPoint(x: 302, y: 198), for: shape, tolerance: 4, rotationOffset: 30) == .bottomRight)
        #expect(HitTesting.handle(at: CGPoint(x: 200, y: 72), for: shape, tolerance: 4, rotationOffset: 30) == .rotation)
        #expect(HitTesting.handle(at: CGPoint(x: 200, y: 150), for: shape, tolerance: 4, rotationOffset: 30) == nil)
    }

    @Test func handlesFollowRotation() {
        let shape = rect(CGRect(x: 0, y: 0, width: 200, height: 20), rotation: .pi / 2, id: 1)
        let topLeft = HitTesting.handles(for: shape, rotationOffset: 30).first { $0.handle == .topLeft }!.point
        #expect(abs(topLeft.x - 110) < 1e-9 && abs(topLeft.y - -90) < 1e-9)
    }

    @Test func unknownKindIsNeverHit() {
        let unknown = Annotation(id: TestDocuments.id(1), kind: .unknown(type: "future", raw: .null))
        #expect(!HitTesting.contains(unknown, point: .zero, tolerance: 100))
        #expect(HitTesting.handles(for: unknown, rotationOffset: 30).isEmpty)
    }
}
