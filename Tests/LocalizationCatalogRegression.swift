import Foundation

// Standalone check of the Catalan/Spanish String Catalog (patch 36). No app, radio or network needed:
//   swiftc -parse-as-library Tests/LocalizationCatalogRegression.swift -o l10n && ./l10n [repository root] [--list-keys]
// Run it from anywhere; the repository root is the first argument (default: the current directory). It reads
// YAAM/Localizable.xcstrings, YAAM.xcodeproj/project.pbxproj and every YAAM/*.swift file, and checks:
//   1. the catalog is valid JSON of a String Catalog (version "1.0", sourceLanguage "en") and no key is written twice;
//   2. knownRegions of the project lists en, Base, ca and es;
//   3. a key that the project rule keeps in English has "shouldTranslate": false, one of the three fixed comments
//      (radio label, section or protocol term / FT8 or FT4 transmit, start or stop button / the code reads this text
//      back) and no ca or es value; every other key (translated) has a Catalan and a Spanish value whose state is
//      "translated" or "needs_review" (never new, stale or empty);
//   4. every format specifier of a key (%@, %lld, %.1f, ...) is present in both translations with the same type and
//      in the same order (a different order needs positional specifiers such as %2$@);
//   5. every key is a string literal of the code (an interpolation \(x) matches a specifier);
//   6. whether the compiler can extract the key: the first argument of Text, Button, Label, Toggle, Picker,
//      Section, .help, .navigationTitle and the other SwiftUI calls that take a LocalizedStringKey. A translation that
//      is not extracted today must say so in its comment ("not extracted yet"). The other direction (a comment that
//      still says so after the code was changed) is only printed as a note, because the comment is then out of date
//      but nothing is wrong;
//   7. no real callsign (the project's own) in a key or a value, no callsign- or locator-shaped word in a key, a value
//      or the comment of a translation (the service name ON4KST is allowed), and no text-field placeholder that looks
//      like a callsign or a locator;
//   8. names of kept keys: a name between « » in a translation is a kept key as written on screen; a kept label
//      name that has lower-case letters (Band, Mode, Log Table, ...) and that the English key contains as a whole
//      word never appears in the translation without the « » (a Catalan label such as "Mode digital" for a key
//      that does not contain the word Mode is fine); and when the comment of a translation names «X»,
//      both translations contain «X»;
//   9. the rules are pinned by fixed lists in this file, so that a kept key cannot lose its protection quietly:
//      every key of rule 1 (radio labels, sections, protocol terms and their variants), of rule 5 (FT8 and FT4
//      transmit, start and stop buttons) and of rule 6 (literal keys that the code reads back) must be in the
//      catalog with "shouldTranslate": false, no ca or es text and the comment of its rule; a text that the code
//      reads back and that is only a String value in the code may be absent, but if it is in the catalog it must
//      be kept;
//  10. a translated key that contains the word YAAM keeps it in both translations (the main window is found by looking
//      for the word in its title, YAAMApp.swift:371).
// If a label is reworded in the code, rename its key in the catalog: check 5 names the key that no longer matches.
// It also prints how many distinct keys the code has today. The lexer below is a small reader of Swift string
// literals; its rules were compared with the compiler's own list (-emit-localized-strings) on sample files.

// MARK: - Swift string literals

private enum Part {
    case text(String)
    case interp(String)
}

private struct Literal {
    var parts: [Part]
    var line: Int

    /// The text with every interpolation replaced by NUL, to be compared with a catalog key whose specifiers became NUL.
    var wildcard: String {
        var s = ""
        for part in parts {
            switch part {
            case .text(let t): s += t
            case .interp: s += "\u{0}"
            }
        }
        return s
    }
}

private enum TokenKind { case ident, number, punct, string }

private struct Token {
    var kind: TokenKind
    var text: String
    var line: Int
    var pos: Int
    var literal: Literal?
}

private struct Lexer {
    let s: [Unicode.Scalar]
    var i = 0
    var line = 1
    var tokens: [Token] = []

    init(_ source: String) { s = Array(source.unicodeScalars) }

    func at(_ k: Int) -> Unicode.Scalar? { k >= 0 && k < s.count ? s[k] : nil }

