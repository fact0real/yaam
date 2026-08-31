//
//  DatabaseExportRegression.swift
//  YAAM Tests
//

import Foundation

nonisolated struct QSORecordModel: Identifiable, Sendable {
    var id: UUID = UUID()
    var index: Int
    var fields: [String: String]

    subscript(key: String) -> String {
        fields[key] ?? ""
    }

    var isConfirmed: Bool { false }
    var uniqueKey: String { QSOIdentity.exactKey(fields: fields) }
}

@main
struct DatabaseExportRegression {
    static func main() {
        print("Running Database Export Regression Tests...")
        testDatabaseExportAllAndSingleProfiles()
        testDatabaseExportWithFilters()
        testDatabaseExportADIFAndCSVGeneration()
        print("All Database Export Regression Tests PASSED successfully!")
    }

    private static func testDatabaseExportAllAndSingleProfiles() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("YAAM_DB_Test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            let db = try LogbookDatabase(baseDirectory: tempDir)
            
            // Create two station profiles
            let profile1 = StationProfile(
                id: UUID(),
                name: "Main Station",
                callsign: "EP2AES",
                qth: "Tehran",
                grid: "LM55ir"
            )
            let profile2 = StationProfile(
                id: UUID(),
                name: "Contest Station",
                callsign: "EP2C",
                qth: "Alborz",
                grid: "LM55xx"
            )

            try db.saveStationProfile(profile1)
            try db.saveStationProfile(profile2)

            // Save QSOs for profile 1
            let qsos1: [PersistedQSO] = [
                PersistedQSO(id: UUID(), index: 1, fields: [
                    "CALL": "W1AW",
                    "QSO_DATE": "20260801",
                    "TIME_ON": "120000",
                    "BAND": "20M",
                    "MODE": "FT8",
                    "RST_SENT": "-05",
                    "RST_RCVD": "-10",
                    "APP_LOTW_QSL": "YES"
                ]),
                PersistedQSO(id: UUID(), index: 2, fields: [
                    "CALL": "JA1ABC",
                    "QSO_DATE": "20260802",
                    "TIME_ON": "143000",
                    "BAND": "40M",
                    "MODE": "CW",
                    "RST_SENT": "599",
                    "RST_RCVD": "599"
                ])
            ]
            try db.saveWorkspace(profileID: profile1.id, headers: ["QSO_DATE", "TIME_ON", "CALL", "BAND", "MODE", "RST_SENT", "RST_RCVD", "APP_LOTW_QSL"], records: qsos1)

            // Save QSOs for profile 2
            let qsos2: [PersistedQSO] = [
                PersistedQSO(id: UUID(), index: 1, fields: [
                    "CALL": "DL1XYZ",
                    "QSO_DATE": "20260803",
                    "TIME_ON": "180000",
                    "BAND": "20M",
                    "MODE": "SSB",
                    "RST_SENT": "59",
                    "RST_RCVD": "59",
                    "COMMENT": "Contest QSO"
                ])
            ]
            try db.saveWorkspace(profileID: profile2.id, headers: ["QSO_DATE", "TIME_ON", "CALL", "BAND", "MODE", "RST_SENT", "RST_RCVD", "COMMENT"], records: qsos2)

            // Test Single Profile Load
            let (headers1, records1) = try db.loadWorkspaceQSOs(profileID: profile1.id)
            precondition(records1.count == 2, "Expected 2 records for profile 1, got \(records1.count)")
            precondition(headers1.contains("APP_LOTW_QSL"), "Expected headers to include APP_LOTW_QSL")

            let (headers2, records2) = try db.loadWorkspaceQSOs(profileID: profile2.id)
            precondition(records2.count == 1, "Expected 1 record for profile 2, got \(records2.count)")
            precondition(headers2.contains("COMMENT"), "Expected headers to include COMMENT")

            // Test All Profiles Load (Full Database)
            let (allHeaders, allRecords) = try db.loadWorkspaceQSOs(profileID: nil)
            precondition(allRecords.count == 3, "Expected 3 records in full database export, got \(allRecords.count)")
            precondition(allHeaders.contains("APP_LOTW_QSL"), "Expected combined headers to contain APP_LOTW_QSL")
            precondition(allHeaders.contains("COMMENT"), "Expected combined headers to contain COMMENT")

            // Test stats
            let statsAll = try db.databaseQSOStats(profileID: nil)
            precondition(statsAll.count == 3, "Expected 3 total QSOs in stats")
            precondition(statsAll.firstDate == "20260801", "Expected first date 20260801, got \(String(describing: statsAll.firstDate))")
            precondition(statsAll.lastDate == "20260803", "Expected last date 20260803, got \(String(describing: statsAll.lastDate))")

            let statsProfile1 = try db.databaseQSOStats(profileID: profile1.id)
            precondition(statsProfile1.count == 2, "Expected 2 QSOs in stats for profile 1")
        } catch {
            fatalError("testDatabaseExportAllAndSingleProfiles failed with error: \(error)")
        }
    }

    private static func testDatabaseExportWithFilters() {
        let records: [[String: String]] = [
            ["CALL": "W1AW", "QSO_DATE": "20260810", "TIME_ON": "100000", "BAND": "20M", "MODE": "FT8"],
            ["CALL": "K1TTT", "QSO_DATE": "20260810", "TIME_ON": "113000", "BAND": "20M", "MODE": "CW"],
            ["CALL": "JA1ABC", "QSO_DATE": "20260810", "TIME_ON": "120000", "BAND": "40M", "MODE": "FT8"],
            ["CALL": "DL1XYZ", "QSO_DATE": "20260811", "TIME_ON": "080000", "BAND": "20M", "MODE": "SSB"]
        ]

        // Test Band filter (20m)
        let bandFilter = ADIFConversionFilter(band: "20m")
        let bandFiltered = bandFilter.apply(to: records)
        precondition(bandFiltered.count == 3, "Expected 3 records on 20m, got \(bandFiltered.count)")

        // Test Mode filter (FT8)
        let modeFilter = ADIFConversionFilter(mode: "FT8")
        let modeFiltered = modeFilter.apply(to: records)
        precondition(modeFiltered.count == 2, "Expected 2 FT8 records, got \(modeFiltered.count)")

        // Test UTC time filter
        let timeFilter = ADIFConversionFilter(
            startUTCKey: "20260810100000",
            endUTCKey: "20260810120000"
        )
        let timeFiltered = timeFilter.apply(to: records)
        precondition(timeFiltered.count == 2, "Expected 2 records between 10:00 and 12:00, got \(timeFiltered.count)")
        precondition(timeFiltered.map { $0["CALL"]! } == ["W1AW", "K1TTT"])

        // Test combined filters
        let combinedFilter = ADIFConversionFilter(
            startUTCKey: "20260810000000",
            endUTCKey: "20260810235959",
            band: "20m",
            mode: "FT8"
        )
        let combinedFiltered = combinedFilter.apply(to: records)
        precondition(combinedFiltered.count == 1, "Expected 1 record matching combined filter, got \(combinedFiltered.count)")
        precondition(combinedFiltered[0]["CALL"] == "W1AW")
    }

    private static func testDatabaseExportADIFAndCSVGeneration() {
        let headers = ["QSO_DATE", "TIME_ON", "CALL", "BAND", "MODE", "RST_SENT", "RST_RCVD"]
        let records: [[String: String]] = [
            ["QSO_DATE": "20260810", "TIME_ON": "100000", "CALL": "EP2AES", "BAND": "20M", "MODE": "FT8", "RST_SENT": "-05", "RST_RCVD": "-10"],
            ["QSO_DATE": "20260810", "TIME_ON": "101500", "CALL": "K9OM", "BAND": "40M", "MODE": "CW", "RST_SENT": "599", "RST_RCVD": "599"]
        ]

        // Test ADIF Generation
        let adif = generateADIF(originalContent: "", records: records)
        precondition(adif.contains("<EOH>"), "ADIF must contain <EOH>")
        precondition(adif.contains("<CALL:6>EP2AES"), "ADIF must contain EP2AES tag")
        precondition(adif.contains("<CALL:4>K9OM"), "ADIF must contain K9OM tag")
        precondition(adif.contains("<EOR>"), "ADIF must contain <EOR>")

        // Test CSV Generation
        let csv = generateCSV(headers: headers, records: records)
        let lines = csv.components(separatedBy: "\r\n")
        precondition(lines.count == 3, "Expected header line + 2 data lines, got \(lines.count)")
        precondition(lines[0] == "QSO_DATE,TIME_ON,CALL,BAND,MODE,RST_SENT,RST_RCVD")
        precondition(lines[1].contains("EP2AES"))
        precondition(lines[2].contains("K9OM"))
    }
}
