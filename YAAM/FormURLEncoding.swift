import Foundation

/// Body for application/x-www-form-urlencoded POSTs. URLComponents leaves "+" unescaped, and form decoders
/// read "+" as a space, so a "+" in a password or an ADIF value would reach the server as a space.
/// Pure Foundation, so it can be tested standalone:
///   swiftc -parse-as-library Tests/FormURLEncodingRegression.swift YAAM/FormURLEncoding.swift -o /tmp/fue && /tmp/fue
nonisolated enum FormURLEncoding {
    static func body(_ items: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
    }

    /// Same fix for GET requests that carry credentials in the URL query.
    static func setQuery(_ items: [URLQueryItem], on components: inout URLComponents) {
        components.queryItems = items
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }

    /// One query value, escaping everything except unreserved ASCII (".urlQueryAllowed" keeps + & = as they are).
    static func encodeValue(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: unreserved)
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
