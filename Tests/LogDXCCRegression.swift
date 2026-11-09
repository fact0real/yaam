import Foundation

nonisolated struct QSORecordModel: Sendable {
    var id = UUID()
    let fields: [String: String]
    subscript(_ key: String) -> String { fields[key] ?? "" }
    var isConfirmed: Bool {
        ["LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "QRZCOM_QSL_RCVD", "APP_QRZLOG_STATUS", "EQSL_QSL_RCVD", "QSL_RCVD"].contains {
            ["Y", "V", "C", "CONFIRMED", "VERIFIED"].contains(self[$0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        }
    }
}

@main struct LogDXCCRegression {
    static func main() {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String = "", line: Int = #line) {
            precondition(condition(), "Line \(line): \(message)"); checks += 1
        }
        func resolve(_ country: String = "", _ dxcc: String = "", _ call: String = "") -> LogDXCCEntity.Resolution {
            LogDXCCEntity.resolve(["COUNTRY": country, "DXCC": dxcc, "CALL": call])
        }
        expect(DXCCEntityCatalog.byCode.count == 402)
        expect(Set(DXCCEntityCatalog.byCode.values.map(\.name)).count == 402, "Distinct entity IDs must retain distinct grouping labels")
        expect(DXCCEntityCatalog.byCode.values.filter { !$0.isDeleted }.count == 340)
        expect(DXCCEntityCatalog.entity(named: "Federal Republic of Germany")?.code == 230)
        expect(DXCCEntityCatalog.entity(named: "Germany")?.code == 230)
        expect(DXCCEntityCatalog.byCode[81]?.name == "Germany (deleted)")
        expect(DXCCEntityCatalog.entity(named: "Turkey")?.code == 390)

        // Missing DXCC codes must not discard confirmed countries; aliases share one identity.
        expect(resolve("Germany").entity?.code == 230)
        expect(resolve("Deutschland").entity?.code == 230)
        expect(resolve("Madagascar").entity?.code == 438)
        expect(resolve("", "00015").entity?.name == "Asiatic Russia")
        expect(resolve("European Russia", "15").issue != nil)
        expect(resolve("European Russia", "15").entity?.name == "Asiatic Russia")
        expect(resolve("Russia", "126").entity?.name == "Kaliningrad")
        expect(resolve("Uzbekistan", "254").entity?.name == "Luxembourg")
        expect(resolve("Uzbekistan", "254").issue != nil)
        expect(resolve("Northern Cyprus", "901").entity == nil)
        expect(resolve("Russia", "garbage", "UA9ABC").entity == nil)
        expect(resolve("Russia", "9999", "UA9ABC").entity == nil)
        expect(resolve("France", "0", "F1ABC").entity == nil)
        expect(resolve("France", "0", "F1ABC").source == .excluded)
        expect(resolve("France", "-1", "F1ABC").entity == nil)

        // Exercise the actual bundled CTY file, including its CRLF lines, exact exceptions and slash calls.
        for (call, code) in [("RA6AVP",54), ("R4IK",54), ("R9ABC",15), ("UA9ABC",15), ("R0IAH/6",54), ("R2FABC",126)] {
            expect(resolve("Russia", "", call).entity?.code == code, call)
        }
        expect(resolve("Russia", "", "K1ABC").entity == nil)
        expect(resolve("Russia", "", "UA9ABC/EA").entity == nil)
        expect(resolve("Russia", "", "UA9ABC/9").entity == nil)
        expect(resolve("", "", "W1AW").entity?.code == 291)
        expect(resolve("Unknown", "", "EA3JIC").entity?.code == 281)
        expect(resolve("United Kingdom", "", "GM1ABC").entity?.code == 279)
        expect(resolve("", "", "EA8/EA3JIC/P").entity?.code == 29)
        expect(resolve("", "", "EA3JIC/EA6/P").entity?.code == 21)
        expect(resolve("", "", "SV2RSG/A").entity?.code == 180)
        expect(resolve("Spain", "281", "EA3JIC/MM").entity == nil)
        expect(resolve("Spain", "281", "EA3JIC/AM").entity == nil)
        expect(resolve("", "", "QQ0UNKNOWN").entity == nil)
        expect(resolve("", "", "not-a-call").entity == nil)

        let fields: [[String: String]] = [
            ["COUNTRY":"Germany", "BAND":"20m", "LOTW_QSL_RCVD":"Y"],
            ["COUNTRY":"Deutschland", "DXCC":"230", "BAND":"20m"],
            ["COUNTRY":"Russia", "DXCC":"15", "BAND":"20m", "QRZLOG_QSL_RCVD":"Y"],
            ["COUNTRY":"Russia", "CALL":"RA6AVP", "BAND":"20m", "QRZCOM_QSL_RCVD":"Y"],
            ["COUNTRY":"Madagascar", "BAND":"10m", "QSL_RCVD":"Y"],
            ["COUNTRY":"France", "DXCC":"0", "BAND":"20m", "QSL_RCVD":"Y"],
            ["COUNTRY":"Unknown", "CALL":"QQ0UNKNOWN", "BAND":"20m", "QSL_RCVD":"Y"]
        ]
        let records = fields.map { QSORecordModel(fields: $0) }
        let summary = DXCCStatisticsSummary(records: records)
        expect(summary.workedCodes == [230,15,54,438])
        expect(summary.confirmedCodes == summary.workedCodes)
        expect(summary.qrzConfirmedCodes == [15,54])
        expect(summary.inferredCount == 3)
        expect(summary.unresolvedCount == 1)
        expect(summary.issues.count == 1)
        expect(records.map(\.fields) == fields, "Read-time statistics must preserve ADIF")
        let coverage = ConfirmationOpportunityIndex(records: records, allKnownEntities: [])
        expect(Set(coverage.countryBandCoverage.map(\.country)) == ["Germany","Asiatic Russia","European Russia","Madagascar"])
        expect(coverage.countryBandCoverage.filter(\.isConfirmed).count == summary.confirmedCodes.count)
        expect(ConfirmationOpportunityIndex.matchesCountryFilter(for: records[3], selectedCountries: ["European Russia"]))
        expect(!ConfirmationOpportunityIndex.matchesCountryFilter(for: records[3], selectedCountries: ["Asiatic Russia"]))
        expect(coverage.opportunity(for: records[6].id)?.hasCountryBandData == false)
        print("Log DXCC regression: \(checks) checks passed (one identity, missing codes, provider scope, Russia, portable exceptions, invalid/no-entity codes and unchanged records)")
    }
}