    func isIdentStart(_ c: Unicode.Scalar) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_" || c.value > 0x7F
    }

    func isIdentChar(_ c: Unicode.Scalar) -> Bool { isIdentStart(c) || (c >= "0" && c <= "9") }

    /// A string literal starts at k: `"`, or one or more `#` and then `"`. Returns (hashes, quotes) or nil.
    func stringStart(_ k: Int) -> (Int, Int)? {
        var j = k
        var hashes = 0
        while at(j) == "#" { hashes += 1; j += 1 }
        guard at(j) == "\"" else { return nil }
        if at(j + 1) == "\"" && at(j + 2) == "\"" { return (hashes, 3) }
        return (hashes, 1)
    }

    mutating func skipBlockComment() {
        var depth = 0
        while i < s.count {
            if s[i] == "/" && at(i + 1) == "*" { depth += 1; i += 2 }
            else if s[i] == "*" && at(i + 1) == "/" {
                depth -= 1; i += 2
                if depth == 0 { return }
            } else {
                if s[i] == "\n" { line += 1 }
                i += 1
            }
        }
    }

    /// Reads the string literal that starts at `i` and moves `i` behind it.
    mutating func readString() -> Literal {
        let startLine = line
        let (hashes, qlen) = stringStart(i) ?? (0, 1)
        i += hashes + qlen
        let multiline = qlen == 3
        var parts: [Part] = []
        var buf = String.UnicodeScalarView()

        func closes(_ k: Int, _ lexer: Lexer) -> Bool {
            for q in 0..<qlen where lexer.at(k + q) != "\"" { return false }
            for h in 0..<hashes where lexer.at(k + qlen + h) != "#" { return false }
            return true
        }
        func escapes(_ k: Int, _ lexer: Lexer) -> Bool {
            if lexer.at(k) != "\\" { return false }
            for h in 0..<hashes where lexer.at(k + 1 + h) != "#" { return false }
            return true
        }

        while i < s.count {
            if closes(i, self) { i += qlen + hashes; break }
            if escapes(i, self) {
                let j = i + 1 + hashes
                guard let c = at(j) else { break }
                if c == "(" {
                    if !buf.isEmpty { parts.append(.text(String(buf))); buf = String.UnicodeScalarView() }
                    var k = j + 1
                    var depth = 1
                    let exprStart = k
                    while k < s.count && depth > 0 {
                        let d = s[k]
                        if d == "(" { depth += 1; k += 1 }
                        else if d == ")" { depth -= 1; k += 1 }
                        else if d == "\"" || (d == "#" && stringStart(k) != nil) {
                            var sub = self
                            sub.i = k
                            _ = sub.readString()
                            line = sub.line
                            k = sub.i
                        } else if d == "/" && at(k + 1) == "*" {
                            var sub = self
                            sub.i = k
                            sub.skipBlockComment()
                            line = sub.line
                            k = sub.i
                        } else {
                            if d == "\n" { line += 1 }
                            k += 1
                        }
                    }
                    var src = String.UnicodeScalarView()
                    src.append(contentsOf: s[exprStart..<max(exprStart, k - 1)])
                    parts.append(.interp(String(src)))
                    i = k
                    continue
                } else if c == "u" && at(j + 1) == "{" {
                    var k = j + 2
                    var hex = ""
                    while let h = at(k), h != "}" { hex.unicodeScalars.append(h); k += 1 }
                    if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) { buf.append(u) }
                    i = k + 1
                    continue
                } else if let mapped = Lexer.simpleEscape(c) {
                    buf.append(mapped)
                    i = j + 1
                    continue
                } else if c == "\n" && multiline {
                    line += 1
                    i = j + 1
                    continue
                } else {
                    buf.append(s[i])
                    i += 1
                    continue
                }
            }
            let c = s[i]
            if c == "\n" {
                line += 1
                if !multiline { break }
            }
            buf.append(c)
            i += 1
        }
        if !buf.isEmpty { parts.append(.text(String(buf))) }
        if multiline { parts = Lexer.dedent(parts) }
        return Literal(parts: parts, line: startLine)
    }

    static func simpleEscape(_ c: Unicode.Scalar) -> Unicode.Scalar? {
        switch c {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "0": return "\u{0}"
        case "\\": return "\\"
        case "\"": return "\""
        case "'": return "'"
        default: return nil
        }
    }

    /// Multi-line literal: the first line break is dropped and the indentation of the closing delimiter is removed.
    static func dedent(_ parts: [Part]) -> [Part] {
        var exprs: [String] = []
        var all = ""
        for p in parts {
            switch p {
            case .text(let t): all += t
            case .interp(let e): exprs.append(e); all += "\u{1}"
            }
        }
        var lines = all.components(separatedBy: "\n")
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        var indent = ""
        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            indent = last
            lines.removeLast()
        }
        let stripped = lines.map { $0.hasPrefix(indent) ? String($0.dropFirst(indent.count)) : $0 }
        let joined = stripped.joined(separator: "\n")
        var result: [Part] = []
        var buf = ""
        var e = 0
        for ch in joined.unicodeScalars {
            if ch == "\u{1}" {
                if !buf.isEmpty { result.append(.text(buf)); buf = "" }
                if e < exprs.count { result.append(.interp(exprs[e])); e += 1 }
            } else {
                buf.unicodeScalars.append(ch)
            }
        }
        if !buf.isEmpty { result.append(.text(buf)) }
        return result
    }

    mutating func run() -> [Token] {
        while i < s.count {
            let c = s[i]
            if c == "\n" { line += 1; i += 1 }
            else if c == " " || c == "\t" || c == "\r" { i += 1 }
            else if c == "/" && at(i + 1) == "/" { while i < s.count && s[i] != "\n" { i += 1 } }
            else if c == "/" && at(i + 1) == "*" { skipBlockComment() }
            else if c == "\"" || (c == "#" && stringStart(i) != nil) {
                let pos = i
                let startLine = line
                let lit = readString()
                tokens.append(Token(kind: .string, text: "", line: startLine, pos: pos, literal: lit))
            } else if c == "`" {
                var j = i + 1
                var name = String.UnicodeScalarView()
                while j < s.count && s[j] != "`" { name.append(s[j]); j += 1 }
                tokens.append(Token(kind: .ident, text: String(name), line: line, pos: i, literal: nil))
                i = j + 1
            } else if isIdentStart(c) {
                var j = i + 1
                while j < s.count && isIdentChar(s[j]) { j += 1 }
                var name = String.UnicodeScalarView()
                name.append(contentsOf: s[i..<j])
                tokens.append(Token(kind: .ident, text: String(name), line: line, pos: i, literal: nil))
                i = j
            } else if c >= "0" && c <= "9" {
                var j = i + 1
                while j < s.count {
                    let d = s[j]
                    let alnum = isIdentChar(d)
                    if alnum || d == "." || d == "_" {
                        if d == "." {
                            guard let n = at(j + 1), n >= "0" && n <= "9" else { break }
                        }
                        j += 1
                    } else { break }
                }
                tokens.append(Token(kind: .number, text: "", line: line, pos: i, literal: nil))
                i = j
            } else {
                tokens.append(Token(kind: .punct, text: String(c), line: line, pos: i, literal: nil))
                i += 1
            }
        }
        return tokens
    }
}

