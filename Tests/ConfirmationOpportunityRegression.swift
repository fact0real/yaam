import Foundation

nonisolated func canonicalCountryName(_ country: String) -> String {
    switch country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "republic of south africa", "south africa": return "South Africa"
    default: return country.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum AmateurBandPlan {
    static func band(for rawValue: String) -> String? {
        guard let frequency = Double(rawValue) else { return nil }
        switch frequency {
        case 14.0...14.35: return "20m"
        case 18.068...18.168: return "17m"
        default: return nil
        }
    }
}

nonisolated struct QSORecordModel: Identifiable, Sendable {
    let id: UUID
    let fields: [String: String]

    init(id: UUID = UUID(), fields: [String: String]) {
        self.id = id
        self.fields = fields
    }

    subscript(key: String) -> String {
        fields[key] ?? ""
    }

    var isConfirmed: Bool {
        ["LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "EQSL_QSL_RCVD", "QSL_RCVD"]
            .contains { fields[$0]?.uppercased() == "Y" }
    }
}

@main
struct ConfirmationOpportunityRegression {
    static func main() {
        let confirmedCameroon = QSORecordModel(fields: [
            "COUNTRY": "Cameroon",
            "BAND": "20M",
            "GRIDSQUARE": "JJ11aa",
            "LOTW_QSL_RCVD": "Y"
        ])
        let newCameroonBandAndGrid = QSORecordModel(fields: [
            "COUNTRY": "Cameroon",
            "BAND": "17M",
            "GRIDSQUARE": "JJ22zz"
        ])
        let existingCameroonBandAndGrid = QSORecordModel(fields: [
            "COUNTRY": "Cameroon",
            "BAND": "20M",
            "GRIDSQUARE": "JJ11bb"
        ])
        let confirmedSouthAfrica = QSORecordModel(fields: [
            "COUNTRY": "Republic of South Africa",
            "FREQ": "14.074",
            "LAT": "-30.0",
            "LON": "25.0",
            "QSL_RCVD": "Y"
        ])
        let pendingSouthAfrica = QSORecordModel(fields: [
            "COUNTRY": "South Africa",
            "BAND": "17m",
            "LAT": "-31.0",
            "LON": "26.0"
        ])

        let index = ConfirmationOpportunityIndex(records: [
            confirmedCameroon,
            newCameroonBandAndGrid,
            existingCameroonBandAndGrid,
            confirmedSouthAfrica,
            pendingSouthAfrica
        ])

        let newCredit = require(index.opportunity(for: newCameroonBandAndGrid.id))
        precondition(newCredit.addsCountryBandCredit)
        precondition(newCredit.addsGridCredit)
        precondition(newCredit.grid == "JJ22")

        let existingCredit = require(index.opportunity(for: existingCameroonBandAndGrid.id))
        precondition(!existingCredit.addsCountryBandCredit)
        precondition(!existingCredit.addsGridCredit)

        let cameroon = require(index.countryBandCoverage.first { $0.country == "Cameroon" })
        precondition(cameroon.bands.first { $0.band == "20m" }?.state == .confirmed)
        precondition(cameroon.bands.first { $0.band == "17m" }?.state == .worked)
        precondition(cameroon.bands.first { $0.band == "15m" }?.state == .needed)

        let southAfrica = require(index.countryBandCoverage.first { $0.country == "South Africa" })
        precondition(southAfrica.bands.first { $0.band == "20m" }?.state == .confirmed)
        precondition(southAfrica.bands.first { $0.band == "17m" }?.state == .worked)
        precondition(index.opportunity(for: pendingSouthAfrica.id)?.grid != nil)

        print("Confirmation opportunity regression tests passed.")
    }

    private static func require<T>(_ value: T?) -> T {
        guard let value else { fatalError("Expected regression fixture value") }
        return value
    }
}
