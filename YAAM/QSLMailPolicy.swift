import Foundation

/// Card delivery describes our recorded contact; it never establishes the other operator's confirmation.
nonisolated enum QSLMailPolicy {
    static func requiresCard(template: String) -> Bool {
        ["QSL Card Delivery", "QRZ Rank Congratulations & QSL"].contains(template)
    }

    static func rank(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !clean.isEmpty, clean.allSatisfy(\.isNumber), let value = Int(clean), value > 0 else { return nil }
        return "#" + value.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    static func rankSubject(hasRanks: Bool, bandMention: String, station: String) -> String {
        let purpose = hasRanks ? "QRZ Rank Congratulations & QSL" : "QSL & operating advice"
        return "\(purpose)\(bandMention) - \(station)"
    }

    static func rankParagraph(qso: String?, band: String?, dxcc: String?) -> String {
        let rows = [("QSO World Rank", qso), ("Bands World Rank", band), ("DXCC World Rank", dxcc)]
            .compactMap { label, raw in rank(raw).map { "  • \(label): \($0)" } }
        guard !rows.isEmpty else {
            return "I do not have verified QRZ rank figures available for this message, so I have left them out. I would still love to learn about your operating experience."
        }
        return "The QRZ rank figures available in YAAM are shown below (they may have changed since retrieval):\n"
            + rows.joined(separator: "\n")
            + "\n\nCongratulations on your progress! What habits, operating style, or station setup have helped you?"
    }
}
