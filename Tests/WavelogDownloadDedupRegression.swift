import Foundation

// Standalone: swiftc -parse-as-library Tests/WavelogDownloadDedupRegression.swift YAAM/QSOIdentity.swift -o /tmp/wdd && /tmp/wdd
@main
struct WavelogDownloadDedupRegression {
    static func qso(_ call: String, _ time: String, _ band: String = "20M", _ mode: String = "SSB") -> [String: String] {
        ["CALL": call, "QSO_DATE": "20260820", "TIME_ON": time, "BAND": band, "MODE": mode]
    }

    static func main() {
        let local = [qso("W1AW", "101500")]

        // Second QSO with the same station, day and band: other time or other mode must be imported
        let remote = [qso("W1AW", "101500"), qso("W1AW", "183000", "20M", "CW"), qso("W1AW", "183000", "40M", "CW"), qso("W1AW", "101530")]
        let fresh = QSOIdentity.newRecords(remote, existing: local, toleranceSeconds: 300)
        precondition(fresh.count == 2, "expected the 20M CW and 40M CW QSOs, got \(fresh.count)")
        precondition(fresh[0]["MODE"] == "CW" && fresh[0]["BAND"] == "20M" && fresh[1]["BAND"] == "40M")

        // Same station twice on the same day and band, hours apart, into an empty log: both kept
        precondition(QSOIdentity.newRecords([qso("W1AW", "101500"), qso("W1AW", "183000")], existing: [], toleranceSeconds: 300).count == 2)

        // A true repeat inside one download collapses
        precondition(QSOIdentity.newRecords([qso("W1AW", "101500"), qso("W1AW", "101500")], existing: [], toleranceSeconds: 300).count == 1)

        // FT8 remote vs DATA local is the same QSO; a record without CALL is skipped
        precondition(QSOIdentity.newRecords([qso("W1AW", "101520", "20M", "FT8")], existing: [qso("W1AW", "101500", "20M", "DATA")], toleranceSeconds: 300).isEmpty)
        precondition(QSOIdentity.newRecords([qso("", "101500")], existing: [], toleranceSeconds: 300).isEmpty)

        print("Wavelog download dedup regression tests passed.")
    }
}
