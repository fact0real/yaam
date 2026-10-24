import Foundation

// The adapter uses QSORecordModel's received/sent semantics, shared with the logbook.
nonisolated protocol QSLGraylistRecord: Sendable {
    var id: UUID { get }
    var fields: [String: String] { get }
    var isConfirmed: Bool { get }
    var isAnyQSLSent: Bool { get }
}

nonisolated struct QSLGraylistEntry: Identifiable, Equatable, Sendable {
    var id: String { callsign }
    let callsign: String
    let country: String
    let contactCount: Int
    let sentCount: Int
    let unresolvedCount: Int
    let bands: [String]
    let modes: [String]
    let dates: [Date]
    let recordIDs: Set<UUID>

    var oldestContact: Date? { dates.first }
    var latestContact: Date? { dates.last }
    var evidence: String { "\(contactCount) QSOs · 0 confirmed" }

    func matureContactCount(waitingDays: Int, now: Date) -> Int {
        let cutoff = now.addingTimeInterval(-Double(max(0, waitingDays)) * 86_400)
        return dates.filter { $0 <= cutoff }.count
    }

    func isMature(waitingDays: Int, now: Date) -> Bool {
        matureContactCount(waitingDays: waitingDays, now: now) >= 3
    }
}

nonisolated struct QSLGraylistIndex: Equatable, Sendable {
    private struct Contact {
        var sent: Bool
        let date: Date?
    }
    private struct History {
        var country = ""
        var confirmed = false
        var contacts: [String: Contact] = [:]
        var bands = Set<String>()
        var modes = Set<String>()
        var recordIDs = Set<UUID>()
        var unresolvedCount = 0

        mutating func add<Record: QSLGraylistRecord>(_ record: Record, calendar: Calendar) {
            let fields = record.fields
            confirmed = confirmed || record.isConfirmed
            recordIDs.insert(record.id)
            let name = (fields["COUNTRY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if country.isEmpty, !name.isEmpty { country = name }
            let key = QSOIdentity.exactKey(fields: fields)
            guard !key.isEmpty else { unresolvedCount += 1; return }
            if var contact = contacts[key] {
                contact.sent = contact.sent || record.isAnyQSLSent
                contacts[key] = contact
            } else {
                contacts[key] = Contact(sent: record.isAnyQSLSent, date: QSLGraylistIndex.date(fields, calendar: calendar))
            }
            let band = QSOIdentity.resolvedBand(fields)
            let mode = QSOIdentity.effectiveMode(fields)
            if !band.isEmpty { bands.insert(band.lowercased()) }
            if !mode.isEmpty { modes.insert(mode) }
        }
    }
    let entries: [QSLGraylistEntry]
    private let byCallsign: [String: QSLGraylistEntry]
    static let empty = QSLGraylistIndex(entries: [])

    private init(entries: [QSLGraylistEntry]) {
        self.entries = entries
        byCallsign = Dictionary(uniqueKeysWithValues: entries.map { ($0.callsign, $0) })
    }

    init<Record: QSLGraylistRecord>(records: [Record], profileID: UUID?) {
        var history: [String: History] = [:]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        for record in records {
            if Task.isCancelled { self = .empty; return }
            let fields = record.fields
            let owner = Self.clean(fields["APP_YAAM_STATION_PROFILE_ID"] ?? "")
            // Legacy rows belong to the already-scoped workspace. Explicit foreign rows do not.
            if !owner.isEmpty, owner != profileID?.uuidString.uppercased() { continue }
            let call = Self.clean(fields["CALL"] ?? "")
            guard !call.isEmpty else { continue }
            history[call, default: History()].add(record, calendar: calendar)
        }

        self.init(entries: history.compactMap { call, item in
            guard !item.confirmed, item.contacts.count >= 3 else { return nil }
            return QSLGraylistEntry(
                callsign: call, country: item.country, contactCount: item.contacts.count,
                sentCount: item.contacts.values.filter(\.sent).count,
                unresolvedCount: item.unresolvedCount,
                bands: item.bands.sorted(), modes: item.modes.sorted(),
                dates: item.contacts.values.compactMap(\.date).sorted(), recordIDs: item.recordIDs
            )
        }.sorted {
            if $0.contactCount != $1.contactCount { return $0.contactCount > $1.contactCount }
            return $0.callsign < $1.callsign
        })
    }

    func entry(for callsign: String) -> QSLGraylistEntry? { byCallsign[Self.clean(callsign)] }

    static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func date(_ fields: [String: String], calendar: Calendar) -> Date? {
        let raw = QSOIdentity.normalizedDate(fields["QSO_DATE"] ?? "")
        guard raw.count == 8, let year = Int(raw.prefix(4)), year >= 1900,
              let month = Int(raw.dropFirst(4).prefix(2)),
              let day = Int(raw.suffix(2)),
              let seconds = QSOIdentity.secondsFromMidnight(fields) else { return nil }
        let parts = DateComponents(year: year, month: month, day: day,
                                   hour: seconds / 3600, minute: seconds % 3600 / 60, second: seconds % 60)
        guard let date = calendar.date(from: parts),
              calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == parts else { return nil }
        return date
    }
}

// Demotion is a sort tier, never a prohibition or a change to the underlying award status.
nonisolated enum QSLGraylistPriority {
    static func tier(isToMe: Bool, isReduced: Bool) -> Int {
        isToMe ? 0 : (isReduced ? 2 : 1)
    }
}
