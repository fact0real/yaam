import Foundation

struct QSLCardStationInfo {
    let callsign: String
    let grid: String
    let radio: String
    let antenna: String
    let powerWatts: Int
    var antennaHeightMeters: Int = 0
    var qth = ""
    var country = ""
    var cqZone = ""
    var ituZone = ""

    init(callsign: String, profile: StationProfile?) {
        self.callsign = callsign
        grid = profile?.normalizedGrid ?? ""
        radio = profile?.radioModel ?? ""
        antenna = profile?.antennaDescription ?? ""
        powerWatts = profile?.powerWatts ?? 0
        antennaHeightMeters = profile?.antennaHeightMeters ?? 0
        qth = profile?.qth ?? ""
        country = profile?.country ?? ""
        cqZone = profile?.cqZone ?? ""
        ituZone = profile?.ituZone ?? ""
    }

    var flag: String {
        let clean = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        let result = countryToFlag(clean, allowCallsignFallback: false)
        return result == "🌐" ? "" : result
    }

    var locationLine: String {
        let place = [qth, country].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: ", ")
        var parts = [String]()
        if !place.isEmpty { parts.append("QTH: \(place)") }
        if !grid.isEmpty { parts.append("GRID: \(grid.uppercased())") }
        if let zone = Int(cqZone.trimmingCharacters(in: .whitespacesAndNewlines)), (1...40).contains(zone) {
            parts.append("CQ: \(zone)")
        }
        if let zone = Int(ituZone.trimmingCharacters(in: .whitespacesAndNewlines)), (1...90).contains(zone) {
            parts.append("ITU: \(zone)")
        }
        return parts.joined(separator: " · ")
    }
}
