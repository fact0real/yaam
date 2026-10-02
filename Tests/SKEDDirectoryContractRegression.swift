import Foundation

@main
struct SKEDDirectoryContractRegression {
    static func main() throws {
        let request = try SKEDDirectoryContract.request(countryISO: " IR ", category: "qso", enrich: true,
                                                        token: "sample-token", userAgent: "YAAM-Regression/1")
        precondition(request.url?.absoluteString == "https://qrz-rank.asis.sh/api/v1/sked/ir?limit=19&category=qso&enrich=true")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer sample-token")
        do {
            _ = try SKEDDirectoryContract.request(countryISO: "ir", category: "qso", enrich: true,
                                                  token: nil, userAgent: "YAAM-Regression/1")
            preconditionFailure("SKED must require a token")
        } catch SKEDDirectoryError.missingToken {}
        do {
            _ = try SKEDDirectoryContract.request(countryISO: "ir", category: "qso", enrich: true,
                                                  token: "two words", userAgent: "YAAM-Regression/1")
            preconditionFailure("Malformed SKED tokens must be rejected")
        } catch SKEDDirectoryError.malformedToken {}
        let csvRequest = try QRZRankAPIContract.makeCountryLeaderboardCSVRequest(
            countryIso: "IR", category: "band", userAgent: "YAAM-Regression/1"
        )
        precondition(csvRequest.url?.absoluteString == "https://qrz-rank.asis.sh/api/v1/leaderboard/country/ir/csv?category=band")

        let fixture = Data("""
        {
          "country_iso":"ir", "country_name":"Iran", "category":"qso", "limit":19,
          "operators":[
            {"rank":1,"callsign":"EP1AAA","name":"A, B \\"Operator\\"","email":"operator@example.org",
             "score_qso":"23,926","val_score_qso":23926,"val_score_countries":158,"val_score_band":867,
             "sked_mailto":"mailto:operator@example.org?subject=SKED"},
            {"rank":2,"callsign":"EP2BBB","name":"Second operator","email":"", "val_score_qso":1200}
          ]
        }
        """.utf8)
        let qso = try SKEDDirectoryContract.decode(fixture, requestedISO: "ir", category: "qso")
        precondition(qso.operators.count == 2)
        precondition(qso.operators[0].score == 23926)
        precondition(qso.operators[0].confirmedQSOs == 23926)
        precondition(qso.operators[0].dxccCountries == 158)
        precondition(qso.operators[0].bandSlots == 867)
        precondition(qso.operators[0].name == "A, B \"Operator\"")
        precondition(qso.emailCount == 1)
        precondition(qso.allEmails == "operator@example.org")
        precondition(qso.operators[1].validEmail == nil)
        precondition(qso.csv.starts(with: Data([0xEF, 0xBB, 0xBF])))
        precondition(String(decoding: qso.csv, as: UTF8.self).contains("\"A, B \"\"Operator\"\"\""))
        let dxcc = try SKEDDirectoryContract.decode(fixture, requestedISO: "ir", category: "countries")
        precondition(dxcc.operators[0].score == 158)
        let band = try SKEDDirectoryContract.decode(fixture, requestedISO: "ir", category: "band")
        precondition(band.operators[0].score == 867)

        do {
            _ = try SKEDDirectoryContract.decode(Data(#"{"message":"unknown response"}"#.utf8), requestedISO: "ir", category: "qso")
            preconditionFailure("A malformed directory must be rejected")
        } catch SKEDDirectoryError.badResponse {}

        print("SKED directory contract regression passed.")
    }
}
