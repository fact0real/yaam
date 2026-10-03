import Foundation

@main
struct SKEDGeographyContractRegression {
    static func main() throws {
        let divisions = ["me", "eu", "as", "af", "na", "sam", "oc", "an"].map {
            ["id": $0, "name": $0.uppercased(), "icon": "🌐"]
        }
        var countries: [[String: Any]] = [
            ["iso": "ir", "continent_id": "me", "country_name": "Iran"],
            ["iso": "us", "continent_id": "na", "country_name": "US"],
            ["iso": "br", "continent_id": "sam", "country_name": "Brazil"],
            ["iso": "bq1", "continent_id": "na", "country_name": "BQ1"],
            ["iso": "x1", "continent_id": "an", "country_name": "X1"],
            ["iso": "x2", "continent_id": "an", "country_name": "X2"]
        ]
        for index in 0..<198 {
            let first = Character(UnicodeScalar(65 + index / 26)!)
            let second = Character(UnicodeScalar(65 + index % 26)!)
            countries.append(["iso": "\(first)\(second)", "continent_id": "eu", "country_name": "Sample \(index)"])
        }
        let states = (0..<50).map { index in
            let first = Character(UnicodeScalar(65 + index / 26)!)
            let second = Character(UnicodeScalar(65 + index % 26)!)
            return ["code": "\(first)\(second)", "name": "State \(index)"]
        }
        func data(_ value: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: value)
        }
        let catalog = try SKEDGeographyContract.decode(
            divisions: data(["divisions": divisions]),
            countries: data(["countries": countries]),
            states: data(["states": states]))
        precondition(catalog.regions.count == 8)
        precondition(catalog.region(for: "IR") == "me")
        precondition(catalog.countries(in: "sam").map(\.iso) == ["br"])
        precondition(catalog.countries(in: "na").contains(where: { $0.iso == "bq1" }))
        precondition(catalog.countries(in: "an").map(\.iso) == ["x1", "x2"])
        precondition(catalog.states.count == 50)
        let request = try SKEDGeographyContract.request(path: "/api/v1/us-states", token: "sample-token",
                                                        userAgent: "YAAM-Regression/1")
        precondition(request.url?.absoluteString == "https://qrz-rank.asis.sh/api/v1/us-states")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer sample-token")
        print("SKED geography contract regression passed")
    }
}
