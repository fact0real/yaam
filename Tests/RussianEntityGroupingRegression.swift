import Foundation

nonisolated struct QSORecordModel {
    var id = UUID()
    var fields: [String: String]
    var isConfirmed = false
    subscript(_ key: String) -> String { fields[key] ?? "" }
}

@main struct RussianEntityGroupingRegression {
    static func main() {
        func country(_ name: String, _ dxcc: String, call: String = "UA9ABC") -> String {
            ConfirmationOpportunityIndex.normalizedCountry(for: QSORecordModel(fields: ["COUNTRY": name, "DXCC": dxcc, "CALL": call]))
        }
        precondition(country("Russia", "15") == "Asiatic Russia")
        precondition(country("Russia", "54") == "European Russia")
        precondition(country("Russian Federation", "54", call: "UA9ABC/EA") == "European Russia", "Explicit entity wins over portable prefix")
        precondition(country("", "15", call: "K1ABC") == "Asiatic Russia")
        precondition(country("European Russia", "15") == "Asiatic Russia", "Recorded DXCC identity is used; original conflicting fields remain available for review")
        precondition(country("Russia", "126") == "Kaliningrad", "A distinct recorded Russian entity must not be collapsed into mainland Russia")
        precondition(country("Russia", "garbage").isEmpty)
        precondition(country("Russia", "", call: "UA9ABC/EA").isEmpty, "A foreign portable prefix conflicting with Russia needs review")
        precondition(country("Russia", "", call: "K1ABC").isEmpty)
        precondition(country("Russia", "", call: "UA9ABC") == "Asiatic Russia")
        precondition(country("Russia", "", call: "UA3ABC") == "European Russia")
        let fields = ["COUNTRY": "Russia", "DXCC": "15", "CALL": "UA9ABC", "BAND": "20m", "COMMENT": "Original imported value"]
        let record = QSORecordModel(fields: fields)
        let european = QSORecordModel(fields: ["COUNTRY": "Russia", "DXCC": "54", "CALL": "UA3ABC", "BAND": "20m"])
        let index = ConfirmationOpportunityIndex(records: [record, european], allKnownEntities: [])
        precondition(index.countryBandCoverage.filter { $0.totalQSOs > 0 }.map(\.country).sorted() == ["Asiatic Russia", "European Russia"])
        precondition(ConfirmationOpportunityIndex.matchesCountryFilter(for: record, selectedCountries: ["Asiatic Russia"]))
        precondition(!ConfirmationOpportunityIndex.matchesCountryFilter(for: record, selectedCountries: ["European Russia"]))
        precondition(record.fields == fields, "Grouping must never rewrite historical ADIF")
        let exported = generateADIF(originalContent: "", records: [record.fields, european.fields])
        let imported = parseADIF(content: exported).records.map { QSORecordModel(fields: $0) }
        let roundTrip = ConfirmationOpportunityIndex(records: imported, allKnownEntities: [])
        precondition(imported.map(\.fields) == [record.fields, european.fields])
        precondition(roundTrip.countryBandCoverage.reduce(0) { $0 + $1.totalQSOs } == 2)
        precondition(roundTrip.countryBandCoverage.filter { $0.totalQSOs > 0 }.map(\.country).sorted() == ["Asiatic Russia", "European Russia"])

        print("PASS Russian ADIF entity grouping, distinct continents, portable ambiguity, filtering and original-field preservation")
    }
}