// MARK: - Which literals does SwiftUI take as localization keys?

private let initAPIs: Set<String> = [
    "Text", "Button", "Label", "Toggle", "Picker", "Section", "GroupBox", "DisclosureGroup", "TextField", "SecureField",
    "Stepper", "Menu", "LabeledContent", "Link", "ProgressView", "DatePicker", "ColorPicker", "NavigationLink", "Tab",
    "ContentUnavailableView", "CommandMenu", "Window", "WindowGroup", "Gauge", "TextEditor", "Slider", "TableColumn",
]
private let modifierAPIs: Set<String> = [
    "navigationTitle", "navigationSubtitle", "help", "alert", "confirmationDialog", "accessibilityLabel",
    "accessibilityHint", "accessibilityValue", "badge", "dialogTitle",
]
private let notCalls: Set<String> = [
    "if", "while", "guard", "switch", "return", "for", "in", "case", "catch", "where", "else", "func", "init",
    "subscript", "let", "var", "throw", "try", "await", "as", "is", "repeat", "defer", "do", "some", "any",
]

private struct Extracted {
    var literal: Literal
    var api: String
    var line: Int
}

private func matchClose(_ t: [Token], _ p: Int) -> Int {
    var depth = 0
    var k = p
    while k < t.count {
        if t[k].kind == .punct {
            switch t[k].text {
            case "(", "[", "{": depth += 1
            case ")", "]", "}":
                depth -= 1
                if depth == 0 { return k }
            default: break
            }
        }
        k += 1
    }
    return -1
}

private func splitArguments(_ t: [Token], _ p: Int, _ q: Int) -> [[Token]] {
    var args: [[Token]] = []
    var cur: [Token] = []
    var depth = 0
    var k = p + 1
    while k < q {
        let tok = t[k]
        if tok.kind == .punct {
            if "([{".contains(tok.text) { depth += 1 }
            else if ")]}".contains(tok.text) { depth -= 1 }
        }
        if depth == 0 && tok.kind == .punct && tok.text == "," {
            args.append(cur)
            cur = []
        } else {
            cur.append(tok)
        }
        k += 1
    }
    if !cur.isEmpty || !args.isEmpty { args.append(cur) }
    return args
}

/// Literals that the compiler takes as keys when `arg` is the first argument of an API above: the literal itself,
/// or both branches of `condition ? "A" : "B"`. Returns the label of the argument and the literals.
private func keyLiterals(_ arg: [Token], source: [Unicode.Scalar]) -> (label: String?, literals: [Literal]) {
    var a = arg
    var label: String? = nil
    if a.count >= 2, a[0].kind == .ident, a[1].kind == .punct, a[1].text == ":",
       !(a.count > 2 && a[2].kind == .punct && a[2].text == ":") {
        label = a[0].text
        a.removeFirst(2)
    }
    if a.count == 1, a[0].kind == .string, let lit = a[0].literal { return (label, [lit]) }
    var depth = 0
    var q: Int? = nil
    var colon: Int? = nil
    for (k, t) in a.enumerated() where t.kind == .punct {
        if "([{".contains(t.text) { depth += 1 }
        else if ")]}".contains(t.text) { depth -= 1 }
        else if depth == 0 {
            if t.text == "?" {
                let before: Unicode.Scalar = t.pos > 0 ? source[t.pos - 1] : " "
                let after: Unicode.Scalar = t.pos + 1 < source.count ? source[t.pos + 1] : " "
                if before == " " && after == " " && q == nil { q = k }
            } else if t.text == ":" && q != nil && colon == nil {
                colon = k
            }
        }
    }
    if let q, let colon {
        let one = Array(a[(q + 1)..<colon])
        let two = Array(a[(colon + 1)...])
        if one.count == 1, two.count == 1, one[0].kind == .string, two[0].kind == .string,
           let l1 = one[0].literal, let l2 = two[0].literal {
            return (label, [l1, l2])
        }
    }
    return (label, [])
}

private struct SourceScan {
    var allLiterals: [String: [(file: String, line: Int)]] = [:]     // wildcard form -> places
    var extracted: [String: [(file: String, line: Int, api: String)]] = [:]
    var swiftFiles = 0
    var swiftLines = 0
}

