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

        let quotaRequest = try QRZRankAPIContract.makeQuotaRequest(
            token: "qrz_test-token",
            userAgent: "YAAM-Regression/1"
        )
        precondition(quotaRequest.httpMethod == "GET")
        precondition(quotaRequest.url?.absoluteString == "https://qrz-rank.asis.sh/api/v1/quota")
        precondition(quotaRequest.value(forHTTPHeaderField: "Authorization") == "Bearer qrz_test-token")

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
                "limit": "2500",
                "used": 61,
                "remaining_requests": "2439",
                "can_make_request": true,
                "exhausted": false,
                "unlimited": false,
                "status": "active",
                "resets_at": "2026-08-24T00:00:00Z",
                "reset_in_seconds": 7200
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
        precondition(envelope.quota?.limit == 2_500)
        precondition(envelope.quota?.used == 61)
        precondition(envelope.quota?.effectiveRemaining == 2_439)
        precondition(envelope.quota?.allowsRequest == true)

        let finiteQuotaData = Data(
            """
            {
              "api_version": "v1",
              "quota": {
                "limit": 2500,
                "used": 2500,
                "remaining_requests": 0,
                "can_make_request": false,
                "exhausted": true,
                "unlimited": false,
                "status": "exhausted"
              }
            }
            """.utf8
        )
        let finiteQuota = try QRZRankAPIContract.decodeQuota(finiteQuotaData).quota
        precondition(finiteQuota.effectiveRemaining == 0)
        precondition(!finiteQuota.allowsRequest)

        let unlimitedQuotaData = Data(
            """
            {
              "api_version": "v1",
              "quota": {
                "limit": null,
                "used": null,
                "remaining_requests": null,
                "can_make_request": true,
                "exhausted": false,
                "unlimited": true,
                "status": "unlimited"
              }
            }
            """.utf8
        )
        let unlimitedQuota = try QRZRankAPIContract.decodeQuota(unlimitedQuotaData).quota
        precondition(unlimitedQuota.isUnlimited)
        precondition(unlimitedQuota.effectiveRemaining == nil)
        precondition(unlimitedQuota.allowsRequest)

        let errorData = Data(
            #"{"error":{"code":"invalid_token","message":"Token is invalid"}}"#.utf8
        )
        let details = QRZRankAPIContract.decodeError(errorData)
        precondition(details?.code == "invalid_token")
        precondition(details?.message == "Token is invalid")

        print("QRZ Rank API contract regression passed.")
    }
}
