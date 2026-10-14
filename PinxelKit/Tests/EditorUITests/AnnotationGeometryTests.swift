import CoreGraphics
import DocumentModel
import PinxelTestSupport
import Testing
@testable import EditorUI

struct AnnotationGeometryTests {
    private func shape(_ frame: CGRect, rotation: Double = 0) -> Annotation {
        Annotation(id: TestDocuments.id(1), kind: .shape(ShapeData(rect: frame, shape: .rectangle)), rotation: rotation)
    }

    private func rectOf(_ annotation: Annotation) -> CGRect? {
        if case .shape(let data) = annotation.kind { return data.rect }
        return nil
    }

    private func close(_ a: CGPoint, _ b: CGPoint, _ tolerance: Double = 1e-6) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    @Test func movedTranslatesEveryKindOfGeometry() {
        let delta = CGSize(width: 5, height: -3)
        #expect(rectOf(AnnotationGeometry.moved(shape(CGRect(x: 10, y: 10, width: 20, height: 20)), by: delta))
            == CGRect(x: 15, y: 7, width: 20, height: 20))
        let line = Annotation(id: TestDocuments.id(2), kind: .line(LineData(line: LineGeometry(start: .zero, end: CGPoint(x: 10, y: 0)))))
        guard case .line(let moved) = AnnotationGeometry.moved(line, by: delta).kind else { Issue.record("not a line"); return }
        #expect(moved.line.start == CGPoint(x: 5, y: -3) && moved.line.end == CGPoint(x: 15, y: -3))
        let step = Annotation(id: TestDocuments.id(3), kind: .step(StepData(center: CGPoint(x: 50, y: 50), diameter: 20)))
        guard case .step(let movedStep) = AnnotationGeometry.moved(step, by: delta).kind else { Issue.record("not a step"); return }
        #expect(movedStep.center == CGPoint(x: 55, y: 47) && movedStep.diameter == 20)
    }

    @Test func cornerResizeKeepsTheOppositeCorner() {
        let result = AnnotationGeometry.resized(shape(CGRect(x: 100, y: 100, width: 200, height: 100)), handle: .bottomRight, to: CGPoint(x: 400, y: 300), keepAspect: false)
        #expect(rectOf(result) == CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    @Test func edgeResizeChangesOneDimension() {
        let result = AnnotationGeometry.resized(shape(CGRect(x: 100, y: 100, width: 200, height: 100)), handle: .right, to: CGPoint(x: 350, y: 999), keepAspect: false)
        #expect(rectOf(result) == CGRect(x: 100, y: 100, width: 250, height: 100))
    }

    @Test func draggingPastTheAnchorFlips() {
        let result = AnnotationGeometry.resized(shape(CGRect(x: 100, y: 100, width: 200, height: 100)), handle: .bottomRight, to: CGPoint(x: 50, y: 50), keepAspect: false)
        #expect(rectOf(result) == CGRect(x: 50, y: 50, width: 50, height: 50))
    }

    @Test func resizeKeepsMinimumSize() {
        let result = AnnotationGeometry.resized(shape(CGRect(x: 100, y: 100, width: 200, height: 100)), handle: .right, to: CGPoint(x: 100, y: 150), keepAspect: false)
        #expect(rectOf(result) == CGRect(x: 100, y: 100, width: 1, height: 100))
    }

    @Test func keepAspectOnACorner() {
        let result = AnnotationGeometry.resized(shape(CGRect(x: 100, y: 100, width: 200, height: 100)), handle: .bottomRight, to: CGPoint(x: 500, y: 210), keepAspect: true)
        #expect(rectOf(result) == CGRect(x: 100, y: 100, width: 400, height: 200))
    }

    @Test func penPathScalesWithItsBox() {
        let pen = Annotation(id: TestDocuments.id(1), kind: .pen(PenData(path: PathGeometry(points: [.zero, CGPoint(x: 10, y: 10)]))))
        guard case .pen(let data) = AnnotationGeometry.resized(pen, handle: .bottomRight, to: CGPoint(x: 20, y: 20), keepAspect: false).kind else {
            Issue.record("not a pen"); return
        }
        #expect(data.path.points == [.zero, CGPoint(x: 20, y: 20)])
    }

    @Test func stepResizeKeepsACircle() {
        let step = Annotation(id: TestDocuments.id(1), kind: .step(StepData(center: CGPoint(x: 50, y: 50), diameter: 20)))
        guard case .step(let data) = AnnotationGeometry.resized(step, handle: .bottomRight, to: CGPoint(x: 80, y: 70), keepAspect: false).kind else {
            Issue.record("not a step"); return
        }
        #expect(data.center == CGPoint(x: 60, y: 60))
        #expect(data.diameter == 40)
    }

    @Test func rotatedResizeKeepsOppositeCornerOnScreen() {
        let original = shape(CGRect(x: 0, y: 0, width: 100, height: 50), rotation: .pi / 2)
        let anchorBefore = HitTesting.handles(for: original, rotationOffset: 30).first { $0.handle == .topLeft }!.point
        let result = AnnotationGeometry.resized(original, handle: .bottomRight, to: CGPoint(x: 0, y: 150), keepAspect: false)
        let anchorAfter = HitTesting.handles(for: result, rotationOffset: 30).first { $0.handle == .topLeft }!.point
        #expect(close(anchorBefore, anchorAfter))
        #expect(abs(result.bounds.width - 175) < 1e-6)
        #expect(abs(result.bounds.height - 75) < 1e-6)
    }

    @Test func lineEndpointsMoveAndConstrain() {
        let line = Annotation(id: TestDocuments.id(1), kind: .arrow(ArrowData(line: LineGeometry(start: .zero, end: CGPoint(x: 10, y: 0)))))
        guard case .arrow(let free) = AnnotationGeometry.resized(line, handle: .lineEnd, to: CGPoint(x: 30, y: 40), keepAspect: false).kind else {
            Issue.record("not an arrow"); return
        }
        #expect(free.line.end == CGPoint(x: 30, y: 40) && free.line.start == .zero)
        guard case .arrow(let snapped) = AnnotationGeometry.resized(line, handle: .lineStart, to: CGPoint(x: 100, y: 3), keepAspect: true).kind else {
            Issue.record("not an arrow"); return
        }
        #expect(abs(snapped.line.start.y) < 1e-9)
    }

    @Test func constrained45SnapsToTheNearestEighthOfATurn() {
        let flat = AnnotationGeometry.constrained45(from: .zero, to: CGPoint(x: 100, y: 10))
        #expect(abs(flat.y) < 1e-9 && abs(flat.x - 100.498756) < 1e-5)
        let diagonal = AnnotationGeometry.constrained45(from: .zero, to: CGPoint(x: 100, y: 90))
        #expect(abs(diagonal.x - diagonal.y) < 1e-9)
        #expect(AnnotationGeometry.constrained45(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5)) == CGPoint(x: 5, y: 5))
    }

    @Test func squaredUsesTheLargerSideAndKeepsDirection() {
        #expect(AnnotationGeometry.squared(from: .zero, to: CGPoint(x: 50, y: 20)) == CGPoint(x: 50, y: 50))
        #expect(AnnotationGeometry.squared(from: .zero, to: CGPoint(x: -10, y: 30)) == CGPoint(x: -30, y: 30))
    }

    @Test func rotationFollowsThePointerAndSnaps() {
        let box = shape(CGRect(x: 100, y: 100, width: 100, height: 100))
        #expect(abs(AnnotationGeometry.rotated(box, pointer: CGPoint(x: 250, y: 150), snap: false).rotation - .pi / 2) < 1e-9)
        #expect(abs(AnnotationGeometry.rotated(box, pointer: CGPoint(x: 150, y: 50), snap: false).rotation) < 1e-9)
        #expect(abs(AnnotationGeometry.rotated(box, pointer: CGPoint(x: 50, y: 150), snap: false).rotation + .pi / 2) < 1e-9)
        #expect(abs(AnnotationGeometry.rotated(box, pointer: CGPoint(x: 250, y: 160), snap: true).rotation - .pi / 2) < 1e-9)
    }
}