private func scanSource(root: String) -> SourceScan {
    var scan = SourceScan()
    let fm = FileManager.default
    let dir = root + "/YAAM"
    let names = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".swift") }.sorted()
    for name in names {
        guard let text = try? String(contentsOfFile: dir + "/" + name, encoding: .utf8) else { continue }
        scan.swiftFiles += 1
        scan.swiftLines += text.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
        var lexer = Lexer(text)
        let toks = lexer.run()
        for t in toks where t.kind == .string {
            if let lit = t.literal { scan.allLiterals[lit.wildcard, default: []].append((name, lit.line)) }
        }
        for p in 1..<max(1, toks.count) {
            guard toks[p].kind == .punct, toks[p].text == "(", toks[p - 1].kind == .ident else { continue }
            let callee = toks[p - 1].text
            if notCalls.contains(callee) { continue }
            let isModifier = p >= 2 && toks[p - 2].kind == .punct && toks[p - 2].text == "."
            let known = isModifier ? modifierAPIs.contains(callee) : initAPIs.contains(callee)
            let localized = !isModifier && (callee == "LocalizedStringKey")
            guard known || localized else { continue }
            let q = matchClose(toks, p)
            guard q > p else { continue }
            let args = splitArguments(toks, p, q)
            guard let first = args.first else { continue }
            let (label, literals) = keyLiterals(first, source: lexer.s)
            guard label == nil else { continue }
            for lit in literals {
                scan.extracted[lit.wildcard, default: []].append((name, lit.line, callee))
            }
        }
    }
    return scan
}


// MARK: - Format specifiers

private struct Specifier {
    var position: Int?
    var type: String
}

private let specifierPattern = "%(?:(\\d+)\\$)?[-+#0]*\\d*(?:\\.\\d+)?((?:hh|h|ll|l|q|L|z|t|j)?[diouxXeEfFgGaAcCsSpn@])"

private func specifiers(in s: String) -> [Specifier] {
    guard let rx = try? NSRegularExpression(pattern: specifierPattern) else { return [] }
    let cleaned = s.replacingOccurrences(of: "%%", with: "")
    let ns = cleaned as NSString
    return rx.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)).map { m in
        let position = m.range(at: 1).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 1)))
        return Specifier(position: position, type: "%" + ns.substring(with: m.range(at: 2)))
    }
}

/// True when `value` takes the same arguments as `key`, of the same types and in the same order. A value may
/// change the order only with positional specifiers (%2$@ ... %1$lld) that cover every position once.
private func specifiersAgree(key: String, value: String) -> Bool {
    let wanted = specifiers(in: key).map { $0.type }
    let found = specifiers(in: value)
    if found.count != wanted.count { return false }
    if found.allSatisfy({ $0.position == nil }) { return found.map { $0.type } == wanted }
    var byPosition: [Int: String] = [:]
    for spec in found {
        guard let p = spec.position, p >= 1, p <= wanted.count, byPosition[p] == nil else { return false }
        byPosition[p] = spec.type
    }
    return (1...max(1, wanted.count)).allSatisfy { wanted.isEmpty || byPosition[$0] == wanted[$0 - 1] }
}

private func wildcardKey(_ key: String) -> String {
    let pattern = "%(?:\\d+\\$)?[-+#0]*\\d*(?:\\.\\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[diouxXeEfFgGaAcCsSpn@]"
    guard let rx = try? NSRegularExpression(pattern: pattern) else { return key }
    return rx.stringByReplacingMatches(in: key, range: NSRange(location: 0, length: (key as NSString).length), withTemplate: "\u{0}")
}

// MARK: - Callsigns, locators and kept names

private func looksLikeCallsignOrLocator(_ s: String) -> Bool {
    let call = "^(?:[A-Z]{1,2}|[0-9][A-Z])[0-9][A-Z]{1,4}(/[A-Z0-9]{1,4})?$"
    let loc = "^[A-R]{2}[0-9]{2}([A-Xa-x]{2}([0-9]{2})?)?$"
    for p in [call, loc] where s.range(of: p, options: .regularExpression) != nil { return true }
    return false
}

/// Words of `s` that have the shape of a callsign (0L1ABC, 0X4DK) or of a Maidenhead locator (BL10, JO31ab).
private func callsignShapedWords(in s: String) -> [String] {
    let pattern = "(?<![A-Za-z0-9])(?:(?:[A-Z]{1,2}|[0-9][A-Z])[0-9][A-Z]{1,4}(?:/[A-Z0-9]{1,4})?|[A-R]{2}[0-9]{2}(?:[A-Xa-x]{2}(?:[0-9]{2})?)?)(?![A-Za-z0-9])"
    guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = s as NSString
    return rx.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
}

private let callsignShapedAllowList: Set<String> = ["ON4KST"]   // a chat service, not a station

/// Names written between « » in `s`.
private func quotedNames(in s: String) -> [String] {
    guard let rx = try? NSRegularExpression(pattern: "«([^»]*)»") else { return [] }
    let ns = s as NSString
    return rx.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
}

private func removingQuotedNames(_ s: String) -> String {
    guard let rx = try? NSRegularExpression(pattern: "«[^»]*»") else { return s }
    return rx.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
}

