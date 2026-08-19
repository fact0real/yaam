//
//  StationProfile.swift
//  YAAM
//

import Foundation

nonisolated struct StationProfile: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var callsign: String
    var qth: String
    var grid: String
    var latitude: String
    var longitude: String
    var dxccCode: String
    var country: String
    var cqZone: String
    var ituZone: String
    var radioModel: String
    var powerWatts: Int
    var antennaDescription: String
    var antennaHeightMeters: Int
    var validFrom: Date?
    var validTo: Date?
    var lotwStationLocation: String
    var eqslQTHNickname: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Home Station",
        callsign: String = "",
        qth: String = "",
        grid: String = "",
        latitude: String = "",
        longitude: String = "",
        dxccCode: String = "",
        country: String = "",
        cqZone: String = "",
        ituZone: String = "",
        radioModel: String = "",
        powerWatts: Int = 100,
        antennaDescription: String = "",
        antennaHeightMeters: Int = 10,
        validFrom: Date? = nil,
        validTo: Date? = nil,
        lotwStationLocation: String = "",
        eqslQTHNickname: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.callsign = callsign
        self.qth = qth
        self.grid = grid
        self.latitude = latitude
        self.longitude = longitude
        self.dxccCode = dxccCode
        self.country = country
        self.cqZone = cqZone
        self.ituZone = ituZone
        self.radioModel = radioModel
        self.powerWatts = powerWatts
        self.antennaDescription = antennaDescription
        self.antennaHeightMeters = antennaHeightMeters
        self.validFrom = validFrom
        self.validTo = validTo
        self.lotwStationLocation = lotwStationLocation
        self.eqslQTHNickname = eqslQTHNickname
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var normalizedCallsign: String {
        callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var displayTitle: String {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanName.isEmpty { return normalizedCallsign.isEmpty ? "Unnamed Station" : normalizedCallsign }
        return normalizedCallsign.isEmpty ? cleanName : "\(cleanName) · \(normalizedCallsign)"
    }

    var normalizedGrid: String {
        grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    func isValid(on date: Date) -> Bool {
        if let validFrom, date < validFrom { return false }
        if let validTo, date > validTo { return false }
        return true
    }

    mutating func normalize() {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        callsign = normalizedCallsign
        qth = qth.trimmingCharacters(in: .whitespacesAndNewlines)
        grid = normalizedGrid
        latitude = latitude.trimmingCharacters(in: .whitespacesAndNewlines)
        longitude = longitude.trimmingCharacters(in: .whitespacesAndNewlines)
        dxccCode = dxccCode.trimmingCharacters(in: .whitespacesAndNewlines)
        country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        cqZone = cqZone.trimmingCharacters(in: .whitespacesAndNewlines)
        ituZone = ituZone.trimmingCharacters(in: .whitespacesAndNewlines)
        radioModel = radioModel.trimmingCharacters(in: .whitespacesAndNewlines)
        antennaDescription = antennaDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        lotwStationLocation = lotwStationLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        eqslQTHNickname = eqslQTHNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        powerWatts = min(max(powerWatts, 1), 1500)
        antennaHeightMeters = min(max(antennaHeightMeters, 0), 500)
        updatedAt = Date()
    }

    func validationMessage() -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Profile name is required."
        }
        if normalizedCallsign.isEmpty {
            return "Station callsign is required."
        }
        if !normalizedGrid.isEmpty, GridLocator.fourCharacterGrid(from: normalizedGrid) == nil {
            return "Grid Locator must begin with a valid Maidenhead square such as LM55."
        }
        if let validFrom, let validTo, validTo < validFrom {
            return "The validity end date cannot be earlier than the start date."
        }
        return nil
    }
}

nonisolated struct PersistedQSO: Sendable {
    let id: UUID
    let index: Int
    let fields: [String: String]
}

nonisolated struct BackupSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let createdAt: Date
    let reason: String
    let sizeBytes: Int64
}

nonisolated struct DatabaseAuditEvent: Identifiable, Sendable {
    let id: Int64
    let date: Date
    let action: String
    let detail: String
    let stationProfileID: UUID?
}
