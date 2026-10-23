import Foundation

// Regression (Y-001): a DX cluster line is written by anyone. DXSpotParser read its frequency and turned it into a
// bucket with Int(bucketKHz * 10), which stops the app when the frequency is from about 9.2e17 kHz (18 digits)
// upwards, or reads as infinity (a few hundred digits): YAAM stopped on receiving such a line, before anyone tuned to it.
// Now the parser drops a line whose frequency is not usable (FrequencyBounds), and keeps every real spot as before.
// It runs the real parser (YAAM/OperatorModels.swift). Without the fix this program stops on the first huge line,
// so the suite fails. Build and run from the repository root (Tests/run-cw-safety-regressions.sh does it).
// Example callsigns are EA3JIC and EP2AES only.

// Stand-ins, as in Tests/BandAdvisorClusterRegression.swift: only the members the band advisor and band plan use.
nonisolated public struct WSJTXLiveDecode: Identifiable, Sendable {
    public var id = UUID()
    public var snr: Int32
    public var receivedAt: Date
}
final class RigControlClient {
    func setFrequencyHz(_ hz: UInt64) {}
    func setMode(_ mode: String, passbandHz: Int) {}
}
nonisolated struct QSORecordModel {
    var fields: [String: String] = [:]
    var isConfirmed = false
    subscript(key: String) -> String { fields[key] ?? "" }
}

@main
struct DXSpotHugeFrequencyRegression {
    static var failures = 0

    static func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "PASS" : "FAIL") \(label)")
        if !condition { failures += 1 }
    }

    static func main() {
        // A real spot is parsed as before.
        let real = DXSpotParser.parse(line: "DX de EA3JIC:     14025.0  EP2AES       CW 599            1830Z")
        check(real?.callsign == "EP2AES" && real?.frequencyKHz == 14025.0, "a real spot is parsed as before")
        check(DXSpotParser.parse(line: "DX de EA3JIC:  135.7  EP2AES  LF 1830Z")?.frequencyKHz == 135.7,
              "a 136 kHz spot is kept")

        // Lines that stopped YAAM on arrival: dropped, and the program goes on.
        let huge = String(repeating: "9", count: 19)
        check(DXSpotParser.parse(line: "DX de EA3JIC: \(huge) EP2AES CW 1830Z") == nil, "a 19-digit frequency is dropped")
        check(DXSpotParser.parse(line: "DX de EA3JIC: 930000000000000000 EP2AES CW 1830Z") == nil,
              "an 18-digit frequency (9.3e17 kHz, enough to stop Int(bucketKHz * 10)) is dropped")
        let infinite = String(repeating: "9", count: 400)
        check(DXSpotParser.parse(line: "DX de EA3JIC: \(infinite) EP2AES CW 1830Z") == nil,
              "a frequency that reads as infinity (400 digits) is dropped")
        check(DXSpotParser.parse(line: "DX de EA3JIC: 300000001 EP2AES CW 1830Z") == nil, "a frequency above 300 GHz is dropped")
        check(DXSpotParser.parse(line: "DX de EA3JIC: 0 EP2AES CW 1830Z") == nil, "a 0 kHz frequency is dropped")

        if failures > 0 { print("DX spot huge frequency regression FAILED (\(failures))"); exit(1) }
        print("DX spot huge frequency regression passed")
    }
}
