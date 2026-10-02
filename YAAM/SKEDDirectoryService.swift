import Foundation

nonisolated struct SKEDOperator: Identifiable, Sendable {
    var id: String { callsign }
    let rank: Int
    let callsign: String
    let name: String?
    let email: String?
    let score: Int?
    let mailto: URL?

    var validEmail: String? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty, !email.contains(where: { $0.isWhitespace }),
              email.contains("@"), !email.contains(";") else { return nil }
        return email
    }
}

nonisolated struct SKEDDirectory: Sendable {
    let countryISO: String
    let countryName: String
    let category: String
    let operators: [SKEDOperator]

    var allEmails: String {
        var seen = Set<String>()
        return operators.compactMap(\.validEmail).filter {
            seen.insert($0.lowercased()).inserted
        }.joined(separator: ";")
    }

    var emailCount: Int { operators.filter { $0.validEmail != nil }.count }

    var csv: Data {
        func quoted(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = ["Rank,Callsign,Name,Email,Score,Country,Category"] + operators.map { item in
            [String(item.rank), item.callsign, item.name ?? "", item.validEmail ?? "",
             item.score.map(String.init) ?? "", countryName, category]
                .map(quoted).joined(separator: ",")
        }
        return Data(("\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n").utf8)
    }
}

nonisolated enum SKEDDirectoryError: LocalizedError, Sendable {
    case invalidCountry
    case badResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidCountry: return "Select a valid country."
        case .badResponse: return "The SKED service returned an unexpected response."
        case .server(let status, let message):
            return message.isEmpty ? "SKED service returned HTTP \(status)." : "SKED service: \(message)"
        }
    }
}

nonisolated enum SKEDDirectoryContract {
    static func request(countryISO: String, category: String, enrich: Bool, token: String?, userAgent: String) throws -> URLRequest {
        let iso = countryISO.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard iso.count == 2, iso.unicodeScalars.allSatisfy(CharacterSet.letters.contains),
              ["qso", "countries", "band"].contains(category) else { throw SKEDDirectoryError.invalidCountry }
        var components = URLComponents(url: QRZRankAPIContract.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/sked/\(iso)"
        components.queryItems = [URLQueryItem(name: "limit", value: "19"),
                                 URLQueryItem(name: "category", value: category),
                                 URLQueryItem(name: "enrich", value: enrich ? "true" : "false")]
        guard let url = components.url else { throw SKEDDirectoryError.badResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = enrich ? 60 : 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let token, !QRZRankAPIContract.normalizedToken(token).isEmpty {
            request.setValue("Bearer \(QRZRankAPIContract.normalizedToken(token))", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func decode(_ data: Data, requestedISO: String, category: String) throws -> SKEDDirectory {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SKEDDirectoryError.badResponse
        }
        let body = root["data"] as? [String: Any] ?? root
        guard let rows = (body["operators"] ?? body["leaderboard"] ?? body["stations"] ?? body["sked_directory"] ?? body["results"]) as? [[String: Any]] else {
            throw SKEDDirectoryError.badResponse
        }
        func string(_ object: [String: Any], _ keys: [String]) -> String? {
            for key in keys {
                if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
                if let value = object[key] as? NSNumber { return value.stringValue }
            }
            return nil
        }
        let operators = rows.prefix(19).enumerated().compactMap { offset, row -> SKEDOperator? in
            guard let callsign = string(row, ["callsign", "call"])?.uppercased() else { return nil }
            let rank = Int(string(row, ["rank", "position"]) ?? "") ?? offset + 1
            let name = string(row, ["full_name", "name", "operator_name", "qrz_name"])
            let email = string(row, ["email", "email_address", "qrz_email"])
            let scoreKeys: [String]
            switch category {
            case "countries": scoreKeys = ["val_score_countries", "score_countries", "score"]
            case "band": scoreKeys = ["val_score_band", "score_band", "score"]
            default: scoreKeys = ["val_score_qso", "score_qso", "score"]
            }
            let score = Int((string(row, scoreKeys) ?? "").replacingOccurrences(of: ",", with: ""))
            let mailto = string(row, ["sked_mailto"]).flatMap(URL.init(string:))
            return SKEDOperator(rank: rank, callsign: callsign, name: name, email: email, score: score, mailto: mailto)
        }
        guard rows.isEmpty || !operators.isEmpty else { throw SKEDDirectoryError.badResponse }
        return SKEDDirectory(countryISO: string(body, ["country_iso", "iso"]) ?? requestedISO,
                             countryName: string(body, ["country_name", "name"]) ?? requestedISO.uppercased(),
                             category: category, operators: operators)
    }
}

actor SKEDDirectoryService {
    static let shared = SKEDDirectoryService()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    func fetch(countryISO: String, category: String, enrich: Bool, token: String?, userAgent: String) async throws -> SKEDDirectory {
        let request = try SKEDDirectoryContract.request(countryISO: countryISO, category: category,
                                                        enrich: enrich, token: token, userAgent: userAgent)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SKEDDirectoryError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = QRZRankAPIContract.decodeError(data)?.message ?? ""
            throw SKEDDirectoryError.server(http.statusCode, message)
        }
        return try SKEDDirectoryContract.decode(data, requestedISO: countryISO, category: category)
    }
}
