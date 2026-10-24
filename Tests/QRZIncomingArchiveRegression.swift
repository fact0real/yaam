import Foundation

@main struct QRZIncomingArchiveRegression {
    static func main() throws {
        func request(_ summary: String, key: String = "42") -> QRZIncomingConfirmation {
            QRZIncomingConfirmation(callsign: "W1AW", qsoDate: "20261020", requestedAt: "", rawSummary: summary, qsoID: key)
        }
        var archive = QRZIncomingRecoveryArchive()
        archive.refresh([request("First page summary")])
        archive.refresh([request("Updated summary")])
        precondition(archive.requests.count == 1 && archive.requests[0].rawSummary == "Updated summary")
        archive.refresh([])
        precondition(archive.requests.count == 1 && archive.lastReturnedKeys.isEmpty, "QRZ disappearance must not discard a recovery case")
        let restored = try JSONDecoder().decode(QRZIncomingRecoveryArchive.self, from: JSONEncoder().encode(archive))
        precondition(restored == archive, "Cases survive restart without claiming QRZ presence")
        var otherStation = QRZIncomingRecoveryArchive()
        otherStation.refresh([request("Different station", key: "99")])
        precondition(!otherStation.requests.contains { $0.recoveryKey == "42" })
        archive.remove(request("Other summary"))
        precondition(archive.requests.isEmpty)
        let legacy = #"{"callsign":"W1AW","qsoDate":"20261020","requestedAt":"","rawSummary":"Legacy"}"#.data(using: .utf8)!
        let old = try JSONDecoder().decode(QRZIncomingConfirmation.self, from: legacy)
        precondition(old.recoveryKey == old.id && old.qsoID.isEmpty)
        print("QRZ Incoming archive regression passed: stable IDs, disappearing requests, restart and legacy requests")
    }
}
