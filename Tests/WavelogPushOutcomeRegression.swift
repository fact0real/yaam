import Foundation

// Standalone, no server or account needed:
//   swiftc -parse-as-library Tests/WavelogPushOutcomeRegression.swift YAAM/WavelogPushOutcome.swift -o /tmp/wpo && /tmp/wpo
// Reply bodies follow Wavelog's Api.php qso() (dev branch).
@main
struct WavelogPushOutcomeRegression {
    static func classify(_ code: Int, _ body: String) -> WavelogPushOutcome {
        WavelogPushOutcome.classify(statusCode: code, body: Data(body.utf8))
    }

    static func main() {
        // Created
        precondition(classify(201, #"{"status":"created","type":"adif","string":"","adif_count":1,"adif_errors":0,"messages":[""]}"#) == .success)
        precondition(classify(200, #"{"status":"successful"}"#) == .success)

        // Duplicate: Wavelog answers 400 "abort" with an empty first message
        precondition(classify(400, #"{"status":"abort","type":"adif","string":"","adif_count":1,"adif_errors":1,"messages":["","Date/Time: 2026-09-01 12:00 Callsign: K1ABC Band: 20m Duplicate for K1ABC"]}"#) == .duplicate)

        // Wrong key / read-only key
        precondition(classify(401, #"{"status":"failed","reason":"missing or wrong api key"}"#) == .rejected("missing or wrong api key"))
        precondition(classify(403, #"{"status":"failed","reason":"API key does not have write permissions"}"#) == .rejected("API key does not have write permissions"))

        // 2xx replies the old pushQSO counted as success
        precondition(classify(200, #"{"status":"failed","reason":"wrong JSON"}"#) == .rejected("wrong JSON"))
        precondition(classify(201, #"{"status":"created","type":"adif","string":"","adif_count":0,"adif_errors":0,"messages":[""]}"#) == .rejected("Wavelog did not import any QSO from the upload"))
        for body in ["<html>Login</html>", ""] {
            guard case .rejected = classify(200, body) else { preconditionFailure("2xx with \(body) must not count as pushed") }
        }

        // Import error that is not a duplicate
        precondition(classify(400, #"{"status":"abort","adif_errors":1,"messages":["","Station profile does not match"]}"#) == .rejected("Station profile does not match"))

        // Retry later only for transport/server trouble
        for code in [408, 429, 500, 502, 503] {
            guard case .networkError = classify(code, "") else { preconditionFailure("HTTP \(code) must be retryable") }
        }
        precondition(WavelogPushOutcome.shouldTryFallbackEndpoint(statusCode: 404))
        precondition(!WavelogPushOutcome.shouldTryFallbackEndpoint(statusCode: 401))
        precondition(WavelogPushOutcome.duplicate.isDelivered && !WavelogPushOutcome.notConfigured.isDelivered)

        print("Wavelog push outcome regression tests passed.")
    }
}
