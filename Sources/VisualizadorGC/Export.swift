import AppKit
import UniformTypeIdentifiers

extension DocWindowController {
    @objc func exportPDF(_ sender: Any?) {
        save(as: .pdf) { url in
            let info = NSPrintInfo()
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            info.paperSize = NSSize(width: 595, height: 842) // A4
            info.leftMargin = 48; info.rightMargin = 48; info.topMargin = 48; info.bottomMargin = 48
            let view = Self.printableView(self.doc.text, width: 595 - 96)
            let op = NSPrintOperation(view: view, printInfo: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            op.run()
        }
    }

    @objc func exportHTML(_ sender: Any?) {
        save(as: .html) { url in
            let text = Markdown.render(self.doc.text).text
            var data: Data?
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { // colores de modo claro, aunque la app esté en oscuro
                data = try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue])
            }
            guard let data else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url)
        }
    }

    private static func printableView(_ source: String, width: CGFloat) -> NSTextView {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        _ = tv.layoutManager // TextKit 1: tablas y cajas de código
        tv.appearance = NSAppearance(named: .aqua)
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.textStorage?.setAttributedString(Markdown.render(source).text)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        tv.sizeToFit()
        return tv
    }

    private func save(as type: UTType, _ write: @escaping (URL) throws -> Void) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = (doc.displayName as NSString).deletingPathExtension + "." + (type.preferredFilenameExtension ?? "")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do { try write(url) } catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }
}
