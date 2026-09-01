//
//  MaidenheadGridEngine.swift
//  YAAM
//

import Foundation

// MARK: - Maidenhead Grid Bounding Box & Coordinate Math

public struct MaidenheadBoundingBox: Equatable, Sendable {
    public let grid: String
    public let minLat: Double
    public let maxLat: Double
    public let minLon: Double
    public let maxLon: Double
    public let center: GeoCoordinate

    public var widthDeg: Double { maxLon - minLon }
    public var heightDeg: Double { maxLat - minLat }
}

public enum MapProjectionMode: String, CaseIterable, Identifiable, Sendable {
    case globe3D = "3D Globe"
    case azimuthal = "Azimuthal Antenna"
    case gridTracker = "GridTracker 2D"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .globe3D: return "globe.americas.fill"
        case .azimuthal: return "antenna.radiowaves.left.and.right"
        case .gridTracker: return "square.grid.3x3"
        }
    }
}

public enum GridTrackerStatus: String, Sendable, CaseIterable {
    case confirmed = "Confirmed"      // 🟢 Confirmed in log
    case worked = "Worked (Pending)"  // 🟠 Worked in log, not yet confirmed
    case needed = "Needed Grid"       // 🔴 Never worked
    case activeOnAir = "On Air Now"   // 🔵 Currently spotted / decoded on air
}

public struct GridLogSummary: Equatable, Sendable {
    public let grid: String
    public var qsoCount: Int
    public var isConfirmed: Bool
    public var firstWorkedDate: String?
    public var lastWorkedCallsign: String?
    public var bandsWorked: Set<String>
    public var modesWorked: Set<String>
}

public enum MaidenheadGridEngine {
    /// Converts a Maidenhead locator (2, 4, or 6 characters) to its bounding box and center coordinate
    public static func boundingBox(for locator: String) -> MaidenheadBoundingBox? {
        let clean = locator.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 2 else { return nil }

        let chars = Array(clean)
        guard let fieldA = chars[0].asciiValue, fieldA >= Character("A").asciiValue!, fieldA <= Character("R").asciiValue!,
              let fieldB = chars[1].asciiValue, fieldB >= Character("A").asciiValue!, fieldB <= Character("R").asciiValue! else {
            return nil
        }

        var minLon = Double(fieldA - Character("A").asciiValue!) * 20.0 - 180.0
        var maxLon = minLon + 20.0
        var minLat = Double(fieldB - Character("A").asciiValue!) * 10.0 - 90.0
        var maxLat = minLat + 10.0

        // 4-character Square (e.g. LL65)
        if clean.count >= 4 {
            guard let sqNum1 = chars[2].wholeNumberValue, (0...9).contains(sqNum1),
                  let sqNum2 = chars[3].wholeNumberValue, (0...9).contains(sqNum2) else {
                return nil
            }
            minLon += Double(sqNum1) * 2.0
            maxLon = minLon + 2.0
            minLat += Double(sqNum2) * 1.0
            maxLat = minLat + 1.0
        }

        // 6-character Subsquare (e.g. LL65ns)
        if clean.count >= 6 {
            guard let subA = chars[4].asciiValue, subA >= Character("A").asciiValue!, subA <= Character("X").asciiValue!,
                  let subB = chars[5].asciiValue, subB >= Character("A").asciiValue!, subB <= Character("X").asciiValue! else {
                return nil
            }
            let subLonWidth = 2.0 / 24.0 // 5 minutes of arc
            let subLatHeight = 1.0 / 24.0 // 2.5 minutes of arc

            minLon += Double(subA - Character("A").asciiValue!) * subLonWidth
            maxLon = minLon + subLonWidth
            minLat += Double(subB - Character("A").asciiValue!) * subLatHeight
            maxLat = minLat + subLatHeight
        }

        let center = GeoCoordinate(latitude: (minLat + maxLat) / 2.0, longitude: (minLon + maxLon) / 2.0)
        return MaidenheadBoundingBox(
            grid: clean,
            minLat: minLat,
            maxLat: maxLat,
            minLon: minLon,
            maxLon: maxLon,
            center: center
        )
    }