/// The fixed comments of a key that the project rule keeps in English, one per rule.
private let keptCommentLabel = "Kept in English by project rule (radio label, section or protocol term). Reviewed by EA3JIC."
private let keptCommentButton = "Kept in English by project rule (FT8 or FT4 transmit, start or stop button). Reviewed by EA3JIC."
private let keptCommentReadBack = "Kept in English by project rule (the code reads this text back). Reviewed by EA3JIC."
private let keptComments: Set<String> = [keptCommentLabel, keptCommentButton, keptCommentReadBack]

// MARK: - The rules, pinned
// Fixed lists: they are written out here on purpose. A key that is missing from the catalog, or that has lost its
// "shouldTranslate": false, or that has got a translation, fails check 9 even if the catalog still looks consistent.
/// Rule 1: short radio field labels, the Logbook and Station sections, contact and protocol terms, and their case and colon variants (92 keys).
private let ruleOneKept: [String] = [
    "Log", "Station", "Log Table", "SKED", "Quick Log", "Globe & Grids", "Callsign:", "DX callsign", "LIVE UTC",
    "START UTC", "END UTC", "DURATION", "Quick RST:", "CALLSIGN", "Frequency (MHz)", "Band", "Mode", "Submode",
    "RST Sent", "RST Recv", "STX (Sent #)", "SRX (Recv #)", "Sent Exch", "Recv Exch", "Serial", "State / Prov",
    "ARRL Sect", "Name", "Grid", "Country", "My POTA reference", "Contacted POTA reference", "My SOTA reference",
    "Contacted SOTA reference", "STATION", "Log QSO", "Callsign", "Call", "My Call", "Station callsign",
    "Grid Locator", "Band:", "Grid:", "BAND", "MODE", "GRID", "CQ", "DX", "TX", "RX", "PTT", "QTH", "CALL", "CALL:",
    "DX CALL", "LOG QSO", "LOG", "Mode:", "My Callsign:", "RCVD RST", "SENT RST", "DX:", "TX:", "RX:", "Callsign: ",
    "Grid locator", "Tx %lld", "Tx %lld: %@", "=TX", "=RX",
    "CW", "FT4", "FT8", "RTTY", "SSB", "COUNTRY", "Country:", "Duration", "Duration:", "FREQUENCY", "Frequency",
    "Freq", "Freq (MHz)", "Freq:", "FREQ:", "Grid Square:", "Maidenhead Grid Square:", "Time", "dB", "DT",
    "Message", "SNR",
]

/// Rule 5: FT8 and FT4 transmit, start and stop buttons (29 keys).
private let ruleFiveKept: [String] = [
    "HALT TX", "Halt TX", "Cancel TX", "Disarm All TX", "Arm TX", "Queue next TX slot", "Call CQ", "Call Now", "Ans",
    "Answer on %@", "Reply", "Calling...", "Reply to %@", "Call %@ (Reply)", "Reply via YAAM FT8 Modem ⚡️",
    "Reply in WSJT-X ⚡️", "Engage #1 (%@)", "Stop All", "Start All", "Start receive", "Stop receive",
    "Start Listener", "Stop Listener", "Start UDP Listener (Port %@)",
    "Snipe", "Disarm Wait & Pounce Target", "Auto-Pilot: ACTIVE", "Auto-Pilot: OFF",
    "Auto-Pilot Armed — Ready to Call",
]

/// Rule 6: literal SwiftUI keys whose wording the code compares as a value (39 keys).
private let ruleSixKept: [String] = [
    "All bands", "All Bands", "All Modes",
    "All", "Awaiting QSL", "CHECKLOG", "DIGI", "Error", "HIGH", "Hamlib rotctld", "IC-7300MK2", "LOW",
    "Lab599 Discovery TX-500", "LoTW", "LoTW/QRZ Confirmation", "MOBILE", "MULTI-OP", "Needed", "Not worked",
    "PORTABLE", "Progress", "QRP", "QRZ", "QSL Card Request", "ROVER", "SINGLE-OP", "Sent", "Space Weather",
    "Today", "VFO A", "VFO B", "YAAM", "eQSL", "Confirmed", "Unconfirmed", "Watchlist", "LoTW Active",
    "Confirmed (Y)", "Blank",
]

/// Rule 6: texts that the code reads back and that are only String values (Not translated list of L10N-NOTES.md; 120 texts). They are not in the catalog; if one is added it must be kept.
private let readBackStrings: [String] = [
    "1 h", "15 m", "2 h", "4 h", "425", "425 DX News", "A friendly SKED request from {my_callsign} to {callsign}",
    "ALL", "ARNewsline", "ARRL", "ARRL News", "ASSISTED", "Antarctica", "Australia", "Austria", "Brazil",
    "Cape Verde", "Cleared", "Cloud & QSL Services", "Club Log", "Connecting", "Custom", "DX-World",
    "DX-World Weekly", "DXpedition", "Demo", "Digital", "Even", "Exact UTC match", "FIXED", "Failed", "France",
    "Germany", "I hope you're doing well!", "IOTA", "India", "Internal", "International", "Israel", "Italy",
    "LoTW Error", "Loaded", "Log Sync & Imports", "MIXED", "MULTI", "Manual Sync", "NON-ASSISTED", "Netherlands",
    "New", "New Zealand", "Newsline", "Not specified", "ONE", "Odd", "Offline", "Outbox", "Phone", "Poland",
    "QRZ Error", "QRZ Incoming Details", "QRZ Rank Congratulations & QSL", "QSL Card Delivery",
    "Receiver audio interrupted; reconnecting…", "Removed", "Russia", "Safety & AI", "Saudi Arabia", "Saved",
    "Senegal", "Sked Request", "South Africa", "South Korea", "Station & Hardware", "TWO", "To verify",
    "United Kingdom", "United States", "Unknown", "VFO C", "VFO D", "Vietnam", "Wavelog", "authentication",
    "before automatic duplicate cleanup", "cannot find host", "communication error", "complete", "connection lost",
    "connection refused", "connection reset", "could not connect", "days", "error", "failed",
    "hostname could not be found", "hours", "http error", "internet connection", "invalid", "minutes", "network",
    "network is down", "no route to host", "offline", "quota", "saved", "skipped", "socket", "subscription",
    "successfully", "the request timed out", "timed out", "timeout", "token", "unable to upload", "unauthorized",
    "unavailable", "upload failed", "warning", "✅",
]

