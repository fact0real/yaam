//
//  SpotArchiveDatabase.swift
//  YAAM
//
//  Lightweight, high-performance SQLite-backed historical spot archive.
//  Enables multi-day spot lookups, DXpedition activity tracking, and CSV export.
//

import Combine
import Foundation
import SQLite3

public struct ArchivedSpotRecord: Identifiable, Sendable, Hashable {
    public let id: String
    public let callsign: String
    public let frequencyKHz: Double
    public let band: String
    public let mode: String
    public let spotter: String
    public let spottedAt: Date
    public let comment: String
    public let snrDB: Int?
    public let dxccEntity: String
    public let beamHeadingDeg: Double?
    public let grid: String
    public let flagEmoji: String
    public let reportCount: Int

    public var frequencyMHz: Double { frequencyKHz / 1000.0 }
}

public final class SpotArchiveDatabase: ObservableObject {
    public static let shared = SpotArchiveDatabase()

    @Published public private(set) var totalStoredSpots: Int = 0

    private let queue = DispatchQueue(label: "app.yaam.spot-archive-database", qos: .utility)
    private var db: OpaquePointer?
    private let databaseURL: URL

    public init(baseDirectory: URL? = nil) {
        let fm = FileManager.default
        let root: URL
        if let baseDirectory {
            root = baseDirectory
        } else if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            root = appSupport.appendingPathComponent("YAAM/Data", isDirectory: true)
        } else {
            root = fm.temporaryDirectory
        }

        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("spots_archive.sqlite")

