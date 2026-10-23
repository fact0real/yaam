import Foundation

// Regression (Y-001): a spot's comment comes from the DX cluster, written by anyone. QSXCommentParser reads a split from
// it ("UP 5", "DN 2", "QSX 14025"), and PileupSniperEngine turns it into a transmit frequency that the call
// intelligence panel and the operator desk tune with UInt64(kHz * 1000). A number such as "UP 99999999999999999999" or
// "DN 99999999999" gave a frequency that stops YAAM there. Now a split whose frequencies are not usable radio frequencies
// (FrequencyBounds) is read as no split, and every real split is read as before. The engine's steps from those offsets
// could still go below 0 kHz (three "DN" spots near the DX frequency); then it gives no solution.
// Build and run from the repository root (Tests/run-cw-safety-regressions.sh does it). The operator is EA3JIC.
// Stand-ins, as in Tests/BandAdvisorClusterRegression.swift: only the members OperatorModels.swift uses.
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
/// Stand-in with only the fields PileupSniperEngine reads; the real one lives in SpotArchiveDatabase.swift (SQLite).
struct ArchivedSpotRecord {
    let callsign: String
    let comment: String
    let spotter: String
    let spottedAt: Date
}

@main
struct QSXCommentBoundsRegression {
    nonisolated(unsafe) static var failures = 0
    static func check(_ condition: Bool, _ label: String) {
        print("\(condition ? "PASS" : "FAIL") \(label)")
        if !condition { failures += 1 }
    }
    /// Whether every frequency the parsed split leads to converts to hertz without stopping the app.
    static func convertible(_ p: QSXCommentParser.ParsedComment, base: Double) -> Bool {
        let khz = [p.lowOffsetKHz, p.highOffsetKHz].compactMap { $0.map { base + $0 } } + [p.exactFrequencyKHz].compactMap { $0 }
        return khz.allSatisfy { $0.isFinite && $0 > 0 && $0 * 1000 < 1.8e19 }
    }
    static func main() {
        let base = 14_024.0
        // Real splits, as before.
        let up = QSXCommentParser.parse(comment: "UP 5", dxBaseFreqKHz: base)
        check(up.isSplit && up.highOffsetKHz == 5 && up.exactFrequencyKHz == 14_029, "UP 5 is read as before")
        let range = QSXCommentParser.parse(comment: "UP 5-10", dxBaseFreqKHz: base)
        check(range.isSplit && range.isRange && range.lowOffsetKHz == 5 && range.highOffsetKHz == 10, "UP 5-10 is read as before")
        let down = QSXCommentParser.parse(comment: "listening down 2", dxBaseFreqKHz: base)
        check(down.isSplit && down.exactFrequencyKHz == 14_022, "DN 2 is read as before")
        let qsx = QSXCommentParser.parse(comment: "qsx 14025.4 loud", dxBaseFreqKHz: base)
        check(qsx.isSplit && qsx.exactFrequencyKHz == 14_025.4, "QSX 14025.4 is read as before")
        check(QSXCommentParser.parse(comment: "now simplex!!", dxBaseFreqKHz: base).isSimplex, "SIMPLEX is read as before")
        // Numbers from the cluster that would stop YAAM where the split is tuned.
        for comment in ["UP 99999999999999999999", "UP 5-99999999999999999999", "DN 99999999999", "DOWN 1-99999999999",
                        "QSX 99999999999999999999", "WKD +99999999999999999999"] {
            let p = QSXCommentParser.parse(comment: comment, dxBaseFreqKHz: base)
            check(!p.isSplit && convertible(p, base: base), "\"\(comment)\" is read as no split, so nothing unusable is tuned")
        }
        // The engine steps from the offsets it read: three "DN" spots close to the DX frequency stepped below 0 kHz.
        let now = Date()
        let downs = [("DN 14020", 300.0), ("DN 14022", 200.0), ("DN 14023.5", 100.0)].map {
            ArchivedSpotRecord(callsign: "EP2AES", comment: $0.0, spotter: "EA3JIC", spottedAt: now.addingTimeInterval(-$0.1))
        }
        let stepped = PileupSniperEngine.analyze(dxCallsign: "EP2AES", dxRxFrequencyKHz: base, archivedSpots: downs)
        check(stepped.map { $0.recommendedTxKHz > 0 && $0.recommendedTxKHz * 1000 < 1.8e19 } ?? true,
              "three DN spots near the DX frequency give no transmit frequency below 0 kHz")
        let usual = PileupSniperEngine.analyze(dxCallsign: "EP2AES", dxRxFrequencyKHz: base,
                                               archivedSpots: [ArchivedSpotRecord(callsign: "EP2AES", comment: "UP 5", spotter: "EA3JIC", spottedAt: now)])
        check(usual?.isSplit == true && (usual?.recommendedTxKHz ?? 0) > base, "a usual UP 5 still gives a split above the DX frequency")

        if failures > 0 { print("QSX comment bounds regression FAILED (\(failures))"); exit(1) }
        print("QSX comment bounds regression passed")
    }
}
