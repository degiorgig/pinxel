import DocumentModel

extension PinxelDocument {
    /// Gli oggetti del documento di prova senza la cattura in fondo.
    public var userAnnotations: [Annotation] { annotations.filter { $0.id != TestDocuments.captureID } }

    /// Lo stesso documento senza la cattura: per i test degli strumenti sugli oggetti.
    public var withoutCapture: PinxelDocument {
        var copy = self
        copy.annotations = userAnnotations
        return copy
    }
}