        openDatabase()
        createSchema()
        refreshCount()
        schedulePeriodicCleanup()
    }

    deinit {
        if let db {
            sqlite3_close_v2(db)
        }
    }

    // MARK: - Database Initialization

    private func openDatabase() {
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &pointer, flags, nil) == SQLITE_OK {
            db = pointer
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        } else {
            print("⚠️ SpotArchiveDatabase: Failed to open SQLite at \(databaseURL.path)")
        }
    }

    private func createSchema() {
        let sql = """
        CREATE TABLE IF NOT EXISTS spots_archive (
            id TEXT PRIMARY KEY,
            callsign TEXT NOT NULL,
            frequency_khz REAL NOT NULL,
            band TEXT NOT NULL,
            mode TEXT NOT NULL,
            spotter TEXT NOT NULL,
            spotted_at REAL NOT NULL,
            comment TEXT,
            snr INTEGER,
            dxcc_entity TEXT,
            beam_heading REAL,
            grid TEXT,
            flag_emoji TEXT,
            report_count INTEGER DEFAULT 1
        );

        CREATE INDEX IF NOT EXISTS idx_spots_call ON spots_archive (callsign);
        CREATE INDEX IF NOT EXISTS idx_spots_time ON spots_archive (spotted_at);
        CREATE INDEX IF NOT EXISTS idx_spots_band ON spots_archive (band);
        CREATE INDEX IF NOT EXISTS idx_spots_call_time ON spots_archive (callsign, spotted_at);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Batch Ingestion

    func archiveSpots(_ spots: [DXSpot]) {
        guard !spots.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }

            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

            let insertSQL = """
            INSERT INTO spots_archive (
                id, callsign, frequency_khz, band, mode, spotter, spotted_at,
                comment, snr, dxcc_entity, beam_heading, grid, flag_emoji, report_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                frequency_khz = excluded.frequency_khz,
                spotted_at = excluded.spotted_at,
                comment = excluded.comment,
                snr = excluded.snr,
                report_count = spots_archive.report_count + 1;
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
                for spot in spots {
                    sqlite3_bind_text(statement, 1, (spot.id as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 2, (spot.callsign as NSString).utf8String, -1, nil)
                    sqlite3_bind_double(statement, 3, spot.frequencyKHz)
                    sqlite3_bind_text(statement, 4, (spot.band as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 5, (spot.mode as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 6, (spot.spotter as NSString).utf8String, -1, nil)
                    sqlite3_bind_double(statement, 7, spot.lastSeenAt.timeIntervalSince1970)
                    sqlite3_bind_text(statement, 8, (spot.comment as NSString).utf8String, -1, nil)

                    if let snr = spot.snrDB {
                        sqlite3_bind_int(statement, 9, Int32(snr))
                    } else {
                        sqlite3_bind_null(statement, 9)
                    }

                    sqlite3_bind_text(statement, 10, (spot.dxccEntityName as NSString).utf8String, -1, nil)

                    if let beam = spot.beamHeadingDeg {
                        sqlite3_bind_double(statement, 11, beam)
                    } else {
                        sqlite3_bind_null(statement, 11)
                    }

                    sqlite3_bind_text(statement, 12, (spot.grid as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 13, (spot.flagEmoji as NSString).utf8String, -1, nil)
                    sqlite3_bind_int(statement, 14, Int32(spot.reportCount))

                    sqlite3_step(statement)
                    sqlite3_reset(statement)
                }
                sqlite3_finalize(statement)
            }

            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
            self.refreshCount()
        }
    }

    // MARK: - Search & Historical Queries

    public func searchArchive(
        callsign: String? = nil,
        band: String? = nil,
        mode: String? = nil,
        sinceHours: Int = 48,
        limit: Int = 500
    ) -> [ArchivedSpotRecord] {
        var results: [ArchivedSpotRecord] = []
        queue.sync {
            guard let db else { return }

            var conditions: [String] = []
            var params: [Any] = []

            let cutoffEpoch = Date().addingTimeInterval(-Double(sinceHours) * 3600.0).timeIntervalSince1970
            conditions.append("spotted_at >= ?")
            params.append(cutoffEpoch)

            if let call = callsign?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !call.isEmpty {
                if call.contains("*") || call.contains("?") {
                    let sqlPattern = call.replacingOccurrences(of: "*", with: "%").replacingOccurrences(of: "?", with: "_")
                    conditions.append("callsign LIKE ?")
                    params.append(sqlPattern)
                } else {
                    conditions.append("callsign LIKE ?")
                    params.append("%\(call)%")
                }
            }

            if let b = band?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty, b != "All" {
                conditions.append("band = ?")
                params.append(b)
            }

            if let m = mode?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty, m != "All" {
                conditions.append("mode = ?")
                params.append(m)
            }

            let whereClause = conditions.joined(separator: " AND ")
            let query = """
            SELECT id, callsign, frequency_khz, band, mode, spotter, spotted_at,
                   comment, snr, dxcc_entity, beam_heading, grid, flag_emoji, report_count
            FROM spots_archive
            WHERE \(whereClause)
            ORDER BY spotted_at DESC
            LIMIT \(limit);
            """

            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                for (idx, param) in params.enumerated() {
                    let bindIdx = Int32(idx + 1)
                    if let doubleVal = param as? Double {
                        sqlite3_bind_double(statement, bindIdx, doubleVal)
                    } else if let strVal = param as? String {
                        sqlite3_bind_text(statement, bindIdx, (strVal as NSString).utf8String, -1, nil)
                    }
                }

                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(statement, 0))
                    let call = String(cString: sqlite3_column_text(statement, 1))
                    let freq = sqlite3_column_double(statement, 2)
                    let bandVal = String(cString: sqlite3_column_text(statement, 3))
                    let modeVal = String(cString: sqlite3_column_text(statement, 4))
                    let spotterVal = String(cString: sqlite3_column_text(statement, 5))
                    let epoch = sqlite3_column_double(statement, 6)
                    let commentVal = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? ""
                    let snrVal: Int? = sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 8))
                    let dxccVal = sqlite3_column_text(statement, 9).map { String(cString: $0) } ?? ""
                    let beamVal: Double? = sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 10)
                    let gridVal = sqlite3_column_text(statement, 11).map { String(cString: $0) } ?? ""
                    let flagVal = sqlite3_column_text(statement, 12).map { String(cString: $0) } ?? ""
                    let repCount = Int(sqlite3_column_int(statement, 13))

                    results.append(ArchivedSpotRecord(
                        id: id,
                        callsign: call,
                        frequencyKHz: freq,
                        band: bandVal,
                        mode: modeVal,
                        spotter: spotterVal,
                        spottedAt: Date(timeIntervalSince1970: epoch),
                        comment: commentVal,
                        snrDB: snrVal,
                        dxccEntity: dxccVal,
                        beamHeadingDeg: beamVal,
                        grid: gridVal,
                        flagEmoji: flagVal,
                        reportCount: max(1, repCount)
                    ))
                }
                sqlite3_finalize(statement)
            }
        }
        return results
    }

    // MARK: - Retention & Pruning

    public func prune(olderThanDays days: Int = 7) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400.0).timeIntervalSince1970
            let sql = "DELETE FROM spots_archive WHERE spotted_at < \(cutoff);"
            sqlite3_exec(db, sql, nil, nil, nil)
            self.refreshCount()
        }
    }

    private func schedulePeriodicCleanup() {
        prune(olderThanDays: 7)
    }

    private func refreshCount() {
        guard let db else { return }
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM spots_archive;", -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = Int(sqlite3_column_int(statement, 0))
                DispatchQueue.main.async {
                    self.totalStoredSpots = count
                }
            }
            sqlite3_finalize(statement)
        }
    }

    // MARK: - CSV Export

    public static func generateCSV(from spots: [ArchivedSpotRecord]) -> String {
        var csv = "UTC,Callsign,Frequency_kHz,Band,Mode,Spotter,SNR_dB,Beam_Deg,Country,Grid,Comment,Reports\n"
        let df = ISO8601DateFormatter()
        for spot in spots {
            let utc = df.string(from: spot.spottedAt)
            let cleanComment = spot.comment.replacingOccurrences(of: "\"", with: "\"\"").replacingOccurrences(of: "\n", with: " ")
            let snrStr = spot.snrDB.map(String.init) ?? ""
            let beamStr = spot.beamHeadingDeg.map { String(format: "%.0f", $0) } ?? ""
            csv += "\"\(utc)\",\"\(spot.callsign)\",\(String(format: "%.1f", spot.frequencyKHz)),\"\(spot.band)\",\"\(spot.mode)\",\"\(spot.spotter)\",\"\(snrStr)\",\"\(beamStr)\",\"\(spot.dxccEntity)\",\"\(spot.grid)\",\"\(cleanComment)\",\(spot.reportCount)\n"
        }
        return csv
    }

    static func generateCSV(from liveSpots: [DXSpot]) -> String {
        var csv = "UTC,Callsign,Frequency_kHz,Band,Mode,Spotter,SNR_dB,Beam_Deg,Country,Distance_km,Grid,Comment,LoTW_Active,Reports\n"
        let df = ISO8601DateFormatter()
        for spot in liveSpots {
            let utc = df.string(from: spot.spottedAt)
            let cleanComment = spot.comment.replacingOccurrences(of: "\"", with: "\"\"").replacingOccurrences(of: "\n", with: " ")
            let snrStr = spot.snrDB.map(String.init) ?? ""
            let beamStr = spot.beamHeadingDeg.map { String(format: "%.0f", $0) } ?? ""
            let distStr = spot.spotterDistanceKm.map { String(format: "%.0f", $0) } ?? ""
            let lotwStr = spot.isLoTWActive ? "YES" : "NO"
            csv += "\"\(utc)\",\"\(spot.callsign)\",\(String(format: "%.1f", spot.frequencyKHz)),\"\(spot.band)\",\"\(spot.mode)\",\"\(spot.spotter)\",\"\(snrStr)\",\"\(beamStr)\",\"\(spot.dxccEntityName)\",\"\(distStr)\",\"\(spot.grid)\",\"\(cleanComment)\",\"\(lotwStr)\",\(spot.reportCount)\n"
        }
        return csv
    }
}
