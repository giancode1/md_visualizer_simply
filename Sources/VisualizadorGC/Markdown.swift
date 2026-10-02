import AppKit

/// Markdown -> NSAttributedString usando el parser de Foundation (sin dependencias).
enum Markdown {
    /// Atributo de la casilla de una tarea (`- [ ] x`): valor = posición de "[" en el fuente.
    static let taskKey = NSAttributedString.Key("vgcTask")

    /// Fragmento de texto mostrado y dónde está, literal, en el fuente (`src == nil`: no se pudo ubicar con certeza, no editable).
    struct Run { var range: NSRange; var src: Int?; var code: Bool }

    static func render(_ src: String) -> (text: NSAttributedString, runs: [Run]) {
        let body = NSFont.systemFont(ofSize: 15)
        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        guard let md = try? AttributedString(markdown: src, options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)) else {
            return (NSAttributedString(string: src, attributes: [.font: body, .foregroundColor: NSColor.textColor]), [])
        }

        let out = NSMutableAttributedString()
        var lastBlock: Int?
        var lastRowID: Int?, lastTableID: Int?, rowIndex = -1 // las filas se numeran aquí: Foundation no garantiza el índice
        var tables = [Int: NSTextTable](), cells = [Int: NSTextTableBlock]()
        var seenItems = Set<Int>()
        var codeBlocks = [Int: NSTextBlock]() // un NSTextBlock compartido por todas las líneas = una caja continua

        let source = src as NSString
        var cursor = 0
        var runs = [Run]()
        let all = Array(md.runs)

