import Foundation

@main
enum QRZRankAPIContractRegression {
    static func main() throws {
        let request = try QRZRankAPIContract.makeRequest(
            callsign: " ep2aes ",
            token: " qrz_test-token ",
            userAgent: "YAAM-Regression/1"
        )
        precondition(request.httpMethod == "GET")
        precondition(request.url?.absoluteString == "https://qrz-rank.asis.sh/api/v1/rank/EP2AES")
        precondition(request.url?.query == nil)
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer qrz_test-token")

        let prefixedRequest = try QRZRankAPIContract.makeRequest(
            callsign: "EP2AES",
            token: "Bearer qrz_prefixed-token",
            userAgent: "YAAM-Regression/1"
        )
        precondition(prefixedRequest.value(forHTTPHeaderField: "Authorization") == "Bearer qrz_prefixed-token")

        do {
            _ = try QRZRankAPIContract.makeRequest(
                callsign: "EP2AES",
                token: "",
                userAgent: "YAAM-Regression/1"
            )
            preconditionFailure("An empty token must be rejected")
        } catch let error as QRZRankAPIContractError {
            precondition(error == .missingToken)
        }

        do {
            _ = try QRZRankAPIContract.makeRequest(
                callsign: "EP2AES",
                token: "qrz_bad token",
                userAgent: "YAAM-Regression/1"
            )
            preconditionFailure("Embedded whitespace must be rejected")
        } catch let error as QRZRankAPIContractError {
            precondition(error == .malformedToken)
        }

        let successData = Data(
            """
            {
              "api_version": "v1",
              "data": {
                "bid": 123,
                "callsign": "EP2AES",
                "country_iso": "IR",
                "country_name": "Iran",
                "rank_qso": 4332,
                "score_qso": "99",
                "rank_countries": "130",
                "score_countries": 138,
                "rank_band": 777,
                "score_band": "20"
              },
              "quota": {
                "limit": "1440",
                "used": 1,
                "remaining": "1439",
                "unlimited": false
              }
            }
            """.utf8
        )
        let envelope = try QRZRankAPIContract.decodeSuccess(successData)
        precondition(envelope.data.callsign == "EP2AES")
        precondition(envelope.data.bid == "123")
        precondition(envelope.data.rank_qso == "4332")
        precondition(envelope.data.rank_band == "777")
        precondition(envelope.data.score_countries == "138")
        precondition(envelope.quota?.limit == 1_440)
        precondition(envelope.quota?.used == 1)
        precondition(envelope.quota?.remaining == 1_439)

        let errorData = Data(
            #"{"error":{"code":"invalid_token","message":"Token is invalid"}}"#.utf8
        )
        let details = QRZRankAPIContract.decodeError(errorData)
        precondition(details?.code == "invalid_token")
        precondition(details?.message == "Token is invalid")

        print("QRZ Rank API contract regression passed.")
    }
}
