//
//  DatabaseExportRegression.swift
//  YAAM Tests
//

import Foundation

struct TestADIFConversionFilter {
    var startUTCKey: String?
    var endUTCKey: String?
    var band: String?
    var mode: String?

    func apply(to records: [[String: String]]) -> [[String: String]] {
        return records.filter { rec in
            if let band, !band.isEmpty {
                let recBand = (rec["BAND"] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                let targetBand = band.trimmingCharacters(in: .whitespaces).lowercased()
                if recBand != targetBand { return false }
            }
            if let mode, !mode.isEmpty {
                let recMode = (rec["MODE"] ?? "").trimmingCharacters(in: .whitespaces).uppercased()
                let targetMode = mode.trimmingCharacters(in: .whitespaces).uppercased()
                if recMode != targetMode { return false }
            }
            if let startUTCKey, !startUTCKey.isEmpty {
                let dateStr = rec["QSO_DATE"] ?? ""
                let timeStr = rec["TIME_ON"] ?? ""
                let recKey = dateStr + timeStr
                if recKey < startUTCKey { return false }
            }
            if let endUTCKey, !endUTCKey.isEmpty {
                let dateStr = rec["QSO_DATE"] ?? ""
                let timeStr = rec["TIME_ON"] ?? ""
                let recKey = dateStr + timeStr
                if recKey > endUTCKey { return false }
            }
            return true
        }
    }
}

func testGenerateADIF(records: [[String: String]]) -> String {
    var output = "YAAM Export\r\n<EOH>\r\n"
    for r in records {
        for (k, v) in r.sorted(by: { $0.key < $1.key }) {
            output += "<\(k):\(v.count)>\(v) "
        }
        output += "<EOR>\r\n"
    }
    return output
}

func testGenerateCSV(headers: [String], records: [[String: String]]) -> String {
    var lines = [headers.joined(separator: ",")]
    for r in records {
        let row = headers.map { r[$0] ?? "" }
        lines.append(row.joined(separator: ","))
    }
    return lines.joined(separator: "\r\n")
}

@main
struct DatabaseExportRegression {
    static func main() {
        print("Running Database Export Regression Tests...")
        testDatabaseExportWithFilters()
        testDatabaseExportADIFAndCSVGeneration()
        print("All Database Export Regression Tests PASSED successfully!")
    }

    private static func testDatabaseExportWithFilters() {
        let records: [[String: String]] = [
            ["CALL": "W1AW", "QSO_DATE": "20260810", "TIME_ON": "100000", "BAND": "20M", "MODE": "FT8"],
            ["CALL": "K1TTT", "QSO_DATE": "20260810", "TIME_ON": "110000", "BAND": "20M", "MODE": "CW"],
            ["CALL": "JA1ABC", "QSO_DATE": "20260810", "TIME_ON": "150000", "BAND": "40M", "MODE": "FT8"],
            ["CALL": "DL1XYZ", "QSO_DATE": "20260811", "TIME_ON": "080000", "BAND": "20M", "MODE": "SSB"]
        ]

        // Test Band filter (20m)
        let bandFilter = TestADIFConversionFilter(band: "20m")
        let bandFiltered = bandFilter.apply(to: records)
        precondition(bandFiltered.count == 3, "Expected 3 records on 20m, got \(bandFiltered.count)")

        // Test Mode filter (FT8)
        let modeFilter = TestADIFConversionFilter(mode: "FT8")
        let modeFiltered = modeFilter.apply(to: records)
        precondition(modeFiltered.count == 2, "Expected 2 FT8 records, got \(modeFiltered.count)")

        // Test UTC time filter
        let timeFilter = TestADIFConversionFilter(
            startUTCKey: "20260810100000",
            endUTCKey: "20260810120000"
        )
        let timeFiltered = timeFilter.apply(to: records)
        precondition(timeFiltered.count == 2, "Expected 2 records between 10:00 and 12:00, got \(timeFiltered.count)")
        precondition(timeFiltered.map { $0["CALL"]! } == ["W1AW", "K1TTT"])

        // Test combined filters
        let combinedFilter = TestADIFConversionFilter(
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
        let adif = testGenerateADIF(records: records)
        precondition(adif.contains("<EOH>"), "ADIF must contain <EOH>")
        precondition(adif.contains("<CALL:6>EP2AES"), "ADIF must contain EP2AES tag")
        precondition(adif.contains("<CALL:4>K9OM"), "ADIF must contain K9OM tag")
        precondition(adif.contains("<EOR>"), "ADIF must contain <EOR>")

        // Test CSV Generation
        let csv = testGenerateCSV(headers: headers, records: records)
        let lines = csv.components(separatedBy: "\r\n")
        precondition(lines.count == 3, "Expected header line + 2 data lines, got \(lines.count)")
        precondition(lines[0] == "QSO_DATE,TIME_ON,CALL,BAND,MODE,RST_SENT,RST_RCVD")
        precondition(lines[1].contains("EP2AES"))
        precondition(lines[2].contains("K9OM"))
    }
}
