import AppKit

/// Soltar un archivo del Finder sobre el visor lo abre (en vez de pegar su ruta/adjunto).
private let fileDropOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

private func hasDroppedFile(_ info: NSDraggingInfo) -> Bool {
    info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: fileDropOptions)
}

/// Un archivo se abre como documento; una carpeta pasa a ser la carpeta de trabajo.
private func openDropped(_ info: NSDraggingInfo) -> Bool {
    guard let url = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: fileDropOptions)?.first as? URL else { return false }
    Workspace.shared.open(url)
    return true
}

final class DropTextView: NSTextView {
    var onTaskClick: ((Int) -> Void)? // posición de "[" de la tarea en el fuente
    var onLink: ((Any) -> Void)? // ⌘-clic en un enlace

    /// Índice del carácter bajo el mouse, solo si el clic cae sobre su glifo (no en el espacio vacío de la línea).
    private func glyphHit(_ event: NSEvent) -> Int? {
        let length = textStorage?.length ?? 0
        guard let lm = layoutManager, let tc = textContainer, length > 0 else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let pt = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let i = lm.characterIndex(for: pt, in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard i < length, lm.rect(forCharacters: NSRange(location: i, length: 1), in: tc).contains(pt) else { return nil }
        return i
    }

    /// En Preview un clic normal edita; ⌘-clic abre el enlace; clic en una casilla de tarea la marca.
    override func mouseDown(with event: NSEvent) {
        if isRichText, let i = glyphHit(event) {
            if event.modifierFlags.contains(.command), let link = textStorage?.attribute(.link, at: i, effectiveRange: nil) {
                onLink?(link)
                return
            }
            if let task = textStorage?.attribute(Markdown.taskKey, at: i, effectiveRange: nil) as? Int { onTaskClick?(task); return }
        }
        super.mouseDown(with: event)
    }
    override func paste(_ sender: Any?) { isRichText ? pasteAsPlainText(sender) : super.paste(sender) }

    /// NSTextView vuelve a calcular sus tipos de arrastre al cambiar editable/formato; aquí se mantiene siempre el de archivos.
    override func updateDragTypeRegistration() {
        super.updateDragTypeRegistration()
        registerForDraggedTypes(registeredDraggedTypes + [.fileURL])
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasDroppedFile(sender) ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasDroppedFile(sender) ? .copy : super.draggingUpdated(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasDroppedFile(sender) || super.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        openDropped(sender) || super.performDragOperation(sender)
    }
}

/// El text view solo mide lo que ocupa su texto; el área vacía del scroll también debe aceptar el drop.
final class DropScrollView: NSScrollView {
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { hasDroppedFile(sender) ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { openDropped(sender) }
}

/// Botón «copiar» que flota sobre cada bloque de código del Preview.
final class CopyButton: NSButton {
    private static let idle = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copiar código")
    private let code: String

    init(code: String) {
        self.code = code
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        isBordered = false
        image = Self.idle
        contentTintColor = .tertiaryLabelColor
        toolTip = "Copiar código"
        target = self
        action = #selector(copyCode)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copiado")
        contentTintColor = Palette.command
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.image = Self.idle
            self?.contentTintColor = .tertiaryLabelColor
        }
    }
}

/// NSSplitView que no dibuja el divisor cuando un panel está oculto (si no, queda una línea fantasma donde estaba).
final class QuietSplitView: NSSplitView {
    override func drawDivider(in rect: NSRect) {
        if !arrangedSubviews.contains(where: \.isHidden) { super.drawDivider(in: rect) }
    }
}

enum Mode { case preview, raw, split }

final class DocWindowController: NSWindowController, NSTextViewDelegate, NSSplitViewDelegate {
    unowned let doc: MarkdownDocument
    private let textView = DropTextView(frame: .zero)     // editor principal (Preview editable o Markdown)
    private let previewView = DropTextView(frame: .zero)  // segundo panel, solo lectura, en modo Split
    private let scroll = DropScrollView()
    private let previewScroll = DropScrollView()
    private let sidebar = SidebarView(frame: .zero)
    private let mainSplit = QuietSplitView()
    private let editorSplit = QuietSplitView()
    private let modeControl = NSSegmentedControl(labels: ["", "Preview", "Markdown"], trackingMode: .selectOne, target: nil, action: nil)
    private let pathLabel = NSTextField(labelWithString: "")
    private let statsLabel = NSTextField(labelWithString: "")
    private let caretLabel = NSTextField(labelWithString: "")
    static var newWindowNext = false
    private static let segments: [Mode] = [.split, .preview, .raw] // orden del selector: ícono Split, Preview, Markdown
    private var mode: Mode
    private var runs: [Markdown.Run] = [] // mapa Preview -> fuente, vigente solo mientras se edita en Preview
    private var splitCode: [NSRange] = []
    private var shown: Mode = .raw // el modo que realmente se ve (un .txt siempre es .raw), fijado en apply()
    private var editingPreview: Bool { shown == .preview }
    private var splitShown: Bool { shown == .split }
    private var timer: Timer?

    init(doc: MarkdownDocument) {
        self.doc = doc
        mode = doc.isMarkdown && doc.fileURL != nil ? .preview : .raw // los .md abiertos se ven formateados; los nuevos, crudos
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        shouldCascadeWindows = true
        window.isRestorable = false // cada arranque empieza limpio, sin reabrir lo de la sesión anterior
        window.tabbingIdentifier = "visualizadorgc"
        // cada archivo nuevo abre como pestaña de la misma ventana, salvo «Nueva ventana»
        let separate = Self.newWindowNext
        Self.newWindowNext = false
        window.tabbingMode = separate ? .disallowed : .preferred
        if separate { // desplazada respecto a la ventana activa, para que se vea que es otra
            if let key = NSApp.keyWindow { window.setFrameOrigin(NSPoint(x: key.frame.origin.x + 32, y: key.frame.origin.y - 32)) }
            DispatchQueue.main.async { window.tabbingMode = .preferred } // y luego sí admite pestañas
        }

        setUp(textView, in: scroll)
        setUp(previewView, in: previewScroll)
        previewView.isEditable = false
        previewView.isRichText = true
        textView.delegate = self
        previewView.delegate = self // solo para los enlaces
        textView.onLink = { [weak self] in self?.follow($0) }
        previewView.onLink = { [weak self] in self?.follow($0) }
        textView.onTaskClick = { [weak self] in self?.toggleTask(at: $0) }
        previewView.onTaskClick = { [weak self] in self?.toggleTask(at: $0) }
        scroll.hasVerticalRuler = true
        scroll.verticalRulerView = LineNumberRuler(scrollView: scroll, textView: textView)

        sidebar.isHidden = true
        previewScroll.isHidden = true
        sidebar.onHeading = { [weak self] in self?.jump(to: $0) }
        for (split, views) in [(mainSplit, [sidebar, editorSplit]), (editorSplit, [scroll, previewScroll])] as [(NSSplitView, [NSView])] {
            split.isVertical = true
            split.dividerStyle = .thin
            split.delegate = self
            views.forEach(split.addArrangedSubview)
        }
        mainSplit.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        mainSplit.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = buildContent()

        modeControl.setImage(NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Split"), forSegment: 0)
        modeControl.setWidth(34, forSegment: 0)
        modeControl.setToolTip("Split: Markdown y Preview lado a lado (⌘3)", forSegment: 0)
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.sizeToFit()
        let box = NSView(frame: NSRect(x: 0, y: 0, width: modeControl.frame.width + 16, height: modeControl.frame.height + 6))
        modeControl.frame.origin = NSPoint(x: 0, y: 3) // margen a la derecha: así «Markdown» no se sale de la ventana
        box.addSubview(modeControl)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = box
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)

        textView.postsFrameChangedNotifications = true
        previewView.postsFrameChangedNotifications = true
        scroll.contentView.postsBoundsChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(layoutCopyButtons), name: NSView.frameDidChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(layoutCopyButtons), name: NSView.frameDidChangeNotification, object: previewView)
        nc.addObserver(self, selector: #selector(syncScroll), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        nc.addObserver(self, selector: #selector(workspaceChanged), name: Workspace.changed, object: nil)
        apply()
        DispatchQueue.main.async { // al abrir, siempre arriba; y el panel lateral hereda el estado de la última vez
            self.scrollTo(self.scroll, y: 0)
            if Workspace.shared.sidebarVisible { self.setSidebar(visible: true) }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
    }

    private func setUp(_ tv: DropTextView, in sc: NSScrollView) {
        sc.hasVerticalScroller = true
        sc.documentView = tv
        _ = tv.layoutManager // fuerza TextKit 1: los bloques de código y tablas (NSTextBlock) no existen en TextKit 2
        tv.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
        tv.autoresizingMask = .width
        tv.isVerticallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset = NSSize(width: 24, height: 20)
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
    }

    private func buildContent() -> NSView {
        let side = NSButton(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Panel lateral")!, target: self, action: #selector(toggleSide))
        side.isBordered = false
        side.contentTintColor = .secondaryLabelColor
        side.toolTip = "Panel lateral (⌘B)"
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.isSelectable = true // para poder copiar la ruta
        for label in [pathLabel, statsLabel, caretLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        func separator() -> NSBox { let b = NSBox(); b.boxType = .separator; return b }
        let top = separator(), bottom = separator()
        let bar = NSView()
        let content = NSView()
        let all: [NSView] = [side, pathLabel, top, mainSplit, bottom, bar, statsLabel, caretLabel]
        all.forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }
        NSLayoutConstraint.activate([
            side.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            side.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            side.widthAnchor.constraint(equalToConstant: 22),
            side.heightAnchor.constraint(equalToConstant: 20),
            pathLabel.centerYAnchor.constraint(equalTo: side.centerYAnchor),
            pathLabel.leadingAnchor.constraint(equalTo: side.trailingAnchor, constant: 6),
            pathLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            top.topAnchor.constraint(equalTo: side.bottomAnchor, constant: 4),
            top.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            mainSplit.topAnchor.constraint(equalTo: top.bottomAnchor),
            mainSplit.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            mainSplit.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            mainSplit.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 22),
            statsLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            statsLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            caretLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            caretLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return content
    }

    // MARK: modos

    func apply() {
        let md = doc.isMarkdown
        let effective: Mode = md ? mode : .raw
        shown = effective
        textView.isRichText = editingPreview
        textView.allowsUndo = !editingPreview // en Preview cada edición se traduce al fuente; el deshacer del sistema no sabría deshacer eso
        textView.undoManager?.removeAllActions()
        if editingPreview {
            let r = Markdown.render(doc.text)
            runs = r.runs
            textView.textStorage?.setAttributedString(r.text)
        } else {
            runs = []
            textView.string = doc.text
            if let storage = textView.textStorage, md { RawHighlight.apply(storage) } else { textView.font = RawHighlight.mono; textView.textColor = .textColor }
            textView.typingAttributes = RawHighlight.base
        }
        if effective == .split {
            if previewScroll.isHidden {
                previewScroll.isHidden = false
                editorSplit.adjustSubviews() // al des-ocultar, el NSSplitView deja ambos paneles en ancho 0 si no se redistribuye
                editorSplit.setPosition(editorSplit.bounds.width / 2, ofDividerAt: 0)
            }
            renderSplit()
        } else if !previewScroll.isHidden {
            previewScroll.isHidden = true
            editorSplit.adjustSubviews()
        }
        scroll.rulersVisible = !editingPreview
        modeControl.selectedSegment = Self.segments.firstIndex(of: effective) ?? 1
        refreshPath()
        refreshDerived()
        DispatchQueue.main.async { self.layoutCopyButtons() }
    }

    func refreshPath() {
        pathLabel.stringValue = doc.fileURL?.path ?? "Sin guardar"
        pathLabel.toolTip = pathLabel.stringValue
        modeControl.isEnabled = doc.isMarkdown
    }

    private func renderSplit() {
        let r = Markdown.render(doc.text)
        previewView.textStorage?.setAttributedString(r.text)
        splitCode = r.runs.filter(\.code).map(\.range)
        layoutCopyButtons()
        syncScroll()
    }

    /// Estadísticas, índice y panel Split se recalculan 0,3 s después de la última edición.
    private func scheduleRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.refreshDerived()
            if self.splitShown { self.renderSplit() }
        }
    }

    private func refreshDerived() {
        let text = doc.text
        let words = text.split(whereSeparator: \.isWhitespace).count
        let lines = text.isEmpty ? 0 : text.utf8.filter { $0 == 10 }.count + 1
        statsLabel.stringValue = "\(words.formatted()) palabras · \(text.count.formatted()) caracteres · \(lines.formatted()) líneas"
        if !sidebar.isHidden { sidebar.headings = SidebarView.headings(in: text) }
    }

    @objc private func syncScroll() {
        guard splitShown else { return }
        let a = scroll.contentView.bounds
        let t = a.origin.y / max(1, textView.frame.height - a.height)
        scrollTo(previewScroll, y: max(0, t * (previewView.frame.height - previewScroll.contentView.bounds.height)))
    }

    private func scrollTo(_ sv: NSScrollView, y: CGFloat) {
        sv.contentView.scroll(to: NSPoint(x: 0, y: y))
        sv.reflectScrolledClipView(sv.contentView)
    }

    // MARK: botones de copiar código

    @objc private func layoutCopyButtons() {
        place(in: textView, ranges: editingPreview ? runs.filter(\.code).map(\.range) : [])
        place(in: previewView, ranges: splitShown ? splitCode : [])
    }

    private func place(in tv: NSTextView, ranges: [NSRange]) {
        let old = tv.subviews.compactMap { $0 as? CopyButton }
        if old.isEmpty && ranges.isEmpty { return } // lo normal: documento sin bloques de código
        old.forEach { $0.removeFromSuperview() }
        guard let lm = tv.layoutManager, let tc = tv.textContainer, let text = tv.textStorage?.mutableString else { return }
        for r in ranges where r.length > 0 && NSMaxRange(r) <= text.length {
            lm.ensureLayout(forCharacterRange: r)
            let rect = lm.rect(forCharacters: r, in: tc)
            let button = CopyButton(code: text.substring(with: r))
            button.frame.origin = NSPoint(x: tv.textContainerOrigin.x + tc.size.width - 30, y: rect.minY + tv.textContainerOrigin.y - 6)
            tv.addSubview(button)
        }
    }

    // MARK: panel lateral

    @objc func toggleSide(_ sender: Any?) { setSidebar(visible: sidebar.isHidden) }

    private func setSidebar(visible: Bool) {
        Workspace.shared.sidebarVisible = visible
        sidebar.isHidden = !visible
        mainSplit.adjustSubviews() // el NSSplitView no redistribuye solo al mostrar/ocultar un panel
        guard visible else { return }
        mainSplit.setPosition(240, ofDividerAt: 0)
        sidebar.headings = SidebarView.headings(in: doc.text)
    }

    @objc private func workspaceChanged() {
        guard window?.isKeyWindow == true, Workspace.shared.folder != nil else { return }
        setSidebar(visible: true)
        sidebar.showFiles()
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat { splitView === mainSplit ? 160 : proposed }
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat { splitView === mainSplit ? 420 : proposed }

    /// Salta al título elegido en el índice, en Preview o en el editor.
    private func jump(to h: SidebarView.Heading) {
        let source = doc.text as NSString
        if editingPreview {
            guard let run = runs.first(where: { ($0.src ?? -1) >= h.offset }) else { return }
            reveal(run.range)
        } else {
            reveal(source.lineRange(for: NSRange(location: min(h.offset, source.length), length: 0)))
        }
        window?.makeFirstResponder(textView)
    }

    private func reveal(_ r: NSRange) {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        lm.ensureLayout(forCharacterRange: r)
        let y = max(0, lm.rect(forCharacters: NSRange(location: r.location, length: min(1, r.length)), in: tc).minY + textView.textContainerOrigin.y - 12)
        scrollTo(scroll, y: y)
        textView.setSelectedRange(NSRange(location: r.location, length: 0))
    }

    // MARK: enlaces

    /// En Preview un clic edita y ⌘-clic sigue el enlace; en el panel Split (solo lectura) basta el clic.
    func textView(_ tv: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if tv.isEditable && !NSEvent.modifierFlags.contains(.command) { return true }
        follow(link)
        return true
    }

    /// Enlaces web/mail → sistema; `#sección` → salto al título; ruta relativa o absoluta → se resuelve contra la carpeta
    /// del documento (los .md/.txt se abren como pestaña, otros archivos con su app).
    private func follow(_ link: Any) {
        let raw = (link as? URL)?.absoluteString ?? (link as? String) ?? ""
        if let url = URL(string: raw), let scheme = url.scheme, scheme != "file" { NSWorkspace.shared.open(url); return }
        let parts = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = parts[0].split(separator: "?").first.map(String.init) ?? ""
        let fragment = parts.count > 1 ? String(parts[1]) : nil

        if pathPart.isEmpty { // enlace interno: #titulo
            let slug = (fragment ?? "").removingPercentEncoding?.lowercased() ?? ""
            if let h = SidebarView.headings(in: doc.text).first(where: { Self.slug($0.title) == slug }) { jump(to: h) } else { NSSound.beep() }
            return
        }
        let decoded = pathPart.removingPercentEncoding ?? pathPart
        let base = doc.fileURL?.deletingLastPathComponent()
        let target = (decoded.hasPrefix("/") || decoded.hasPrefix("file:") ? URL(fileURLWithPath: decoded.replacingOccurrences(of: "file://", with: "")) : URL(fileURLWithPath: decoded, relativeTo: base)).standardizedFileURL

        guard FileManager.default.fileExists(atPath: target.path) else {
            guard let window else { return }
            let alert = NSAlert()
            alert.messageText = "No se encontró el archivo"
            alert.informativeText = target.path
            alert.beginSheetModal(for: window)
            return
        }
        if Workspace.isDocument(target) { Workspace.shared.openFile(target) } else { NSWorkspace.shared.open(target) }
    }

    /// Ancla estilo GitHub: minúsculas, espacios → guiones, sin signos.
    private static func slug(_ title: String) -> String {
        String(title.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }.map { $0 == " " ? "-" : $0 })
    }

    /// Marca o desmarca una tarea `- [ ]` clicando su casilla; cambia solo esos 3 caracteres del fuente.
    private func toggleTask(at loc: Int) {
        let source = doc.text as NSString
        guard loc + 3 <= source.length else { return }
        let mark = source.substring(with: NSRange(location: loc, length: 3))
        guard ["[ ]", "[x]", "[X]"].contains(mark) else { return }
        let done = mark == "[ ]"
        doc.text = source.replacingCharacters(in: NSRange(location: loc, length: 3), with: done ? "[x]" : "[ ]")
        doc.updateChangeCount(.changeDone)
        let y = scroll.contentView.bounds.origin.y // al re-renderizar se conserva la posición de lectura
        apply()
        scrollTo(scroll, y: y)
    }

    /// Preview editable: solo texto. Cada edición se traduce a su lugar exacto en el fuente; si no se puede
    /// hacer con certeza (varios fragmentos, saltos de línea, símbolos de Markdown…) se rechaza y el archivo no se toca.
    func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard editingPreview else { return true }
        guard let new = replacementString,
              let i = runs.firstIndex(where: { $0.src != nil && range.location >= $0.range.location && NSMaxRange(range) <= NSMaxRange($0.range) })
        else { NSSound.beep(); return false }

        let run = runs[i]
        let shown = textView.string as NSString
        let oldRun = shown.substring(with: run.range)
        let local = range.location - run.range.location
        let newRun = (oldRun as NSString).replacingCharacters(in: NSRange(location: local, length: range.length), with: new)
        let rejected = run.code
            ? new.contains("```")
            : new.rangeOfCharacter(from: Self.markdownSymbols) != nil || (Self.startsList(newRun) && !Self.startsList(oldRun))

        let at = NSRange(location: run.src! + local, length: range.length)
        let source = doc.text as NSString
        // el fuente debe contener exactamente lo que se va a reemplazar; si no, el mapa está desfasado
        guard !rejected, NSMaxRange(at) <= source.length, source.substring(with: at) == shown.substring(with: range) else { NSSound.beep(); return false }

        doc.text = source.replacingCharacters(in: at, with: new)
        doc.updateChangeCount(.changeDone)
        let delta = (new as NSString).length - range.length
        runs[i].range.length += delta
        for j in runs.indices where j > i {
            runs[j].range.location += delta
            if runs[j].src != nil { runs[j].src! += delta }
        }
        return true
    }

    private static let markdownSymbols = CharacterSet(charactersIn: "\\`*_[]<>~|#\n\r")
    private static let listStart = try! NSRegularExpression(pattern: "^\\s*([-+]|\\d+[.)])\\s")
    private static func startsList(_ t: String) -> Bool { listStart.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil }

    func textDidChange(_ notification: Notification) {
        if editingPreview { // el fuente ya se actualizó en shouldChangeTextIn; ahora que el texto cambió, se recolocan los botones
            layoutCopyButtons()
            scheduleRefresh()
            return
        }
        doc.text = textView.string
        doc.updateChangeCount(.changeDone)
        if doc.isMarkdown, !textView.hasMarkedText(), let storage = textView.textStorage {
            RawHighlight.apply(storage)
            textView.typingAttributes = RawHighlight.base
        }
        scheduleRefresh()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard (notification.object as? NSTextView) === textView else { return }
        guard !editingPreview else { caretLabel.stringValue = ""; return }
        guard let text = textView.textStorage?.mutableString else { return }
        let loc = min(textView.selectedRange().location, text.length)
        var line = 1, lineStart = 0
        for i in 0..<loc where text.character(at: i) == 10 { line += 1; lineStart = i + 1 }
        caretLabel.stringValue = "Ln \(line), Col \(loc - lineStart + 1)"
    }

    private func setMode(_ m: Mode) { mode = m; apply() }
    @objc private func modeChanged() { setMode(Self.segments[modeControl.selectedSegment]) }
    @objc func showRendered(_ sender: Any?) { setMode(.preview) }
    @objc func showRaw(_ sender: Any?) { setMode(.raw) }
    @objc func showSplit(_ sender: Any?) { setMode(.split) }
}

private extension NSLayoutManager {
    func rect(forCharacters r: NSRange, in tc: NSTextContainer) -> NSRect {
        boundingRect(forGlyphRange: glyphRange(forCharacterRange: r, actualCharacterRange: nil), in: tc)
    }
}
