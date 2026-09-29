import Foundation

/// What really happened when one QSO was pushed to Wavelog / Cloudlog (`api/qso`).
/// Pure Foundation, so it can be regression-tested standalone:
///   swiftc -parse-as-library Tests/WavelogPushOutcomeRegression.swift YAAM/WavelogPushOutcome.swift -o /tmp/wpo && /tmp/wpo
/// Replies handled (Wavelog Api.php, qso()): 201 {"status":"created","adif_count":N,...};
/// 400 {"status":"abort","messages":[..., "... Duplicate for ..."]}; 401/403 {"status":"failed","reason":...};
/// 200 {"status":"failed","reason":"wrong JSON"}.
nonisolated enum WavelogPushOutcome: Equatable, Sendable {
    case success
    case duplicate                 // the server already has this QSO
    case notConfigured             // no URL / API key, or auto-push off: nothing was sent
    case rejected(String)          // the server said no; sending the same QSO again will not help
    case networkError(String)      // transport error, 408, 429 or 5xx: worth retrying later

    var isDelivered: Bool { self == .success || self == .duplicate }

    var message: String {
        switch self {
        case .success: return "Pushed"
        case .duplicate: return "Already in Wavelog"
        case .notConfigured: return "Wavelog is not configured"
        case .rejected(let reason), .networkError(let reason): return reason
        }
    }

    /// The server has no such endpoint: try the next one (api/qso -> index.php/api/qso).
    static func shouldTryFallbackEndpoint(statusCode: Int) -> Bool {
        statusCode == 404 || statusCode == 405
    }

    static func classify(statusCode: Int, body: Data) -> WavelogPushOutcome {
        if statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode) {
            return .networkError("HTTP error \(statusCode)")
        }

        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let status = (json?["status"] as? String)?.lowercased() ?? ""
        let messages = ((json?["messages"] as? [String]) ?? [])
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let reason = (json?["reason"] as? String) ?? messages.first

        if !messages.isEmpty, messages.allSatisfy({ $0.localizedCaseInsensitiveContains("duplicate") }) {
            return .duplicate
        }

        if (200...299).contains(statusCode) {
            if status == "created" || status == "successful" {
                if let count = json?["adif_count"] as? Int, count == 0 {
                    return .rejected("Wavelog did not import any QSO from the upload")
                }
                if let errors = json?["adif_errors"] as? Int, errors > 0 {
                    return .rejected(reason ?? "Wavelog reported \(errors) import error(s)")
                }
                return .success
            }
            if json == nil {
                return .rejected("Unexpected reply (not a Wavelog API response). Check the server URL.")
            }
        }

        if let reason { return .rejected(reason) }
        return .rejected(status.isEmpty ? "HTTP error \(statusCode)" : "Wavelog replied \"\(status)\"")
    }
}