/// Service names that contain a kept word (Club Log contains Log); they are not the section.
private let serviceNamesWithKeptWords = ["Club Log"]

private func containsWholeWord(_ name: String, in s: String) -> Bool {
    let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}_])"
    return s.range(of: pattern, options: .regularExpression) != nil
}

private func hasLowercaseLetter(_ s: String) -> Bool { s.unicodeScalars.contains { $0.properties.isLowercase } }

/// The bare-name check applies when the English key contains the kept label name as a whole word: a message that
/// names the field must then write it between « ». A key without the word is free to use the ordinary word of the
/// language (Catalan "mode" is an ordinary word).
private func bareNameApplies(name: String, key: String) -> Bool { containsWholeWord(name, in: key) }

// MARK: - The check

@main
struct LocalizationCatalogRegression {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst().filter { $0 != "--list-keys" }
        let root = arguments.first ?? "."
        if CommandLine.arguments.contains("--list-keys") {
            // one line per distinct key the compiler extracts today; an interpolation is written as \(...)
            for key in scanSource(root: root).extracted.keys.sorted() {
                print(key.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\u{0}", with: "\\(...)"))
            }
            return
        }
        var checks = 0
        var failures = 0
        func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            checks += 1
            guard !condition else { return }
            failures += 1
            if failures <= 40 { print("FAIL: \(message())") }
        }

        // 4. the comparison of format specifiers must see a changed order, a lost specifier and a wrong type
        expect(specifiersAgree(key: "A %@ B %lld", value: "X %@ Y %lld"), "self-check: equal specifiers rejected")
        expect(!specifiersAgree(key: "A %@ B %lld", value: "X %lld Y %@"), "self-check: swapped specifiers accepted")
        expect(specifiersAgree(key: "A %@ B %lld", value: "X %2$lld Y %1$@"), "self-check: positional reorder rejected")
        expect(!specifiersAgree(key: "A %@ B %lld", value: "X %2$@ Y %1$lld"), "self-check: positional reorder with wrong types accepted")
        expect(!specifiersAgree(key: "A %@ B %lld", value: "X %1$@ Y %1$lld"), "self-check: repeated position accepted")
        expect(!specifiersAgree(key: "A %@", value: "X"), "self-check: lost specifier accepted")
        expect(!specifiersAgree(key: "A %lld", value: "X %@"), "self-check: wrong type accepted")
        expect(specifiersAgree(key: "100%% %@", value: "100%% %@"), "self-check: percent sign rejected")

        // 8. the bare-name check must apply to a message that names a field and must leave an ordinary word alone
        expect(bareNameApplies(name: "Mode", key: "Clear Band and Mode filters"), "self-check: the bare-name check misses a key that contains Mode")
        expect(!bareNameApplies(name: "Mode", key: "Digital Suite"), "self-check: the bare-name check applies to a key without the word Mode")
        expect(!bareNameApplies(name: "Mode", key: "Moderate"), "self-check: the bare-name check applies to a longer word")

        // 2. regions of the project
        let pbxPath = root + "/YAAM.xcodeproj/project.pbxproj"
        var regions: [String] = []
        if let pbx = try? String(contentsOfFile: pbxPath, encoding: .utf8),
           let start = pbx.range(of: "knownRegions = (") {
            let tail = pbx[start.upperBound...]
            if let end = tail.range(of: ");") {
                regions = tail[..<end.lowerBound].split(separator: "\n")
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t,")) }.filter { !$0.isEmpty }
            }
        }
        print("info: knownRegions in project.pbxproj: \(regions.joined(separator: ", "))")
        for region in ["en", "Base", "ca", "es"] {
            expect(regions.contains(region), "knownRegions of project.pbxproj lacks \(region)")
        }

        // what the code has today
        let scan = scanSource(root: root)
        let interpolated = scan.extracted.keys.filter { $0.contains("\u{0}") }.count
        print("info: \(scan.swiftFiles) Swift files, \(scan.swiftLines) lines; distinct SwiftUI literal keys the compiler extracts today: \(scan.extracted.count) (\(interpolated) with an interpolation)")