        /// Búsqueda literal hacia adelante en el fuente, acotada a `limit` caracteres.
        func find(_ s: String, from: Int, limit: Int = .max) -> NSRange {
            source.range(of: s, options: .literal, range: NSRange(location: from, length: min(limit, source.length - from)))
        }
        /// Cierra el párrafo previo con un salto que hereda su estilo, para que una caja (código/tabla) lo contenga en vez de salirse de ella.
        @discardableResult func closeParagraph() -> NSParagraphStyle? {
            let prev = out.attributes(at: out.length - 1, effectiveRange: nil)
            out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: prev[.paragraphStyle] as Any, .font: prev[.font] as Any]))
            return prev[.paragraphStyle] as? NSParagraphStyle
        }

        for (n, run) in all.enumerated() {
            let comps = run.presentationIntent?.components ?? []
            var level = 0, codeID: Int?, lang = "", inQuote = false, isRule = false, ordered = false, item: (id: Int, ordinal: Int)?
            var tableID: Int?, columns = 0, cellID: Int?, col = 0, rowID: Int?, isHeader = false
            var depth = 0
            for c in comps {
                switch c.kind {
                case .header(let l): level = l
                case .codeBlock(let hint): codeID = c.identity; lang = (hint ?? "").lowercased()
                case .blockQuote: inQuote = true
                case .thematicBreak: isRule = true
                case .orderedList: ordered = true; depth += 1
                case .unorderedList: depth += 1
                case .listItem(let o): if item == nil { item = (c.identity, o) }
                case .table(let cs): tableID = c.identity; columns = cs.count
                case .tableHeaderRow: rowID = c.identity; isHeader = true
                case .tableRow: rowID = c.identity
                case .tableCell(let i): cellID = c.identity; col = i
                default: break
                }
            }
            let inCode = codeID != nil
            let block = comps.first?.identity ?? -1

            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = level > 0 ? 8 : 10
            style.lineSpacing = 2
            let indent = CGFloat(depth) * 20 + (inQuote ? 16 : 0)
            style.firstLineHeadIndent = indent
            style.headIndent = indent + (item != nil ? 14 : 0)
            /// Dentro de una caja (código/celda) no hay sangría ni espacio entre párrafos.
            func place(in block: NSTextBlock) {
                style.textBlocks = [block]
                style.paragraphSpacing = 0
                style.firstLineHeadIndent = 0
                style.headIndent = 0
            }

            if let codeID {
                let box = codeBlocks[codeID] ?? {
                    let b = NSTextBlock()
                    b.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07)
                    b.setContentWidth(100, type: .percentageValueType)
                    b.setWidth(10, type: .absoluteValueType, for: .padding)
                    codeBlocks[codeID] = b
                    return b
                }()
                place(in: box)
            }

            if let tableID, let cellID {
                if tableID != lastTableID { rowIndex = -1; lastRowID = nil }
                if rowID != lastRowID { rowIndex += 1; lastRowID = rowID }
                let cell = cells[cellID] ?? {
                    let t = tables[tableID] ?? {
                        let t = NSTextTable()
                        t.numberOfColumns = columns
                        t.collapsesBorders = true
                        t.setContentWidth(100, type: .percentageValueType)
                        tables[tableID] = t
                        return t
                    }()
                    let b = NSTextTableBlock(table: t, startingRow: rowIndex, rowSpan: 1, startingColumn: col, columnSpan: 1)
                    b.setWidth(1, type: .absoluteValueType, for: .border)
                    b.setBorderColor(.separatorColor)
                    b.setWidth(6, type: .absoluteValueType, for: .padding)
                    if isHeader { b.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06) }
                    cells[cellID] = b
                    return b
                }()
                place(in: cell)
            }
            let sameTable = tableID != nil && tableID == lastTableID
            lastTableID = tableID

            var text = String(md[run.range].characters)
            var task: (loc: Int, done: Bool)?  // `- [ ] x` / `- [x] x`: se muestra una casilla clicable en vez de la viñeta
            if let item, block != lastBlock, !seenItems.contains(item.id), !inCode,
               let marker = ["[ ] ", "[x] ", "[X] "].first(where: { text.hasPrefix($0) }) {
                let m = find(marker, from: cursor, limit: 40)
                if m.location != NSNotFound { task = (m.location, marker != "[ ] "); text.removeFirst(4); cursor = NSMaxRange(m) }
            }

            if block != lastBlock {
                if lastBlock != nil {
                    let prevStyle = closeParagraph()
                    if !sameTable, prevStyle?.textBlocks.isEmpty == false {
                        // párrafo vacío sin bloque: separa cajas contiguas (si no, TextKit las fusiona) y da aire
                        out.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 8)]))
                    }
                }
                lastBlock = block
                if let item, seenItems.insert(item.id).inserted {
                    var attrs: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style]
                    var glyph = ordered ? "\(item.ordinal). " : "• "
                    if let task {
                        glyph = task.done ? "☑ " : "☐ "
                        attrs[.font] = NSFont.systemFont(ofSize: 16)
                        attrs[.foregroundColor] = task.done ? Palette.command : NSColor.secondaryLabelColor
                        attrs[taskKey] = task.loc
                    }
                    out.append(NSAttributedString(string: glyph, attributes: attrs))
                }
            }

            var font = inCode ? mono : level > 0 ? NSFont.systemFont(ofSize: [0, 28, 23, 19, 17, 15, 14][min(level, 6)], weight: .bold) : body
            var traits: NSFontDescriptor.SymbolicTraits = []
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if inline.contains(.emphasized) { traits.insert(.italic) }
            if inline.contains(.code) { font = mono }
            if isHeader { traits.insert(.bold) }
            if !traits.isEmpty { font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits)), size: font.pointSize) ?? font }

            if isRule { text = String(repeating: "─", count: 40) }
            if inCode && text.hasSuffix("\n") { text.removeLast() }
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: inQuote || isRule ? NSColor.secondaryLabelColor : NSColor.textColor, .paragraphStyle: style]
            if inline.contains(.code) && !inCode { attrs[.backgroundColor] = NSColor.quaternaryLabelColor }
            if inline.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attrs[.link] = link }
            let start = out.length
            let len = (text as NSString).length
            let piece = NSMutableAttributedString(string: text, attributes: attrs) // se resalta aparte: así no se re-escanea todo `out`
            if inCode { Highlight.apply(piece, range: NSRange(location: 0, length: len), lang: lang) }
            out.append(piece)

            // ubica el texto en el fuente, siempre hacia adelante; entre un fragmento y otro solo puede haber sintaxis (sin letras)
            var loc: Int?
            if len > 0, !isRule {
                var f = find(text, from: cursor, limit: 600)
                if f.location != NSNotFound {
                    let gap = source.substring(with: NSRange(location: cursor, length: f.location - cursor))
                    if !inCode && gap.rangeOfCharacter(from: .letters) != nil { f = NSRange(location: NSNotFound, length: 0) }
                }
                if f.location == NSNotFound && len >= 12 { // reenganche tras algo que no se pudo ubicar
                    f = find(text, from: cursor)
                }
                if f.location != NSNotFound {
                    loc = f.location
                    cursor = NSMaxRange(f)
                    // al terminar un enlace, salta su "](url)" para que la URL no se confunda con texto
                    if run.link != nil, n + 1 == all.count || all[n + 1].link != run.link {
                        let open = find("](", from: cursor, limit: 40)
                        if open.location != NSNotFound {
                            let close = find(")", from: NSMaxRange(open), limit: 2000)
                            if close.location != NSNotFound { cursor = NSMaxRange(close) }
                        }
                    }
                }
            }
            runs.append(Run(range: NSRange(location: start, length: len), src: loc, code: inCode))
        }
        if out.length > 0 { closeParagraph() } // necesario para cajas de código/tablas al final del documento
        return (out, runs)
    }

    static func selfTest() {
        let md = "# Titulo\n\ntexto **negrita** y `code` y [enlace](https://x.com/negrita)\n\n- uno\n- dos\n\n1. a\n2. b\n\n---\n"
        let r = render(md)
        let s = r.text.string
        for expected in ["Titulo", "negrita", "• uno", "• dos", "1. a", "2. b", "───"] { precondition(s.contains(expected), "falta: \(expected)\n\(s)") }
        // cada fragmento ubicado debe coincidir literalmente con el fuente
        for run in r.runs { if let at = run.src { precondition((md as NSString).substring(with: NSRange(location: at, length: run.range.length)) == (s as NSString).substring(with: run.range), "mapa roto") } }
        precondition(r.runs.contains { $0.src != nil && (s as NSString).substring(with: $0.range) == "negrita" }, "no ubicó 'negrita'")
        let tk = render("- [ ] pendiente\n- [x] hecha\n")
        precondition(tk.text.string.contains("☐ pendiente") && tk.text.string.contains("☑ hecha"), "tareas sin casilla")
        precondition(tk.runs.allSatisfy { $0.src != nil }, "tareas sin mapa")
        precondition(!s.contains("**") && !s.contains("# "), "sintaxis sin interpretar")

        let t = render("| a | b |\n|---|---|\n| 1 | 2 |\n").text
        var tableBlocks = 0
        t.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: t.length)) { v, _, _ in if (v as? NSParagraphStyle)?.textBlocks.isEmpty == false { tableBlocks += 1 } }
        precondition(tableBlocks > 0 && t.string.contains("a") && t.string.contains("2"), "tabla sin renderizar")

        func colors(_ t: NSAttributedString) -> Set<NSColor> {
            var found = Set<NSColor>()
            t.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: t.length)) { v, _, _ in if let v = v as? NSColor { found.insert(v) } }
            return found
        }
        let code = colors(render("```swift\nlet x = \"hi\" // nota\n```\n").text)
        let shColors = colors(render("```bash\nyarn worker:sign --watch # nota\n```\n").text)
        precondition(shColors.contains(Palette.command) && shColors.contains(Palette.flag) && shColors.contains(Palette.comment), "shell sin colorear")
        precondition(code.contains(Palette.keyword) && code.contains(Palette.string) && code.contains(Palette.comment), "código sin resaltar")
    }
}
