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
        switch mode {
        case .quick:
            let terms = normalized(query)
                .split(separator: " ")
                .map(String.init)
            return !terms.isEmpty && terms.allSatisfy { document.quickText.contains($0) }

        case .callsign:
            let callsigns = query
                .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" || $0 == "|" })
                .map { callsignKey(String($0)) }
                .filter { !$0.isEmpty }
            return callsigns.contains(document.callsign)

        case .name:
            let alternatives = query
                .split(whereSeparator: { $0 == ";" || $0 == "|" })
                .map { normalized(String($0)).split(separator: " ").map(String.init) }
                .filter { !$0.isEmpty }
            return alternatives.contains { terms in
                terms.allSatisfy { document.nameText.contains($0) }
            }
        }
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

    private static func callsignKey(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "/" }
    }
}
