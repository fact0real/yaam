//
//  POTASOTAModels.swift
//  YAAM
//
//  Domain models for POTA (Parks on the Air) and SOTA (Summits on the Air)
//  field operations, live spots, offline directory lookups, and session tracking.
//

import Foundation
import CoreLocation

// MARK: - Portable Field Program
public enum FieldProgramType: String, CaseIterable, Identifiable, Codable, Sendable {
    case pota = "POTA"
    case sota = "SOTA"
    case wwff = "WWFF"
    case iota = "IOTA"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pota: return "Parks on the Air (POTA)"
        case .sota: return "Summits on the Air (SOTA)"
        case .wwff: return "World Wide Flora & Fauna (WWFF)"
        case .iota: return "Islands on the Air (IOTA)"
        }
    }

    public var icon: String {
        switch self {
        case .pota: return "tree.fill"
        case .sota: return "mountain.2.fill"
        case .wwff: return "leaf.fill"
        case .iota: return "water.waves"
        }
    }

    public var requiredQSOsForActivation: Int {
        switch self {
        case .pota, .wwff: return 10
        case .sota: return 4
        case .iota: return 1
        }
    }
}

// MARK: - Field Activation Session
public struct FieldActivationSession: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var program: FieldProgramType
    public var myReference: String              // e.g. "K-1234" or "EP-0001" or "W6/NC-423"
    public var referenceName: String            // e.g. "Golestan National Park"
    public var operatorCallsign: String
    public var gridSquare: String               // e.g. "LM35" or "LL46wr"
    public var latitude: Double?
    public var longitude: Double?
    public var startTime: Date
    public var endTime: Date?
    public var qsoCount: Int
    public var parkToParkCount: Int
    public var summitToSummitCount: Int
    public var targetGoal: Int                  // e.g. 10 for POTA
    public var isActive: Bool
    public var notes: String
    public var workedBands: [String]
    public var workedModes: [String]

    public init(
        id: UUID = UUID(),
        program: FieldProgramType = .pota,
        myReference: String = "",
        referenceName: String = "",
        operatorCallsign: String = "",
        gridSquare: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        startTime: Date = Date(),
        endTime: Date? = nil,
        qsoCount: Int = 0,
        parkToParkCount: Int = 0,
        summitToSummitCount: Int = 0,
        targetGoal: Int = 10,
        isActive: Bool = true,
        notes: String = "",
        workedBands: [String] = [],
        workedModes: [String] = []
    ) {
        self.id = id
        self.program = program
        self.myReference = myReference
        self.referenceName = referenceName
        self.operatorCallsign = operatorCallsign
        self.gridSquare = gridSquare
        self.latitude = latitude
        self.longitude = longitude
        self.startTime = startTime
        self.endTime = endTime
        self.qsoCount = qsoCount
        self.parkToParkCount = parkToParkCount
        self.summitToSummitCount = summitToSummitCount
        self.targetGoal = targetGoal
        self.isActive = isActive
        self.notes = notes
        self.workedBands = workedBands
        self.workedModes = workedModes
    }

    public var isQualified: Bool {
        qsoCount >= targetGoal
    }

    public var remainingToQualify: Int {
        max(0, targetGoal - qsoCount)
    }

    public var progressFraction: Double {
        guard targetGoal > 0 else { return 1.0 }
        return min(1.0, Double(qsoCount) / Double(targetGoal))
    }

    public var qsoRatePerHour: Double {
        let elapsed = max(60.0, (endTime ?? Date()).timeIntervalSince(startTime))
        return (Double(qsoCount) / elapsed) * 3600.0
    }
}

// MARK: - POTA Live Spot Item (Codable from api.pota.app/spot/activator)
public struct POTASpotItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(spotId)_\(spotTime)" }
    public var spotId: Int
    public var activator: String
    public var frequency: Double                // in kHz or MHz depending on endpoint
    public var mode: String
    public var reference: String                // e.g. "K-1234"
    public var name: String                     // Park name
    public var locationDesc: String?            // State or country
    public var grid: String?
    public var spotTime: String                 // ISO8601
    public var spotter: String?
    public var comments: String?
    public var count: Int?

    enum CodingKeys: String, CodingKey {
        case spotId
        case activator
        case frequency
        case mode
        case reference
        case name
        case locationDesc
        case grid
        case spotTime
        case spotter
        case comments
        case count
    }

    public init(
        spotId: Int = 0,
        activator: String = "",
        frequency: Double = 0.0,
        mode: String = "SSB",
        reference: String = "",
        name: String = "",
        locationDesc: String? = nil,
        grid: String? = nil,
        spotTime: String = "",
        spotter: String? = nil,
        comments: String? = nil,
        count: Int? = nil
    ) {
        self.spotId = spotId
        self.activator = activator
        self.frequency = frequency
        self.mode = mode
        self.reference = reference
        self.name = name
        self.locationDesc = locationDesc
        self.grid = grid
        self.spotTime = spotTime
        self.spotter = spotter
        self.comments = comments
        self.count = count
    }

    public var frequencyMHz: Double {
        // POTA API frequency is typically in kHz (e.g. 14074.0 or 7200.0) or MHz
        if frequency > 1000.0 {
            return frequency / 1000.0
        }
        return frequency
    }

    public var frequencyKHz: Double {
        if frequency > 1000.0 {
            return frequency
        }
        return frequency * 1000.0
    }

    public var formattedFrequency: String {
        String(format: "%.3f MHz", frequencyMHz)
    }

    public var band: String {
        AmateurBandPlan.band(forMHz: frequencyMHz) ?? "HF"
    }
}

