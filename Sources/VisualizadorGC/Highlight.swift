import AppKit

/// Paleta del código (tipo VS Code: clara y oscura). Los comandos de terminal van en verde.
enum Palette {
    private static func dyn(_ light: Int, _ dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let v = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
        }
    }
    static let keyword = dyn(0x0000FF, 0x569CD6)
    static let control = dyn(0xAF00DB, 0xC586C0)
    static let type = dyn(0x267F99, 0x4EC9B0)
    static let function = dyn(0x795E26, 0xDCDCAA)
    static let constant = dyn(0x0070C1, 0x4FC1FF)
    static let property = dyn(0x001080, 0x9CDCFE)
    static let string = dyn(0xA31515, 0xCE9178)
    static let number = dyn(0x098658, 0xB5CEA8)
    static let command = dyn(0x1A7F37, 0x3FB950)
    static let flag = dyn(0xB35900, 0xE0AF68)
    static let tag = dyn(0x800000, 0x569CD6)
    static let decorator = dyn(0xC2410C, 0xFB923C)
    static let added = command
    static let removed = dyn(0xCF222E, 0xF85149)
    static let comment = NSColor.secondaryLabelColor
}

/// Resaltado de sintaxis por regex (no es un parser): genérico tipo C/JS/Python/SQL/Prisma/YAML/JSON, más reglas propias para shell, diff y HTML.
/// ponytail: un solo conjunto de keywords para los lenguajes genéricos. Sin lenguaje declarado no se colorea.
enum Highlight {
    private static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }
    private static let control = words("import from export default return if else for while do switch case break continue try catch finally throw await yield with raise except elif pass assert")
    private static let keywords = words("""
        const let var function new class extends async typeof instanceof in of this null true false undefined void static public private protected interface \
        type enum implements package def lambda None True False self is not and or model datasource generator select insert update delete into values where \
        join left right inner on group by order limit create table alter drop primary key foreign references fn mut pub impl struct trait use mod match func go \
        defer chan range then fi done echo readonly abstract override namespace using final int float double bool char long short unsigned nil NULL super \
        SELECT FROM WHERE INSERT INTO VALUES UPDATE DELETE JOIN LEFT RIGHT INNER ON GROUP BY ORDER LIMIT CREATE TABLE ALTER DROP AND OR NOT AS
        """)
    private static let builtinTypes = words("string number boolean any never unknown object str dict list")
    private static let skip = words("text txt plain plaintext ascii output")

    static func apply(_ s: NSMutableAttributedString, range: NSRange, lang: String) {
        switch lang {
        case "bash", "sh", "shell", "zsh", "console", "terminal", "shellscript": shell(s, range)
        case "diff", "patch": diff(s, range)
        case "html", "xml", "svg", "vue", "xhtml": markup(s, range)
        case let l where skip.contains(l) || l.isEmpty: return
        default: generic(s, range, lang)
        }
    }

    /// Compilar una NSRegularExpression es caro y el resaltado corre en cada tecla: se compila una vez por patrón.
    /// Solo se usa desde el hilo principal.
    private static var regexCache: [String: NSRegularExpression] = [:]
    static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = "\(options.rawValue)|\(pattern)"
        if let cached = regexCache[key] { return cached }
        let compiled = try? NSRegularExpression(pattern: pattern, options: options)
        regexCache[key] = compiled
        return compiled
    }

    /// Pinta todas las coincidencias de `pattern` (color y/o fuente); lo que se pinta después tapa lo anterior.
    /// `text` es `s.string`: se pasa para no copiarlo en cada llamada.
    static func paint(_ s: NSMutableAttributedString, _ text: String, _ range: NSRange, _ pattern: String, _ color: NSColor? = nil, font: NSFont? = nil, group: Int = 0) {
        guard let re = regex(pattern, [.anchorsMatchLines]) else { return }
        re.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let r = m?.range(at: group), r.location != NSNotFound else { return }
            if let color { s.addAttribute(.foregroundColor, value: color, range: r) }
            if let font { s.addAttribute(.font, value: font, range: r) }
        }
    }
    private static let strings = "\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'|`(?:[^`\\\\]|\\\\.)*`"

    private static func shell(_ s: NSMutableAttributedString, _ r: NSRange) {
        let text = s.string
        func p(_ pattern: String, _ color: NSColor, group: Int = 0) { paint(s, text, r, pattern, color, group: group) }
        p("(?:^|[|;&(]|\\$\\()\\s*(?:\\$\\s+)?([A-Za-z_./~][\\w./~:+@-]*)", Palette.command, group: 1) // comando = primera palabra de cada orden
        p("(?<=\\s)--?[A-Za-z][\\w-]*", Palette.flag)
        p("\\$\\{?[A-Za-z_]\\w*\\}?|\\$[0-9@#?*!$-]", Palette.property)
        p(strings, Palette.string)
        p("(?<![\\w$.-])\\d+(?:\\.\\d+)*(?![\\w.-])", Palette.number)
        p("(?:^|(?<=\\s))#[^\\n]*", Palette.comment)
    }

    private static func diff(_ s: NSMutableAttributedString, _ r: NSRange) {
        let text = s.string
        paint(s, text, r, "^\\+.*$", Palette.added)
        paint(s, text, r, "^-.*$", Palette.removed)
        paint(s, text, r, "^@@.*$", Palette.keyword)
    }

    private static func markup(_ s: NSMutableAttributedString, _ r: NSRange) {
        let text = s.string
        func p(_ pattern: String, _ color: NSColor) { paint(s, text, r, pattern, color) }
        p("</?[A-Za-z][\\w:.-]*|/?>", Palette.tag)
        p("(?<=\\s)[A-Za-z_:@][\\w:.-]*(?==)", Palette.property)
        p(strings, Palette.string)
        p("<!--[\\s\\S]*?-->", Palette.comment)
    }

    private static func generic(_ s: NSMutableAttributedString, _ range: NSRange, _ lang: String) {
        let hash: Set<String> = ["python", "py", "yaml", "yml", "ruby", "rb", "toml", "dockerfile", "env", "ini", "makefile"]
        let comment = ["sql", "lua"].contains(lang) ? "--[^\\n]*" : hash.contains(lang) ? "#[^\\n]*" : "//[^\\n]*|/\\*[\\s\\S]*?\\*/"
        let pattern = "(\(comment))|(\(strings))|(@@?[A-Za-z_][\\w.]*)|(\\b\\d+(?:\\.\\d+)?\\b)|(\\b[A-Za-z_]\\w*\\b)"
        guard let re = regex(pattern) else { return }
        let text = s.string
        let str = text as NSString
        func next(_ from: Int) -> (idx: Int, ch: unichar) {
            var j = from
            while j < str.length, str.character(at: j) == 32 { j += 1 }
            return (j, j < str.length ? str.character(at: j) : 0)
        }
        re.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let m else { return }
            let color: NSColor?
            if m.range(at: 1).location != NSNotFound {
                color = Palette.comment
            } else if m.range(at: 2).location != NSNotFound {
                color = next(m.range.upperBound).ch == 58 ? Palette.property : Palette.string // string seguido de ':' = clave
            } else if m.range(at: 3).location != NSNotFound {
                color = Palette.decorator
            } else if m.range(at: 4).location != NSNotFound {
                color = Palette.number
            } else {
                let w = str.substring(with: m.range)
                let prev = m.range.location > 0 ? str.character(at: m.range.location - 1) : 0
                if control.contains(w) {
                    color = Palette.control
                } else if keywords.contains(w) || (lang == "sql" && keywords.contains(w.uppercased())) {
                    color = Palette.keyword
                } else {
                    let (j, after) = next(m.range.upperBound)
                    let isConst = w.count > 1 && w == w.uppercased() && w.first!.isLetter
                    let isClass = w.count > 1 && w.first!.isUppercase && !isConst
                    if prev == 46 { color = after == 40 ? Palette.function : isConst ? Palette.constant : Palette.property } // tras un punto
                    else if isClass { color = Palette.type }
                    else if after == 40 { color = Palette.function }
                    else if after == 58, !(j + 1 < str.length && str.character(at: j + 1) == 58) { color = Palette.property }
                    else if isConst { color = Palette.constant }
                    else if builtinTypes.contains(w) { color = Palette.type }
                    else { color = nil }
                }
            }
            if let color { s.addAttribute(.foregroundColor, value: color, range: m.range) }
        }
    }
}

