import Foundation

@main
struct CSVExportSafetyRegression {
    static func main() throws {
        precondition(CSVExportSafety.cell("=HYPERLINK(\"https://x\")") == "\"'=HYPERLINK(\"\"https://x\"\")\"")
        precondition(CSVExportSafety.cell(" \t+SUM(1,2)") == "\"' \t+SUM(1,2)\"")
        precondition(CSVExportSafety.cell("ordinary") == "\"ordinary\"")
        let source = Data("Name,Notes\r\n\"=2+3\",\"line 1\nline 2\"\r\nA,\"B\"\"C\"\r\n".utf8)
        let output = try CSVExportSafety.sanitized(source)
        let text = String(decoding: output, as: UTF8.self)
        precondition(text.contains("\"'=2+3\""))
        precondition(text.contains("\"line 1\nline 2\""))
        precondition(text.contains("\"B\"\"C\""))
        do {
            _ = try CSVExportSafety.sanitized(Data("\"unterminated".utf8))
            preconditionFailure("Malformed CSV accepted")
        } catch CSVExportSafety.CSVError.malformedCSV {}
        print("CSV export safety regression passed")
    }
}
