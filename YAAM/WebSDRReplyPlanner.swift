import Foundation

struct WebSDRReplyPlan: Equatable {
    let partner: String
    let draft: String
    let needsLocalReport: Bool
    let explanation: String
}

/// A WebSDR decode identifies the other station's words, but its audio dBFS
/// cannot supply the operator's received RF report. Keep that field editable.
enum WebSDRReplyPlanner {
    static func plan(for decodedText: String, targetCallsign: String) -> WebSDRReplyPlan? {
        let target = targetCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let words = decodedText.uppercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 3, !target.isEmpty, words[0] == target,
              words[1] != target, isCallsign(words[1]) else { return nil }
        let partner = words[1]
        let payload = words.dropFirst(2).joined(separator: " ")
        let prefix = "\(partner) \(target)"
        switch payload {
        case "73":
            return nil
        case "RR73", "RRR":
            return .init(partner: partner, draft: "\(prefix) 73", needsLocalReport: false,
                         explanation: "Final 73 after the partner's acknowledgement")
        default:
            if payload.range(of: #"^R[+-]\d{2}$"#, options: .regularExpression) != nil {
                return .init(partner: partner, draft: "\(prefix) RR73", needsLocalReport: false,
                             explanation: "Acknowledge the partner's received report")
            }
            if payload.range(of: #"^[+-]\d{2}$"#, options: .regularExpression) != nil {
                return .init(partner: partner, draft: "\(prefix) R[REPORT]", needsLocalReport: true,
                             explanation: "Enter your actual RF report before transmitting")
            }
            if payload.range(of: #"^[A-R]{2}[0-9]{2}([A-X]{2})?$"#, options: .regularExpression) != nil {
                return .init(partner: partner, draft: "\(prefix) [REPORT]", needsLocalReport: true,
                             explanation: "Enter your actual RF report before transmitting")
            }
            return nil
        }
    }

    static func isReady(_ draft: String, for plan: WebSDRReplyPlan, targetCallsign: String) -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard text.hasPrefix("\(plan.partner) \(targetCallsign.uppercased()) "),
              !text.contains("["), !text.contains("]") else { return false }
        if plan.needsLocalReport {
            let suffix = text.split(separator: " ").last.map(String.init) ?? ""
            let expectedPattern = plan.draft.hasSuffix("R[REPORT]")
                ? #"^R[+-]\d{2}$"# : #"^[+-]\d{2}$"#
            return suffix.range(of: expectedPattern, options: .regularExpression) != nil
        }
        return text == plan.draft
    }

    private static func isCallsign(_ value: String) -> Bool {
        value.count >= 3 && value.rangeOfCharacter(from: .decimalDigits) != nil &&
        value.rangeOfCharacter(from: .letters) != nil &&
        value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "/") }
    }
}
