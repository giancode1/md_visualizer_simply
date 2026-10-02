import AppKit

/// ⌘P: abrir rápido por nombre entre los archivos de la carpeta de trabajo, los recientes y los ya abiertos.
final class QuickOpen: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = QuickOpen()

    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 360), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: true)
    private let field = NSSearchField()
    private let table = NSTableView()
    /// `relLower` y `nameLower` se calculan al añadir el archivo, no en cada tecla ni en cada comparación del orden.
    private struct Entry { let url: URL; let rel: String; let relLower: String; let nameLower: String }
    private var all: [Entry] = []
    private var shown: [Entry] = []

    private override init() {
        super.init()
        panel.title = "Abrir rápido"
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        field.placeholderString = "Nombre del archivo…"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")))
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let content = panel.contentView!
        content.addSubview(field)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    func show() {
        all = []
        merge(NSDocumentController.shared.documents.compactMap(\.fileURL) + NSDocumentController.shared.recentDocumentURLs)
        field.stringValue = ""
        filter()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        DispatchQueue.global().async { // el recorrido de la carpeta puede tardar: se completa la lista cuando termina
            let scanned = Workspace.shared.scan()
            DispatchQueue.main.async { self.merge(scanned); self.filter() }
        }
    }

    private func merge(_ urls: [URL]) {
        var seen = Set(all.map(\.url.path))
        for u in urls where seen.insert(u.path).inserted {
            let rel = relative(u)
            all.append(Entry(url: u, rel: rel, relLower: rel.lowercased(), nameLower: u.lastPathComponent.lowercased()))
        }
    }

    private func relative(_ u: URL) -> String {
        if let f = Workspace.shared.folder?.path, u.path.hasPrefix(f + "/") { return String(u.path.dropFirst(f.count + 1)) }
        return (u.path as NSString).abbreviatingWithTildeInPath
    }

    private func filter() {
        let words = field.stringValue.lowercased().split(separator: " ").map(String.init)
        let first = words.first
        shown = Array(all.filter { e in words.allSatisfy { e.relLower.contains($0) } }
            .sorted { a, b in
                let ha = first.map { a.nameLower.hasPrefix($0) } ?? false, hb = first.map { b.nameLower.hasPrefix($0) } ?? false
                return ha != hb ? ha : (a.rel.count, a.nameLower) < (b.rel.count, b.nameLower)
            }.prefix(200))
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    @objc private func openSelected() {
        let row = max(0, table.selectedRow)
        guard shown.indices.contains(row) else { return }
        panel.close()
        Workspace.shared.openFile(shown[row].url)
    }

    func controlTextDidChange(_ obj: Notification) { filter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            let next = max(0, min(shown.count - 1, table.selectedRow + (sel == #selector(NSResponder.moveDown(_:)) ? 1 : -1)))
            table.selectRowIndexes([next], byExtendingSelection: false)
            table.scrollRowToVisible(next)
        case #selector(NSResponder.insertNewline(_:)): openSelected()
        case #selector(NSResponder.cancelOperation(_:)): panel.close()
        default: return false
        }
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let e = shown[row]
        let text = NSMutableAttributedString(string: e.url.lastPathComponent, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        let dir = (e.rel as NSString).deletingLastPathComponent
        if !dir.isEmpty { text.append(NSAttributedString(string: "   \(dir)", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])) }
        let label = NSTextField(labelWithAttributedString: text)
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
}
