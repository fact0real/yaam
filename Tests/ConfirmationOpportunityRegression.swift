import Foundation
@testable import YAAM

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

        // Kosovo DXCC entity verification
        let kosovo = require(index.countryBandCoverage.first { $0.country == "Kosovo" })
        precondition(!kosovo.isWorked)
        precondition(!kosovo.isConfirmed)
        precondition(kosovo.neededBandCount > 0)

        // Verify Kosovo callsign resolution with empty COUNTRY field
        let kosovoCallsignQSO = QSORecordModel(fields: [
            "CALL": "Z60A",
            "BAND": "20m",
            "LOTW_QSL_RCVD": "Y"
        ])
        let kosovoIndex = ConfirmationOpportunityIndex(records: [kosovoCallsignQSO])
        let workedKosovo = require(kosovoIndex.countryBandCoverage.first { $0.country == "Kosovo" })
        precondition(workedKosovo.isConfirmed)
        precondition(workedKosovo.bands.first { $0.band == "20m" }?.state == .confirmed)

        print("Confirmation opportunity regression tests passed.")
    }

    private static func require<T>(_ value: T?) -> T {
        guard let value else { fatalError("Expected regression fixture value") }
        return value
    }
}
