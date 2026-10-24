import Foundation

nonisolated struct QSLGraylistMailRecipient: Identifiable, Sendable {
    let entry: QSLGraylistEntry
    let records: [QSORecordModel]
    let email: String
    var id: String { entry.callsign }
}

nonisolated enum QSLGraylistMail {
    static let historyKind = "QSL_CONFIRMATION_REQUEST"

    // The entries are a snapshot of the visible list, independent of log-table filters.
    static func recipients(entries: [QSLGraylistEntry], records: [QSORecordModel],
                           profileID: UUID) -> [QSLGraylistMailRecipient] {
        let byCall = Dictionary(grouping: records.filter {
            let owner = QSLGraylistIndex.clean($0.fields["APP_YAAM_STATION_PROFILE_ID"] ?? "")
            return owner.isEmpty || owner == profileID.uuidString.uppercased()
        }, by: { QSLGraylistIndex.clean($0.fields["CALL"] ?? "") })
        var calls = Set<String>()
        return entries.compactMap { entry in
            guard calls.insert(entry.callsign).inserted else { return nil }
            let all = (byCall[entry.callsign] ?? []).filter { entry.recordIDs.contains($0.id) }
                .sorted { ($0.fields["QSO_DATE"] ?? "") + ($0.fields["TIME_ON"] ?? "") >
                    ($1.fields["QSO_DATE"] ?? "") + ($1.fields["TIME_ON"] ?? "") }
            guard !all.contains(where: \.isConfirmed) else { return nil }
            var keys = Set<String>()
            let distinct = all.filter {
                let key = QSOIdentity.exactKey(fields: $0.fields)
                return !key.isEmpty && keys.insert(key).inserted
            }
            guard distinct.count >= 3 else { return nil }
            let email = all.compactMap { $0.fields["EMAIL"] }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: isUsableEmail) ?? ""
            return QSLGraylistMailRecipient(entry: entry, records: distinct, email: email)
        }
    }

    static func isUsableEmail(_ email: String) -> Bool {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = clean.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") &&
            !parts[1].hasPrefix(".") && !clean.hasPrefix("-") &&
            !clean.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) } &&
            !clean.contains(",") && !clean.contains(";")
    }
}
