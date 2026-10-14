import Foundation
import Testing
@testable import DocumentModel

struct StepNumberingTests {
    func step(_ sequence: StepSequence = .numbers, override: String? = nil) -> Annotation {
        Annotation(kind: .step(StepData(center: .zero, diameter: 30, label: StepLabel(sequence: sequence, override: override))))
    }

    @Test func numbersFollowOrder() {
        let steps = [step(), step(), step()]
        let labels = StepNumbering.labels(for: steps)
        #expect(steps.map { labels[$0.id] } == ["1", "2", "3"])
    }

    @Test func deletingRenumbers() {
        var steps = [step(), step(), step()]
        steps.remove(at: 1)
        let labels = StepNumbering.labels(for: steps)
        #expect(steps.map { labels[$0.id] } == ["1", "2"])
    }

    @Test func sequencesAreIndependentAndIgnoreOtherKinds() {
        let arrow = Annotation(kind: .line(LineData(line: LineGeometry(start: .zero, end: .zero))))
        let items = [step(), step(.uppercaseLetters), arrow, step(), step(.lowercaseLetters), step(.uppercaseLetters)]
        let labels = StepNumbering.labels(for: items)
        #expect(items.map { labels[$0.id] } == ["1", "A", nil, "2", "a", "B"])
    }

    @Test func overrideReplacesLabelButKeepsPosition() {
        let items = [step(), step(override: "★"), step()]
        let labels = StepNumbering.labels(for: items)
        #expect(items.map { labels[$0.id] } == ["1", "★", "3"])
    }

    @Test func lettersContinuePastZ() {
        #expect(StepNumbering.format(26, .uppercaseLetters) == "Z")
        #expect(StepNumbering.format(27, .uppercaseLetters) == "AA")
        #expect(StepNumbering.format(28, .lowercaseLetters) == "ab")
        #expect(StepNumbering.format(702, .uppercaseLetters) == "ZZ")
        #expect(StepNumbering.format(703, .uppercaseLetters) == "AAA")
    }
}