/// Colores para el editor Markdown crudo (títulos, negrita, enlaces, listas, código con su lenguaje…).
/// ponytail: se repasa todo el documento en cada cambio; si un archivo enorme se siente lento, limitar al párrafo editado.
enum RawHighlight {
    static let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let base: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: NSColor.textColor]
    private static let bold = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    private static let italic = NSFontManager.shared.convert(mono, toHaveTrait: .italicFontMask)

    static func apply(_ s: NSTextStorage) {
        let all = NSRange(location: 0, length: s.length)
        let text = s.string // los caracteres no cambian aquí, solo los atributos
        s.beginEditing()
        s.setAttributes(base, range: all)

        func paint(_ pattern: String, _ color: NSColor? = nil, font: NSFont? = nil, group: Int = 0) {
            Highlight.paint(s, text, all, pattern, color, font: font, group: group)
        }
        paint("^\\s*(?:[-*+]|\\d+[.)])\\s", Palette.type)                  // viñetas y numeración
        paint("^>.*$", .secondaryLabelColor)                              // citas
        paint("^(?:-{3,}|\\*{3,}|_{3,})\\s*$", .secondaryLabelColor)      // línea horizontal
        paint("[|]", .secondaryLabelColor)                                // tablas
        paint("(?<![*\\w])\\*[^*\\n]+\\*(?![*\\w])", Palette.control, font: italic)
        paint("(?<![\\w_])_[^_\\n]+_(?![\\w_])", Palette.control, font: italic)
        paint("\\*\\*[^*\\n]+\\*\\*", font: bold)
        paint("\\*\\*", .secondaryLabelColor)
        paint("~~[^~\\n]+~~", .secondaryLabelColor)
        paint("`[^`\\n]+`", Palette.string)
        paint("\\[[^\\]\\n]*\\]\\([^)\\n]*\\)", Palette.keyword)
        paint("^#{1,6}\\s.*$", Palette.keyword, font: bold)                    // títulos

        // bloques de código: quitan lo anterior y se colorean según su lenguaje
        let ns = text as NSString
        if ns.range(of: "```").location != NSNotFound {
            var open: (lang: String, from: Int)?
            ns.enumerateSubstrings(in: all, options: .byLines) { line, r, enclosing, _ in
                guard let t = line?.trimmingCharacters(in: .whitespaces), t.hasPrefix("```") else { return }
                s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
                if let o = open {
                    let code = NSRange(location: o.from, length: max(0, r.location - o.from))
                    s.setAttributes(base, range: code)
                    Highlight.apply(s, range: code, lang: o.lang)
                    open = nil
                } else {
                    open = (String(t.dropFirst(3)).lowercased(), NSMaxRange(enclosing))
                }
            }
        }
        s.endEditing()
    }
}

