import DocumentModel

extension PinxelDocument {
    /// The test document's objects without the capture at the bottom.
    public var userAnnotations: [Annotation] { annotations.filter { $0.id != TestDocuments.captureID } }

    /// The same document without the capture: for the tools' tests on objects.
    public var withoutCapture: PinxelDocument {
        var copy = self
        copy.annotations = userAnnotations
        return copy
    }
}
