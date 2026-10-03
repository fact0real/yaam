import Foundation

struct EmailHistoryEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let date: Date
    let callsign: String
    let email: String
    let subject: String
    let status: String
    var kind: String? = nil
    var sked: SKEDMailDetails? = nil

    var countsAsQSL: Bool {
        status == "Sent" && !["SKED", "QRZ_INCOMING_DETAILS"].contains(kind?.uppercased() ?? "")
    }
}
