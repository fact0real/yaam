import Foundation

nonisolated struct SKEDRegion: Identifiable, Sendable {
    let id: String
    let name: String
    let icon: String
}

nonisolated struct SKEDCountryOption: Identifiable, Sendable {
    let iso: String
    let regionID: String
    let serviceName: String
    var id: String { iso }
}

nonisolated struct SKEDUSState: Identifiable, Sendable {
    let code: String
    let name: String
    var id: String { code }
}

nonisolated struct SKEDGeographyCatalog: Sendable {
    let regions: [SKEDRegion]
    let countries: [SKEDCountryOption]
    let states: [SKEDUSState]

    func countries(in regionID: String) -> [SKEDCountryOption] {
        countries.filter { $0.regionID == regionID }
    }

    func region(for iso: String) -> String? {
        countries.first { $0.iso == iso.lowercased() }?.regionID
    }
}

nonisolated enum SKEDGeographyContract {
    static func request(path: String, token: String, userAgent: String) throws -> URLRequest {
        guard ["/api/v1/divisions", "/api/v1/countries", "/api/v1/us-states"].contains(path) else {
            throw SKEDDirectoryError.badResponse
        }
        let normalized = QRZRankAPIContract.normalizedToken(token)
        guard !normalized.isEmpty else { throw SKEDDirectoryError.missingToken }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard normalized.unicodeScalars.allSatisfy({ !forbidden.contains($0) }) else {
            throw SKEDDirectoryError.malformedToken
        }
        var components = URLComponents(url: QRZRankAPIContract.baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        guard let url = components.url else { throw SKEDDirectoryError.badResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(normalized)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func decode(divisions: Data, countries: Data, states: Data) throws -> SKEDGeographyCatalog {
        func rows(_ data: Data, key: String) throws -> [[String: Any]] {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = root[key] as? [[String: Any]] else { throw SKEDDirectoryError.badResponse }
            return rows
        }
        let regions = try rows(divisions, key: "divisions").compactMap { row -> SKEDRegion? in
            guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
            return SKEDRegion(id: id.lowercased(), name: name, icon: row["icon"] as? String ?? "🌐")
        }
        let validIDs = Set(regions.map(\.id))
        let countryOptions = try rows(countries, key: "countries").compactMap { row -> SKEDCountryOption? in
            guard let iso = (row["iso"] ?? row["country_iso"]) as? String,
                  let region = row["continent_id"] as? String,
                  validIDs.contains(region.lowercased()),
                  (2...3).contains(iso.count),
                  iso.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) })
            else { return nil }
            return SKEDCountryOption(iso: iso.lowercased(), regionID: region.lowercased(),
                                     serviceName: (row["country_name"] ?? row["name"]) as? String ?? iso.uppercased())
        }
        let stateOptions = try rows(states, key: "states").compactMap { row -> SKEDUSState? in
            guard let code = row["code"] as? String, code.count == 2,
                  code.unicodeScalars.allSatisfy(CharacterSet.letters.contains),
                  let name = row["name"] as? String else { return nil }
            return SKEDUSState(code: code.uppercased(), name: name)
        }
        guard regions.count == 8, countryOptions.count >= 200,
              countryOptions.contains(where: { $0.iso == "us" && $0.regionID == "na" }),
              stateOptions.count >= 50 else { throw SKEDDirectoryError.badResponse }
        return SKEDGeographyCatalog(regions: regions, countries: countryOptions, states: stateOptions)
    }
}

actor SKEDGeographyService {
    static let shared = SKEDGeographyService()
    private let session: URLSession
    private var cachedCatalog: SKEDGeographyCatalog?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    func fetch(token: String, userAgent: String) async throws -> SKEDGeographyCatalog {
        if let cachedCatalog { return cachedCatalog }
        let session = self.session
        @Sendable func read(_ path: String) async throws -> Data {
            let request = try SKEDGeographyContract.request(path: path, token: token, userAgent: userAgent)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SKEDDirectoryError.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw SKEDDirectoryError.server(http.statusCode, QRZRankAPIContract.decodeError(data)?.message ?? "")
            }
            return data
        }
        async let divisions = read("/api/v1/divisions")
        async let countries = read("/api/v1/countries")
        async let states = read("/api/v1/us-states")
        let (divisionData, countryData, stateData) = try await (divisions, countries, states)
        let catalog = try SKEDGeographyContract.decode(divisions: divisionData, countries: countryData, states: stateData)
        cachedCatalog = catalog
        return catalog
    }
}