    /// Converts a GeoCoordinate into a 4-character Maidenhead locator (e.g. LL65)
    public static func locator(from coord: GeoCoordinate) -> String {
        var lon = coord.longitude + 180.0
        var lat = coord.latitude + 90.0

        // Handle edge cases
        lon = max(0.0, min(359.9999, lon))
        lat = max(0.0, min(179.9999, lat))

        let fieldLon = Int(lon / 20.0)
        let fieldLat = Int(lat / 10.0)

        let remLon1 = lon.truncatingRemainder(dividingBy: 20.0)
        let remLat1 = lat.truncatingRemainder(dividingBy: 10.0)

        let squareLon = Int(remLon1 / 2.0)
        let squareLat = Int(remLat1 / 1.0)

        let charA = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLon))))
        let charB = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLat))))

        return "\(charA)\(charB)\(squareLon)\(squareLat)"
    }

    /// Converts a GeoCoordinate into a precise 6-character Maidenhead locator (e.g. LL65ns)
    public static func locator6(from coord: GeoCoordinate) -> String {
        var lon = coord.longitude + 180.0
        var lat = coord.latitude + 90.0

        lon = max(0.0, min(359.9999, lon))
        lat = max(0.0, min(179.9999, lat))

        let fieldLon = Int(lon / 20.0)
        let fieldLat = Int(lat / 10.0)

        let remLon1 = lon.truncatingRemainder(dividingBy: 20.0)
        let remLat1 = lat.truncatingRemainder(dividingBy: 10.0)

        let squareLon = Int(remLon1 / 2.0)
        let squareLat = Int(remLat1 / 1.0)

        let remLon2 = remLon1.truncatingRemainder(dividingBy: 2.0)
        let remLat2 = remLat1.truncatingRemainder(dividingBy: 1.0)

        let subLon = Int(remLon2 / (2.0 / 24.0))
        let subLat = Int(remLat2 / (1.0 / 24.0))

        let charA = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLon))))
        let charB = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLat))))
        let charC = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(min(23, max(0, subLon))))))
        let charD = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(min(23, max(0, subLat))))))

        return "\(charA)\(charB)\(squareLon)\(squareLat)\(charC)\(charD)".lowercased()
    }

    /// Aggregates all QSORecords from logbook into a map of Grid summaries
    static func aggregateLogbook(
        records: [QSORecordModel],
        bandFilter: String = "ALL",
        modeFilter: String = "ALL"
    ) -> [String: GridLogSummary] {
        var gridMap: [String: GridLogSummary] = [:]
        let upperBand = bandFilter.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let upperMode = modeFilter.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        for r in records {
            let gridRaw = r["GRIDSQUARE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard gridRaw.count >= 4 else { continue }
            let grid4 = String(gridRaw.prefix(4))

            let recordBand = r["BAND"].uppercased()
            let recordMode = (r["SUBMODE"].isEmpty ? r["MODE"] : r["SUBMODE"]).uppercased()

            if upperBand != "ALL" && recordBand != upperBand { continue }
            if upperMode != "ALL" && !recordMode.contains(upperMode) { continue }

            let isConf = r.isConfirmed
            let call = r["CALL"].uppercased()
            let date = r["QSO_DATE"]

            if var existing = gridMap[grid4] {
                existing.qsoCount += 1
                if isConf { existing.isConfirmed = true }
                existing.bandsWorked.insert(recordBand)
                existing.modesWorked.insert(recordMode)
                existing.lastWorkedCallsign = call
                gridMap[grid4] = existing
            } else {
                gridMap[grid4] = GridLogSummary(
                    grid: grid4,
                    qsoCount: 1,
                    isConfirmed: isConf,
                    firstWorkedDate: date,
                    lastWorkedCallsign: call,
                    bandsWorked: [recordBand],
                    modesWorked: [recordMode]
                )
            }
        }

        return gridMap
    }

    /// Evaluates the status of a specific 4-character Maidenhead grid
    public static func status(
        for grid4: String,
        logSummaries: [String: GridLogSummary],
        activeOnAirGrids: Set<String>
    ) -> GridTrackerStatus {
        let clean = String(grid4.prefix(4)).uppercased()

        if activeOnAirGrids.contains(clean) {
            return .activeOnAir
        }

        if let summary = logSummaries[clean] {
            return summary.isConfirmed ? .confirmed : .worked
        }

        return .needed
    }

    /// Catalog of all 324 worldwide 2-character Maidenhead Fields (AA to RR)
    public static let allFields: [String] = {
        var list: [String] = []
        for lonCh in 0..<18 {
            for latCh in 0..<18 {
                let c1 = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(lonCh))))
                let c2 = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(latCh))))
                list.append("\(c1)\(c2)")
            }
        }
        return list
    }()
}
