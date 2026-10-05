import Foundation

struct WebSDRReplyPlan: Equatable {
    let partner: String
    let draft: String
    let needsLocalReport: Bool
    let explanation: String
}

nonisolated enum WebSDRReplyGuard {
    static func targetIsOwnCallsign(_ target: String, ownCallsign: String) -> Bool {
        let own = normalized(ownCallsign)
        return !own.isEmpty && own != "DEFAULT" && normalized(target) == own
    }

    static func identityIssue(target: String, ownCallsign: String) -> String? {
        if targetIsOwnCallsign(target, ownCallsign: ownCallsign) { return nil }
        let own = normalized(ownCallsign)
        if own.isEmpty || own == "DEFAULT" {
            return "Set your callsign in Settings > Stations before queuing a reply."
        }
        return "Replies are sent as your own station (\(own))."
    }

    static func dialIssue(dialHz: UInt64, ft8DialsHz: [UInt64]) -> String? {
        guard ft8DialsHz.contains(dialHz) else {
            return "The WebSDR dial is not an FT8 band preset. Use band preset, start receive and pick the message again."
        }
        return nil
    }

    static func retuneIssue(plannedDialHz: Int?, currentDialHz: Int) -> String? {
        guard plannedDialHz == currentDialHz else {
            return "The receiver was retuned after this reply was prepared. Pick the message again."
        }
        return nil
    }

    private static func normalized(_ callsign: String) -> String {
        callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
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
