import Foundation

/// A single outgoing message may cover several incoming requests from one station.
struct QRZIncomingBulkRequest {
    let id: String
    let callsign: String
    let qsoDate: String
}

struct QRZIncomingBulkRecipient: Identifiable, Equatable {
    let callsign: String
    let requestIDs: [String]
    let qsoDates: [String]
    var id: String { callsign }
}

enum QRZIncomingBulkMail {
    static let historyKind = "QRZ_INCOMING_DETAILS"

    static let defaultSubject = "Could you help me recover our QSO details? - {my_callsign}"
    static let defaultBody = """
    Hi {name} ({callsign}),

    I noticed your incoming QRZ Logbook confirmation request for {qso_dates}. Those contacts don't appear in my local log, so I'd like to check the details with you rather than guess.

    Could you please send me the UTC time, band or frequency, mode, and the reports we exchanged? I'll compare them carefully with my records and confirm the matching contact in QRZ.

    Sorry for the extra step, and thanks for helping me sort this out.

    Best 73,
    {my_callsign}
    """

    static func group(_ requests: [QRZIncomingBulkRequest]) -> [QRZIncomingBulkRecipient] {
        var order: [String] = []
        var grouped: [String: ([String], [String])] = [:]
        for request in requests {
            let call = request.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !call.isEmpty else { continue }
            if grouped[call] == nil {
                order.append(call)
                grouped[call] = ([], [])
            }
            let date = formattedDate(request.qsoDate)
            if !(grouped[call]?.0.contains(request.id) ?? false) {
                grouped[call]?.0.append(request.id)
            }
            if !date.isEmpty && !(grouped[call]?.1.contains(date) ?? false) {
                grouped[call]?.1.append(date)
            }
        }
        return order.compactMap { call in
            guard let entry = grouped[call] else { return nil }
            return QRZIncomingBulkRecipient(callsign: call, requestIDs: entry.0,
                                            qsoDates: entry.1.sorted())
        }
    }

    static func render(_ template: String, recipient: QRZIncomingBulkRecipient,
                       name: String, myCallsign: String) -> String {
        let greeting = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let dates = recipient.qsoDates.isEmpty
            ? "the date shown in your QRZ request"
            : recipient.qsoDates.joined(separator: ", ")
        return template
            .replacingOccurrences(of: "{name}", with: greeting.isEmpty ? recipient.callsign : greeting)
            .replacingOccurrences(of: "{callsign}", with: recipient.callsign)
            .replacingOccurrences(of: "{qso_dates}", with: dates)
            .replacingOccurrences(of: "{request_count}", with: String(recipient.requestIDs.count))
            .replacingOccurrences(of: "{my_callsign}", with: myCallsign)
    }

    static func hasUnresolvedFields(_ text: String) -> Bool {
        text.range(of: #"\{[A-Za-z_][A-Za-z0-9_]*\}"#, options: .regularExpression) != nil
    }

    static func isUsableEmail(_ email: String) -> Bool {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = clean.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty &&
            parts[1].contains(".") && !parts[1].hasPrefix(".") &&
            !clean.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "," || $0 == ";" })
    }

    private static func formattedDate(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = clean.filter(\.isNumber)
        guard digits.count == 8 else { return clean }
        return "\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.suffix(2))"
    }
}
