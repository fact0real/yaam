import Foundation

nonisolated enum LogSearchMode: String, CaseIterable, Identifiable, Sendable {
    case quick
    case callsign
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick:
            return "Quick Search"
        case .callsign:
            return "Exact Callsign"
        case .name:
            return "Contact Name"
        }
    }

    var shortTitle: String {
        switch self {
        case .quick:
            return "Any"
        case .callsign:
            return "Call"
        case .name:
            return "Name"
        }
    }

    var systemImage: String {
        switch self {
        case .quick:
            return "magnifyingglass"
        case .callsign:
            return "antenna.radiowaves.left.and.right"
        case .name:
            return "person.text.rectangle"
        }
    }

    var placeholder: String {
        switch self {
        case .quick:
            return "Search log..."
        case .callsign:
            return "Exact callsign..."
        case .name:
            return "Contact name..."
        }
    }
}

nonisolated struct LogSearchDocument: Sendable {
    let quickText: String
    let callsign: String
    let nameText: String
}

nonisolated enum LogSearchEngine {
    static func makeDocument(
        fields: [String: String],
        country: String,
        continent: String,
        countryFlag: String
    ) -> LogSearchDocument {
        let nameValues = fields.compactMap { key, value -> String? in
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard normalizedKey == "NAME" ||
                    normalizedKey == "OPERATOR" ||
                    normalizedKey.hasSuffix("_NAME") else {
                return nil
            }
            return value
        }

        return LogSearchDocument(
            quickText: normalized((Array(fields.values) + [country, continent, countryFlag]).joined(separator: " ")),
            callsign: callsignKey(fields["CALL"] ?? ""),
            nameText: normalized(nameValues.joined(separator: " "))
        )
    }

    static func matches(_ document: LogSearchDocument, query: String, mode: LogSearchMode) -> Bool {
        let prepared = PreparedLogSearchQuery(query: query, mode: mode)
        return prepared.matches(document)
    }

    static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func callsignKey(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "/" }
    }
}

// MARK: - Precompiled High Performance Search Query
nonisolated struct PreparedLogSearchQuery: Sendable {
    let rawQuery: String
    let mode: LogSearchMode
    let terms: [String]
    let callsigns: Set<String>
    let nameAlternatives: [[String]]

    init(query: String, mode: LogSearchMode) {
        self.rawQuery = query
        self.mode = mode
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .quick:
            self.terms = LogSearchEngine.normalized(trimmed)
                .split(separator: " ")
                .map(String.init)
            self.callsigns = []
            self.nameAlternatives = []
        case .callsign:
            let list = trimmed
                .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" || $0 == "|" })
                .map { LogSearchEngine.callsignKey(String($0)) }
                .filter { !$0.isEmpty }
            self.callsigns = Set(list)
            self.terms = []
            self.nameAlternatives = []
        case .name:
            self.nameAlternatives = trimmed
                .split(whereSeparator: { $0 == ";" || $0 == "|" })
                .map { LogSearchEngine.normalized(String($0)).split(separator: " ").map(String.init) }
                .filter { !$0.isEmpty }
            self.terms = []
            self.callsigns = []
        }
    }

    func matches(_ document: LogSearchDocument) -> Bool {
        switch mode {
        case .quick:
            return !terms.isEmpty && terms.allSatisfy { document.quickText.contains($0) }
        case .callsign:
            return callsigns.contains(document.callsign)
        case .name:
            return nameAlternatives.contains { terms in
                terms.allSatisfy { document.nameText.contains($0) }
            }
        }
    }
}

// MARK: - English-Only Input & Keyboard Transliteration Filter
nonisolated enum EnglishSearchInputFilter {
    /// Persian and Arabic digit translation table to standard English digits
    private static let digitMap: [Character: Character] = [
        "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
        "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
        "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
        "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9"
    ]

    /// Standard Persian keyboard QWERTY key mapping for accidental Persian typing
    private static let persianToEnglishMap: [Character: Character] = [
        "ض": "q", "ص": "w", "ث": "e", "ق": "r", "ف": "t", "غ": "y", "ع": "u", "ه": "i", "خ": "o", "ح": "p",
        "ج": "[", "چ": "]", "ش": "a", "س": "s", "ی": "d", "ي": "d", "ب": "f", "ل": "g", "ا": "h", "آ": "h",
        "ت": "j", "ن": "k", "م": "l", "ک": ";", "ك": ";", "گ": "'", "ظ": "z", "ط": "x", "ز": "c", "ر": "v",
        "ذ": "b", "د": "n", "پ": "m", "و": ",", "ژ": "C"
    ]

    /// Characters permitted in radio search queries
    private static let allowedPunctuation: Set<Character> = [
        " ", "/", "-", ".", "@", "?", "*", ";", ",", "_", ":", "+", "[", "]", "(", ")"
    ]

    /// Sanitizes search input by:
    /// 1. Converting Persian/Arabic digits to English digits (0-9)
    /// 2. Transliterating Persian keyboard characters to their English QWERTY equivalents
    /// 3. Restricting all output exclusively to ASCII characters (letters, numbers, radio search symbols)
    static func sanitize(_ input: String) -> String {
        var output = ""
        output.reserveCapacity(input.count)

        for char in input {
            if let englishDigit = digitMap[char] {
                output.append(englishDigit)
            } else if let qwertyChar = persianToEnglishMap[char] {
                output.append(qwertyChar.uppercased())
            } else if char.isASCII && (char.isLetter || char.isNumber || allowedPunctuation.contains(char)) {
                output.append(char)
            }
        }
        return output
    }
}
