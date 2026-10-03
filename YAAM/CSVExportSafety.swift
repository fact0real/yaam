import Foundation

nonisolated enum CSVExportSafety {
    enum CSVError: Error { case invalidEncoding, malformedCSV }

    static func cell(_ value: String) -> String {
        let leading = value.unicodeScalars.drop(while: {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
                || CharacterSet(charactersIn: "\u{FEFF}\u{200B}\u{200C}\u{200D}").contains($0)
        })
        let dangerous = leading.first.map { "=+-@".unicodeScalars.contains($0) } ?? false
        let escaped = (dangerous ? "'" : "") + value
        return "\"" + escaped.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func sanitized(_ data: Data) throws -> Data {
        guard data.count <= 20_000_000, var source = String(data: data, encoding: .utf8) else {
            throw CSVError.invalidEncoding
        }
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }
        source = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var afterQuote = false
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            if quoted {
                if character == "\"" {
                    if next < source.endIndex && source[next] == "\"" {
                        field.append("\"")
                        index = source.index(after: next)
                        continue
                    }
                    quoted = false
                    afterQuote = true
                } else { field.append(character) }
            } else if character == "," || character == "\n" {
                row.append(field)
                field = ""
                afterQuote = false
                if character != "," {
                    rows.append(row)
                    row = []
                }
            } else if character == "\"" && field.isEmpty && !afterQuote {
                quoted = true
            } else {
                if afterQuote || character == "\"" { throw CSVError.malformedCSV }
                field.append(character)
            }
            index = next
        }
        guard !quoted else { throw CSVError.malformedCSV }
        if !row.isEmpty || !field.isEmpty || afterQuote {
            row.append(field)
            rows.append(row)
        }
        let output = "\u{FEFF}" + rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
        return Data(output.utf8)
    }
}
