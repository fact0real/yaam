import Foundation

// Standalone: swiftc -parse-as-library Tests/FormURLEncodingRegression.swift YAAM/FormURLEncoding.swift -o /tmp/fue && /tmp/fue
@main
struct FormURLEncodingRegression {
    /// What a form decoder (PHP, ColdFusion, ...) does with a field: "+" is a space, then %XX.
    static func formDecoded(_ field: String) -> String {
        field.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
    }

    static func main() {
        let values = ["pass+word 1&2", "<COMMENT:6>73 +1 ", "plain"]
        let body = String(decoding: FormURLEncoding.body(values.enumerated().map {
            URLQueryItem(name: "f\($0.offset)", value: $0.element)
        }) ?? Data(), as: UTF8.self)

        precondition(!body.contains("+"), "a literal + would be read as a space: \(body)")
        precondition(body.contains("pass%2Bword%201%262"), body)

        let fields = body.split(separator: "&").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
        precondition(fields.map { formDecoded($0[1]) } == values, "form-decoded values must round-trip: \(body)")

        // GET requests carrying credentials in the query
        var components = URLComponents(string: "https://example.org/report")!
        FormURLEncoding.setQuery([URLQueryItem(name: "password", value: "pass+word 1&2")], on: &components)
        let url = components.url?.absoluteString ?? ""
        precondition(url == "https://example.org/report?password=pass%2Bword%201%262", url)

        // Hand-built query values (LoTW report URL)
        precondition(FormURLEncoding.encodeValue("a+b&c=d é") == "a%2Bb%26c%3Dd%20%C3%A9")
        print("Form URL encoding regression tests passed.")
    }
}