// MARK: - SOTA Live Spot Item (Codable from api2.sota.org.uk/api/spots)
public struct SOTASpotItem: Identifiable, Codable, Hashable, Sendable {
    public var id: Int { idNumber }
    public var idNumber: Int
    public var timeStamp: String
    public var userID: Int?
    public var summitCode: String               // e.g. "W6/NC-423"
    public var summitDetails: String?
    public var associationCode: String?
    public var regionCode: String?
    public var activatorCallsign: String
    public var activatorName: String?
    public var frequency: String                // string representation e.g. "14.062"
    public var mode: String
    public var callsign: String?
    public var comments: String?

    enum CodingKeys: String, CodingKey {
        case idNumber = "id"
        case timeStamp
        case userID
        case summitCode
        case summitDetails
        case associationCode
        case regionCode
        case activatorCallsign
        case activatorName
        case frequency
        case mode
        case callsign
        case comments
    }

    public init(
        idNumber: Int = 0,
        timeStamp: String = "",
        userID: Int? = nil,
        summitCode: String = "",
        summitDetails: String? = nil,
        associationCode: String? = nil,
        regionCode: String? = nil,
        activatorCallsign: String = "",
        activatorName: String? = nil,
        frequency: String = "14.062",
        mode: String = "CW",
        callsign: String? = nil,
        comments: String? = nil
    ) {
        self.idNumber = idNumber
        self.timeStamp = timeStamp
        self.userID = userID
        self.summitCode = summitCode
        self.summitDetails = summitDetails
        self.associationCode = associationCode
        self.regionCode = regionCode
        self.activatorCallsign = activatorCallsign
        self.activatorName = activatorName
        self.frequency = frequency
        self.mode = mode
        self.callsign = callsign
        self.comments = comments
    }

    public var frequencyMHz: Double {
        Double(frequency.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 14.060
    }

    public var frequencyKHz: Double {
        frequencyMHz * 1000.0
    }

    public var formattedFrequency: String {
        String(format: "%.3f MHz", frequencyMHz)
    }

    public var band: String {
        AmateurBandPlan.band(forMHz: frequencyMHz) ?? "HF"
    }
}

// MARK: - Park Directory Entry (Offline Cache)
public struct ParkDirectoryEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String { reference }
    public var reference: String                // e.g. "K-1234", "EP-0001", "W6/NC-423"
    public var name: String
    public var program: FieldProgramType
    public var country: String
    public var stateOrRegion: String
    public var gridSquare: String
    public var latitude: Double
    public var longitude: Double
    public var elevationMeters: Int?

    public init(
        reference: String,
        name: String,
        program: FieldProgramType = .pota,
        country: String = "",
        stateOrRegion: String = "",
        gridSquare: String = "",
        latitude: Double = 0.0,
        longitude: Double = 0.0,
        elevationMeters: Int? = nil
    ) {
        self.reference = reference
        self.name = name
        self.program = program
        self.country = country
        self.stateOrRegion = stateOrRegion
        self.gridSquare = gridSquare
        self.latitude = latitude
        self.longitude = longitude
        self.elevationMeters = elevationMeters
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public func distance(from userCoord: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude)
        let loc2 = CLLocation(latitude: latitude, longitude: longitude)
        return loc1.distance(from: loc2) / 1000.0 // in km
    }
}

// MARK: - Lightweight Field QSO Record (implements FieldQSORecord)
public struct SimpleFieldQSO: FieldQSORecord, Identifiable, Sendable {
    public var id: UUID
    public var fields: [String: String]

    public init(id: UUID = UUID(), fields: [String: String]) {
        self.id = id
        self.fields = fields
    }

    public subscript(key: String) -> String {
        fields[key] ?? ""
    }

    public var isConfirmed: Bool {
        fields["QSL_RCVD"] == "Y" || fields["LOTW_QSL_RCVD"] == "Y"
    }
}
