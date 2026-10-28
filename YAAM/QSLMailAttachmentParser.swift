import Foundation

/// Parses locally imported RFC 822 mail. Each visual attachment is retained separately.
nonisolated enum QSLMailAttachmentParser {
    struct Attachment: Sendable { let filename: String; let data: Data }
    struct Message: Sendable {
        var from = ""
        var subject = ""
        var date = ""
        var body = ""
        var attachments: [Attachment] = []
    }

    static func parse(_ data: Data) -> Message {
        // Latin-1 provides a lossless one-byte representation while splitting MIME boundaries.
        let raw = String(data: data, encoding: .isoLatin1) ?? ""
        var message = Message()
        parsePart(raw, into: &message, root: true)
        return message
    }

    private static func parsePart(_ raw: String, into message: inout Message, root: Bool = false) {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard let separator = normalized.range(of: "\n\n") else { return }
        let headerText = String(normalized[..<separator.lowerBound])
            .replacingOccurrences(of: "\n[ \t]+", with: " ", options: .regularExpression)
        var headers: [String: String] = [:]
        for line in headerText.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let body = String(normalized[separator.upperBound...])
        if root {
            message.from = decodedHeader(headers["from"] ?? "")
            message.subject = decodedHeader(headers["subject"] ?? "")
            message.date = headers["date"] ?? ""
        }
        let type = headers["content-type"] ?? "text/plain"
        if type.lowercased().hasPrefix("multipart/"), let boundary = parameter("boundary", in: type) {
            for part in body.components(separatedBy: "--" + boundary).dropFirst() {
                if part.hasPrefix("--") { break }
                parsePart(part.trimmingCharacters(in: .newlines), into: &message)
            }
            return
        }
        let bytes: Data
        switch headers["content-transfer-encoding"]?.lowercased() {
        case "base64":
            guard let decoded = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else { return }
            bytes = decoded
        case "quoted-printable": bytes = quotedPrintable(body)
        default: bytes = body.data(using: .isoLatin1) ?? Data()
        }
        let disposition = headers["content-disposition"] ?? ""
        let name = parameter("filename", in: disposition) ?? parameter("name", in: type) ?? ""
        let mime = type.components(separatedBy: ";").first?.lowercased() ?? ""
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        if mime.hasPrefix("image/") || mime == "application/pdf" || ["png", "jpg", "jpeg", "webp", "heic", "pdf"].contains(ext) {
            guard !bytes.isEmpty else { return }
            let fallback = mime == "application/pdf" ? "QSL.pdf" : "QSL.jpg"
            message.attachments.append(Attachment(filename: decodedHeader(name.isEmpty ? fallback : name), data: bytes))
        } else if mime == "text/plain" || (mime == "text/html" && message.body.isEmpty) {
            let text = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1) ?? ""
            if mime == "text/plain" { message.body += text + "\n" }
            else { message.body = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression) }
        }
    }

    private static func parameter(_ name: String, in value: String) -> String? {
        let pattern = "(?:^|;)\\s*" + name + "\\s*=\\s*(?:\"([^\"]*)\"|([^;\\s]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        for index in [1, 2] {
            if let range = Range(match.range(at: index), in: value) { return String(value[range]) }
        }
        return nil
    }

    private static func quotedPrintable(_ value: String) -> Data {
        let bytes = Array(value.data(using: .isoLatin1) ?? Data(value.utf8))
        var output = Data(), index = 0
        while index < bytes.count {
            if bytes[index] == 61 {
                if index + 1 < bytes.count && bytes[index + 1] == 10 { index += 2; continue }
                if index + 2 < bytes.count,
                   let byte = UInt8(String(bytes: bytes[(index + 1)...(index + 2)], encoding: .ascii) ?? "", radix: 16) {
                    output.append(byte); index += 3; continue
                }
            }
            // Non-ASCII unescaped bytes must retain their original Latin-1 value.
            output.append(bytes[index]); index += 1
        }
        return output
    }

    private static func decodedHeader(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?=") else { return value }
        var result = value
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let whole = Range(match.range, in: result), let kind = Range(match.range(at: 2), in: value),
                  let encoded = Range(match.range(at: 3), in: value) else { continue }
            let content = String(value[encoded])
            let data = value[kind].lowercased() == "b" ? Data(base64Encoded: content) : quotedPrintable(content.replacingOccurrences(of: "_", with: " "))
            if let data, let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                result.replaceSubrange(whole, with: decoded)
            }
        }
        return result
    }
}