        // 1. catalog file
        let catalogPath = root + "/YAAM/Localizable.xcstrings"
        guard let data = FileManager.default.contents(atPath: catalogPath) else {
            expect(false, "YAAM/Localizable.xcstrings does not exist (the project has no .xcstrings, .strings or .lproj)")
            finish(checks, failures)
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data), let catalog = object as? [String: Any] else {
            expect(false, "YAAM/Localizable.xcstrings is not a JSON object")
            finish(checks, failures)
            return
        }
        expect(catalog["version"] as? String == "1.0", "catalog version is \(String(describing: catalog["version"])), expected \"1.0\"")
        expect(catalog["sourceLanguage"] as? String == "en", "catalog sourceLanguage is \(String(describing: catalog["sourceLanguage"])), expected \"en\"")
        guard let strings = catalog["strings"] as? [String: Any], !strings.isEmpty else {
            expect(false, "catalog has no strings")
            finish(checks, failures)
            return
        }
        // JSONSerialization keeps one of two equal keys without a word. In the file as the String Catalog editor
        // writes it, every key of "strings" is a line of four spaces, the key and " : {".
        let text = String(decoding: data, as: UTF8.self)
        let keyLines = text.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.hasPrefix("    \"") && $0.hasSuffix("\" : {") }.count
        expect(keyLines == strings.count, "the file has \(keyLines) key lines but the catalog has \(strings.count) keys: a key is written twice, or the file is not in the editor's layout")

        // the kept names, as they are written on screen (a trailing colon is part of the label style, not of the name)
        var keptKeys: Set<String> = []
        for (key, value) in strings {
            if let entry = value as? [String: Any], entry["shouldTranslate"] as? Bool == false { keptKeys.insert(key) }
        }
        let keptNames = Set(keptKeys.map { $0.hasSuffix(":") ? String($0.dropLast()) : $0 })
        // label names (rule 1) with lower-case letters: a message that names one writes it between « »
        let labelKeys = keptKeys.filter { (strings[$0] as? [String: Any])?["comment"] as? String == keptCommentLabel }
        let bareChecked = Set(labelKeys.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ": ")) })
            .filter { hasLowercaseLetter($0) && $0.count >= 3 }.sorted()

        var notExtractedTranslated = 0
        var extractedKept = 0
        var staleNotes = 0
        for key in strings.keys.sorted() {
            let shown = key.replacingOccurrences(of: "\n", with: "\\n")
            guard let entry = strings[key] as? [String: Any] else { expect(false, "'\(shown)' is not an object"); continue }
            let comment = entry["comment"] as? String ?? ""
            let kept = keptKeys.contains(key)
            if let flag = entry["shouldTranslate"] { expect(flag is Bool, "'\(shown)': shouldTranslate is not true or false") }
            let locs = entry["localizations"] as? [String: Any] ?? [:]
            expect(!key.lowercased().contains("ep2aes") && !key.lowercased().contains("ea3jic"), "'\(shown)': a real callsign in the key")
            expect(callsignShapedWords(in: key).filter { !callsignShapedAllowList.contains($0) }.isEmpty,
                   "'\(shown)': a callsign- or locator-shaped word in the key: \(callsignShapedWords(in: key))")

            // 5. the key is a literal of the code
            let wild = wildcardKey(key)
            let literalPlaces = scan.allLiterals[wild] ?? []
            expect(!literalPlaces.isEmpty, "'\(shown)' is not a string literal of any YAAM/*.swift file (if the label was reworded in the code, rename its key in the catalog)")
            let extractedPlaces = scan.extracted[wild] ?? []
            // 7. a key that is only used as a text field placeholder must not be a callsign or a locator
            if !extractedPlaces.isEmpty && extractedPlaces.allSatisfy({ $0.api == "TextField" || $0.api == "SecureField" }) {
                expect(!looksLikeCallsignOrLocator(key), "'\(shown)' is only used as a text field placeholder and looks like a callsign or locator")
            }

            if kept {
                // 3. kept in English: nothing to translate, one fixed comment
                expect(locs.isEmpty, "'\(shown)' is kept in English but has text for \(locs.keys.sorted())")
                expect(keptComments.contains(comment), "'\(shown)' is kept in English but its comment is not one of the three fixed sentences")
                if !extractedPlaces.isEmpty { extractedKept += 1 }
            } else {
                // 3. translated: Catalan and Spanish, reviewed (translated) or waiting for review (needs_review)
                expect(Set(locs.keys) == ["ca", "es"], "'\(shown)' has languages \(locs.keys.sorted()), expected ca and es")
                expect(!comment.lowercased().contains("ep2aes") && !comment.lowercased().contains("ea3jic"), "'\(shown)': a real callsign in the comment")
                expect(callsignShapedWords(in: comment).filter { !callsignShapedAllowList.contains($0) }.isEmpty,
                       "'\(shown)': a callsign- or locator-shaped word in the comment: \(callsignShapedWords(in: comment))")
                for lang in ["ca", "es"] {
                    guard let loc = locs[lang] as? [String: Any], let unit = loc["stringUnit"] as? [String: Any] else {
                        expect(false, "'\(shown)' \(lang): no stringUnit (the catalog has no plural or device variations)")
                        continue
                    }
                    let value = unit["value"] as? String ?? ""
                    let state = unit["state"] as? String ?? "missing"
                    expect(state == "translated" || state == "needs_review", "'\(shown)' \(lang): state is \(state), expected translated or needs_review")
                    expect(!value.isEmpty, "'\(shown)' \(lang): empty value")
                    expect(specifiersAgree(key: key, value: value),
                           "'\(shown)' \(lang): format specifiers \(specifiers(in: value).map { $0.type }) differ from the key's \(specifiers(in: key).map { $0.type }) (types or order)")
                    expect(value == value.trimmingCharacters(in: .whitespaces) || key != key.trimmingCharacters(in: .whitespaces),
                           "'\(shown)' \(lang): leading or trailing space in the value")
                    expect(!value.lowercased().contains("ep2aes") && !value.lowercased().contains("ea3jic"), "'\(shown)' \(lang): a real callsign in the value")
                    expect(callsignShapedWords(in: value).filter { !callsignShapedAllowList.contains($0) }.isEmpty,
                           "'\(shown)' \(lang): a callsign- or locator-shaped word in the value: \(callsignShapedWords(in: value))")

                    // 8. kept names
                    expect(value.filter { $0 == "«" }.count == value.filter { $0 == "»" }.count, "'\(shown)' \(lang): « and » do not match")
                    for name in quotedNames(in: value) {
                        expect(keptNames.contains(name), "'\(shown)' \(lang): «\(name)» is not a key kept in English")
                    }
                    var bare = removingQuotedNames(value)
                    for service in serviceNamesWithKeptWords { bare = bare.replacingOccurrences(of: service, with: "") }
                    for name in bareChecked where bareNameApplies(name: name, key: key) {
                        expect(!containsWholeWord(name, in: bare), "'\(shown)' \(lang): the kept name \(name) appears without « » (the English key contains it, so the message names the field)")
                    }
                    if key.contains("YAAM") {
                        expect(value.contains("YAAM"), "'\(shown)' \(lang): the word YAAM is lost (the main window is found by it)")
                    }
                    for name in quotedNames(in: comment) {
                        expect(value.contains("«" + name + "»"), "'\(shown)' \(lang): the comment names «\(name)» but the value does not contain it between « »")
                    }
                }
                // 6. a translated key the compiler cannot extract says so in its comment
                let says = comment.lowercased().contains("not extracted yet")
                if let first = extractedPlaces.first {
                    if says { staleNotes += 1; print("note: '\(shown)': the comment says not extracted yet, but \(first.api)(...) takes it as a key at \(first.file):\(first.line); remove the sentence from the comment") }
                } else if !literalPlaces.isEmpty {
                    notExtractedTranslated += 1
                    expect(says, "'\(shown)' is not a SwiftUI key anywhere in the code (first literal at \(literalPlaces[0].file):\(literalPlaces[0].line)) but its comment does not say \"not extracted yet\"")
                }
            }
        }
        // 9. the rules are pinned by the fixed lists above
        for (list, comment, rule) in [(ruleOneKept, keptCommentLabel, "rule 1"), (ruleFiveKept, keptCommentButton, "rule 5"), (ruleSixKept, keptCommentReadBack, "rule 6")] {
            for key in list {
                let shown = key.replacingOccurrences(of: "\n", with: "\\n")
                guard let entry = strings[key] as? [String: Any] else { expect(false, "'\(shown)' (\(rule)) is missing from the catalog"); continue }
                expect(entry["shouldTranslate"] as? Bool == false, "'\(shown)' (\(rule)) must be kept in English: shouldTranslate is not false")
                expect((entry["localizations"] as? [String: Any] ?? [:]).isEmpty, "'\(shown)' (\(rule)) must be kept in English but has ca or es text")
                expect(entry["comment"] as? String == comment, "'\(shown)' (\(rule)) has not the comment of its rule")
            }
        }
        for key in readBackStrings {
            guard let entry = strings[key] as? [String: Any] else { continue }
            expect(entry["shouldTranslate"] as? Bool == false && (entry["localizations"] as? [String: Any] ?? [:]).isEmpty,
                   "'\(key)' is a text that the code reads back (Not translated list of L10N-NOTES.md): it must stay English, with shouldTranslate false and no ca or es text")
        }
        let translated = strings.count - keptKeys.count
        print("info: catalog has \(strings.count) keys: \(keptKeys.count) kept in English (shouldTranslate false), \(translated) translated")
        print("info: translated: \(translated - notExtractedTranslated) are extracted by the compiler today, \(notExtractedTranslated) are String values in the code (comment says: not extracted yet)")
        print("info: kept: \(extractedKept) are extracted by the compiler today, \(keptKeys.count - extractedKept) are String values in the code")
        let byComment = [keptCommentLabel, keptCommentButton, keptCommentReadBack].map { c in keptKeys.filter { (strings[$0] as? [String: Any])?["comment"] as? String == c }.count }
        print("info: kept by rule: \(byComment[0]) of rule 1, \(byComment[1]) of rule 5, \(byComment[2]) of rule 6; pinned: \(ruleOneKept.count + ruleFiveKept.count + ruleSixKept.count) keys and \(readBackStrings.count) read-back texts that are only String values")
        if staleNotes > 0 { print("info: \(staleNotes) comment(s) still say not extracted yet") }

        finish(checks, failures)
    }

    static func finish(_ checks: Int, _ failures: Int) {
        print("LocalizationCatalogRegression: \(checks) checks, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
