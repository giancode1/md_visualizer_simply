import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    var text = ""
    weak var controller: DocWindowController?

    override var fileURL: URL? { didSet { controller?.refreshPath() } } // Guardar como… / renombrar

    override class var autosavesInPlace: Bool { true }

    private static let markdownExtensions: Set = ["md", "markdown"]
    var isMarkdown: Bool { Self.markdownExtensions.contains(fileURL?.pathExtension.lowercased() ?? "md") }

    override func makeWindowControllers() {
        let wc = DocWindowController(doc: self)
        controller = wc
        addWindowController(wc)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        controller?.apply() // recarga si el archivo cambió en disco
    }

    override func data(ofType typeName: String) throws -> Data { Data(text.utf8) }
}