/// Números de línea al margen del editor (como Cursor).
final class LineNumberRuler: NSRulerView {
    private static let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor]
    private weak var textView: NSTextView?
    private var lineStarts: [Int]? // dónde empieza cada línea; se recalcula solo cuando cambian los caracteres, no en cada scroll

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 46
        scrollView.contentView.postsBoundsChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        nc.addObserver(self, selector: #selector(textChanged(_:)), name: NSTextStorage.didProcessEditingNotification, object: textView.textStorage)
    }
    required init(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func refresh() { needsDisplay = true }
    @objc private func textChanged(_ note: Notification) {
        if (note.object as? NSTextStorage)?.editedMask.contains(.editedCharacters) == true { lineStarts = nil }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer, let storage = tv.textStorage else { return }
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        func draw(_ n: Int, atY y: CGFloat) {
            let label = "\(n)" as NSString
            let size = label.size(withAttributes: Self.attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: convert(NSPoint(x: 0, y: y + tv.textContainerOrigin.y), from: tv).y), withAttributes: Self.attrs)
        }

        let text = storage.mutableString
        if text.length == 0 { draw(1, atY: 0); return }
        let starts = lineStarts ?? {
            var found = [0]
            for i in 0..<text.length where text.character(at: i) == 10 { found.append(i + 1) }
            lineStarts = found
            return found
        }()
        // número de línea = cuántas líneas empiezan en o antes de `index` (búsqueda binaria)
        func number(at index: Int) -> Int {
            var lo = 0, hi = starts.count
            while lo < hi { let mid = (lo + hi) / 2; if starts[mid] <= index { lo = mid + 1 } else { hi = mid } }
            return lo
        }

        let first = lm.characterRange(forGlyphRange: lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc), actualGlyphRange: nil)
        var index = text.lineRange(for: NSRange(location: first.location, length: 0)).location
        var n = number(at: index)
        while index < text.length, index <= NSMaxRange(first) {
            let frag = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: index), effectiveRange: nil)
            draw(n, atY: frag.minY)
            n += 1
            index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
        }
        if index >= text.length, text.character(at: text.length - 1) == 10 { draw(n, atY: lm.extraLineFragmentRect.minY) }
    }
}
