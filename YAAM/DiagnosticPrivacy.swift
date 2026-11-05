import Foundation

/// Defense in depth for diagnostics. Never use raw provider replies as status text.
nonisolated enum DiagnosticPrivacy {
    private static let rules: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: "(?im)[\"'](?:authorization|proxy-authorization|cookie|set-cookie)[\"']\\s*:\\s*[^\\r\\n]*"), "[private header removed]"),
        (try! NSRegularExpression(pattern: "(?im)\\b(?:authorization|proxy-authorization|cookie|set-cookie)\\s*:[^\\r\\n]*"), "[private header removed]"),
        (try! NSRegularExpression(pattern: "(?i)(https?://)[^\\s/]+@"), "$1[redacted]@"),
        (try! NSRegularExpression(pattern: "(?i)(https?://[^\\s?\\#]+)[?\\#][^\\s]*"), "$1?[redacted]"),
        (try! NSRegularExpression(pattern: "(?i)([\"']?\\b(?:password|passwd|pass|p|key|api[_-]?key|access[_-]?token|refresh[_-]?token|token|session(?:[_-]?(?:id|key))?|s)\\b[\"']?\\s*[:=]\\s*)(?:\"[^\"\\r\\n]*\"|'[^'\\r\\n]*'|[^\\s&;,<>]+)"), "$1[redacted]"),
        (try! NSRegularExpression(pattern: "(?is)(<(?:password|pass|key|session_id|session|token|api_key)>).*?(</[^>]+>)"), "$1[redacted]$2"),
    ]

    static func redacted(_ text: String) -> String {
        guard text.utf8.count <= 65_536 else { return "[Diagnostic omitted: size limit]" }
        var result = text
        for (expression, replacement) in rules {
            result = expression.stringByReplacingMatches(in: result,
                range: NSRange(result.startIndex..., in: result), withTemplate: replacement)
        }
        return result.components(separatedBy: .controlCharacters).joined(separator: " ")
    }
}
