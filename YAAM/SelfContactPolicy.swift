import Foundation

nonisolated enum SelfContactPolicy {
    static func isSelfContact(fields: [String: String], profileCallsign: String = "") -> Bool {
        let contact = (fields["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let explicitStation = (fields["STATION_CALLSIGN"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let profileStation = profileCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let station = explicitStation.isEmpty ? profileStation : explicitStation
        return !contact.isEmpty && !station.isEmpty && station != "DEFAULT" && station != "NOCALL" && contact == station
    }
}
