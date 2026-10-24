import Foundation

nonisolated enum LocalClusterWirePolicy {
    static func line(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            $0.value >= 32 && $0.value != 127 && !CharacterSet.controlCharacters.contains($0)
        }.prefix(512)))
    }

    static func xml(_ text: String) -> String {
        line(text).replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
