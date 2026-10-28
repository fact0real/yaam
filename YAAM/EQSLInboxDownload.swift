import Foundation

/// DownloadInBox returns a landing page, followed by a temporary ADIF file.
nonisolated enum EQSLInboxDownload {
    static func failure(in text: String) -> String? {
        let lower = text.lowercased()
        let known: [(String, String)] = [
            ("bad password", "eQSL rejected the username or password."),
            ("no such callsign", "eQSL could not find this callsign."),
            ("login failed", "eQSL login failed."),
            ("not yet logged in", "eQSL requires you to sign in."),
            ("no match on username/password", "eQSL could not authenticate this account for the QSO date."),
            ("overlapping accounts", "eQSL reports overlapping station accounts for this QSO date."),
            ("missing qsomode", "eQSL rejected the request because its mode is missing."),
            ("cannot find that log entry", "eQSL could not find this QSO."),
            ("not authorized", "eQSL did not authorize this card download."),
            ("must be at least silver", "eQSL requires a Silver membership for this download."),
            ("graphic not available", "The sender has no downloadable eQSL graphic."),
            ("ip address has been blocked", "eQSL has blocked this network address; contact eQSL support.")
        ]
        for (needle, message) in known where lower.contains(needle) { return message }
        if lower.contains("error:") { return "eQSL returned an error. Check the account and QTH nickname." }
        return nil
    }

    static func adifURL(in text: String, relativeTo base: URL) -> URL? {
        let pattern = #"(?i)href\s*=\s*["']([^"']+\.(?:adi|adif|txt)(?:\?[^"']*)?)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text),
                  let url = URL(string: String(text[range]).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL,
                  url.scheme?.lowercased() == "https", ["eqsl.cc", "www.eqsl.cc"].contains(url.host?.lowercased() ?? ""),
                  url.user == nil, url.password == nil else { continue }
            return url
        }
        return nil
    }

    static func download(session: URLSession, url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        try validate(response)
        let text = decode(data)
        if let message = failure(in: text) { throw error(message, authenticationFailure: authenticationFailure(in: text)) }
        if isADIF(text) { return text }
        guard let file = adifURL(in: text, relativeTo: response.url ?? url) else {
            throw error("eQSL returned a page without a downloadable ADIF file. The inbox could not be read.")
        }
        let (fileData, fileResponse) = try await session.data(from: file)
        try validate(fileResponse)
        let adif = decode(fileData)
        if let message = failure(in: adif) { throw error(message, authenticationFailure: authenticationFailure(in: adif)) }
        guard isADIF(adif) else { throw error("The eQSL download was not an ADIF inbox file.") }
        return adif
    }

    private static func isADIF(_ text: String) -> Bool {
        text.range(of: #"(?i)<(?:eoh|eor|call:\d+)"#, options: .regularExpression) != nil
    }
    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw error("The eQSL server could not complete the request.")
        }
    }
    private static func authenticationFailure(in text: String) -> Bool {
        let text = text.lowercased()
        return ["bad password", "no such callsign", "login failed", "not yet logged in", "no match on username/password"].contains { text.contains($0) }
    }
    static func error(_ message: String, authenticationFailure: Bool = false) -> NSError {
        NSError(domain: "EQSLService", code: authenticationFailure ? 401 : 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
