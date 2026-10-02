import AppKit

/// Panel lateral: índice de títulos del documento y árbol de archivos de la carpeta de trabajo.
final class SidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate {
    struct Heading: Equatable { let level: Int; let title: String; let offset: Int } // offset = posición de la línea en el fuente

    var onHeading: ((Heading) -> Void)?
    var headings: [Heading] = [] { didSet { if headings != oldValue { headingTable.reloadData() } } }

    private let segment = NSSegmentedControl(labels: ["Índice", "Archivos"], trackingMode: .selectOne, target: nil, action: nil)
    private let headingTable = NSTableView()
    private let fileOutline = NSOutlineView()
    private let headingScroll = NSScrollView()
    private let fileScroll = NSScrollView()
    private let emptyBox = NSStackView()
    private var root: FileNode?

    override init(frame: NSRect) {
        super.init(frame: frame)
        segment.target = self
        segment.action = #selector(tabChanged)
        segment.selectedSegment = Workspace.shared.sidebarFiles ? 1 : 0
        segment.translatesAutoresizingMaskIntoConstraints = false

        configure(headingTable, action: #selector(headingClicked))
        headingTable.dataSource = self
        headingTable.delegate = self
        configure(fileOutline, action: #selector(fileClicked))
        fileOutline.outlineTableColumn = fileOutline.tableColumns[0]
        fileOutline.dataSource = self // NSOutlineView tiene su propio dataSource/delegate: no sirve un bucle común
        fileOutline.delegate = self

        let title = NSTextField(labelWithString: "Sin carpeta abierta")
        title.textColor = .secondaryLabelColor
        let open = NSButton(title: "Abrir carpeta…", target: self, action: #selector(chooseFolder))
        emptyBox.orientation = .vertical
        emptyBox.spacing = 8
        emptyBox.addArrangedSubview(title)
        emptyBox.addArrangedSubview(open)
        emptyBox.translatesAutoresizingMaskIntoConstraints = false

        for (scroll, view) in [(headingScroll, headingTable as NSView), (fileScroll, fileOutline as NSView)] {
            scroll.documentView = view
            scroll.hasVerticalScroller = true
            scroll.drawsBackground = false
            scroll.translatesAutoresizingMaskIntoConstraints = false
        }
        [segment, headingScroll, fileScroll, emptyBox].forEach(addSubview)
        NSLayoutConstraint.activate([
            segment.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            segment.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            segment.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            headingScroll.topAnchor.constraint(equalTo: segment.bottomAnchor, constant: 8),
            fileScroll.topAnchor.constraint(equalTo: segment.bottomAnchor, constant: 8),
            emptyBox.topAnchor.constraint(equalTo: segment.bottomAnchor, constant: 24),
            emptyBox.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
        for scroll in [headingScroll, fileScroll] {
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
                scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reloadFiles), name: Workspace.changed, object: nil)
        reloadFiles()
        tabChanged()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func configure(_ table: NSTableView, action: Selector) {
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")))
        table.headerView = nil
        table.style = .sourceList
        table.target = self
        table.action = action
    }

    func showFiles() { segment.selectedSegment = 1; tabChanged() }

    @objc private func tabChanged() {
        let files = segment.selectedSegment == 1
        Workspace.shared.sidebarFiles = files
        headingScroll.isHidden = files
        fileScroll.isHidden = !files || root == nil
        emptyBox.isHidden = !files || root != nil
    }

    @objc private func reloadFiles() {
        root = Workspace.shared.folder.map { FileNode(url: $0, isDir: true) }
        fileOutline.reloadData()
        tabChanged()
    }

    @objc private func chooseFolder() { Workspace.shared.chooseFolder() }

    @objc private func headingClicked() {
        let row = headingTable.clickedRow
        if headings.indices.contains(row) { onHeading?(headings[row]) }
    }

    @objc private func fileClicked() {
        guard let node = fileOutline.item(atRow: fileOutline.clickedRow) as? FileNode else { return }
        if node.isDir {
            fileOutline.isItemExpanded(node) ? fileOutline.collapseItem(node) : fileOutline.expandItem(node)
        } else {
            Workspace.shared.openFile(node.url)
        }
    }

    /// Títulos `#`…`######` del texto, sin contar los de dentro de bloques de código.
    static func headings(in text: String) -> [Heading] {
        var out: [Heading] = []
        var inFence = false
        (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (text as NSString).length), options: .byLines) { line, range, _, _ in
            guard let line else { return }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); return }
            guard !inFence, line.utf8.first == 0x23, let m = line.range(of: "^#{1,6}\\s+", options: .regularExpression) else { return }
            let level = line[..<m.upperBound].filter { $0 == "#" }.count
            let title = line[m.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
            if !title.isEmpty { out.append(Heading(level: level, title: title, offset: range.location)) }
        }
        return out
    }

    // MARK: índice
    func numberOfRows(in tableView: NSTableView) -> Int { headings.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let h = headings[row]
        let label = NSTextField(labelWithString: String(repeating: "\u{2003}", count: h.level - 1) + h.title)
        label.font = .systemFont(ofSize: 12, weight: h.level == 1 ? .semibold : .regular)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    // MARK: archivos
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = (item as? FileNode) ?? root else { return 0 }
        return node.children.count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? FileNode) ?? root!).children[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as! FileNode).isDir }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! FileNode
        let label = NSTextField(labelWithString: node.url.lastPathComponent)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        let icon = NSImageView(image: NSImage(systemSymbolName: node.isDir ? "folder" : "doc.text", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        let cell = NSTableCellView()
        cell.addSubview(icon)
        cell.addSubview(label)
        cell.textField = label
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
