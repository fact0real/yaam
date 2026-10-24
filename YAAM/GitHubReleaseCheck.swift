import Foundation

nonisolated enum GitHubReleaseCheck {
    enum Outcome: Equatable {
        case available(String, URL)
        case current
        case failed(String)
    }

    private static func components(_ raw: String) -> [Int]? {
        let text = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(fields.count) else { return nil }
        var numbers: [Int] = []
        for field in fields {
            guard !field.isEmpty, field.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(field) else { return nil }
            numbers.append(number)
        }
        return numbers + Array(repeating: 0, count: 4 - numbers.count)
    }

    static func evaluate(data: Data?, response: URLResponse?, currentVersion: String) -> Outcome {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return .failed("GitHub did not return a successful release response. Try again later.")
        }
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, let latest = components(tag),
              let current = components(currentVersion), json["draft"] as? Bool != true,
              json["prerelease"] as? Bool != true else {
            return .failed("GitHub returned an unrecognized release. The installed version could not be checked.")
        }
        guard current.lexicographicallyPrecedes(latest) else { return .current }
        guard let rawURL = json["html_url"] as? String, let url = URL(string: rawURL),
              url.scheme == "https", url.host?.lowercased() == "github.com", url.user == nil,
              url.password == nil, url.port == nil,
              url.path.hasPrefix("/fact0real/yaam/releases/tag/") else {
            return .failed("The release page address was not recognized. Open YAAM’s GitHub releases directly.")
        }
        return .available(tag, url)
    }
}
