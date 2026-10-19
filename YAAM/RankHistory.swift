import Foundation

nonisolated enum RankHistoryCache {
    private static let writes = DispatchQueue(label: "YAAM.rank-history.persistence", qos: .utility)

    static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YAAM/rank-history-v1.json")
    }

    static func load(from url: URL? = Self.url) -> [QRZRankHistorySnapshot] {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshots = try? JSONDecoder().decode([QRZRankHistorySnapshot].self, from: data) else { return [] }
        return snapshots
    }

    // A serial writer preserves save order; atomic replacement keeps the prior
    // complete file intact if the process exits during a write.
    static func save(_ data: Data, to url: URL? = Self.url) {
        guard let url else { return }
        writes.async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                // UserDefaults also retains the complete history for recovery.
                NSLog("Rank history file could not be saved; preferences retain the history.")
            }
        }
    }
}

nonisolated enum RankChartMode: String, CaseIterable, Identifiable {
    case actualRank = "Daily rank"
    case dailyChange = "Daily change"
    case sinceBaseline = "Since baseline"
    var id: String { rawValue }
    var explanation: String {
        switch self {
        case .actualRank: return "Recorded rank for each UTC day. Lower rank is better. Gaps mean no observation."
        case .dailyChange: return "Climb / slip from the previous UTC day. Both days must have an observation."
        case .sinceBaseline: return "Climb / slip from the first visible observation. Gaps are not interpolated."
        }
    }
    func value(for point: RankTrendPoint, in points: [RankTrendPoint], baseline: Int) -> Int? {
        switch self {
        case .actualRank: return -point.rank
        case .sinceBaseline: return baseline - point.rank
        case .dailyChange:
            guard let previous = points.last(where: { $0.date < point.date }),
                  RankHistoryCalendar.adjacent(previous.date, point.date) else { return nil }
            return previous.rank - point.rank
        }
    }
}

nonisolated enum RankHistoryCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func date(for day: String) -> Date? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return components.year == year && components.month == month && components.day == day ? date : nil
    }

    static func adjacent(_ earlier: Date, _ later: Date) -> Bool {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: earlier),
                                to: calendar.startOfDay(for: later)).day == 1
    }

    static func timeline(points: [RankTrendPoint], limit: Int = 90, now: Date = Date()) -> [Date] {
        guard let first = points.map(\.date).min(), let last = points.map(\.date).max(), limit > 0 else { return [] }
        let end = calendar.startOfDay(for: max(last, now))
        let start = max(calendar.startOfDay(for: first), calendar.date(byAdding: .day, value: -(limit - 1), to: end)!)
        guard start <= end else { return [] }
        let count = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return (0...count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

nonisolated enum RankHistoryAnalysis {
    static func series(snapshots: [QRZRankHistorySnapshot], owner: String, tracked: [String],
                       metric: RankHistoryMetric, now: Date = Date()) -> [RankTrendSeries] {
        let formatter = DateFormatter()
        formatter.timeZone = RankHistoryCalendar.calendar.timeZone
        formatter.dateFormat = "MMM d"
        let deduplicated = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.date > b.date ? a : b })
        let all = deduplicated.values.sorted { $0.day < $1.day }
        let ownerByDay = Dictionary(all.filter { $0.callsign == owner }.map { ($0.day, $0) }, uniquingKeysWith: { _, b in b })
        let ownerLatestDate = all.last(where: { $0.callsign == owner && $0.rank(for: metric) != nil })?.chartDate
        func make(_ callsign: String, owner isOwner: Bool) -> RankTrendSeries {
            let records = all.filter { $0.callsign == callsign }
            let points = records.compactMap { record -> RankTrendPoint? in
                guard let rank = record.rank(for: metric) else { return nil }
                return RankTrendPoint(date: record.chartDate, label: formatter.string(from: record.chartDate), rank: rank)
            }
            let last = points.last
            let previous = points.dropLast().last
            let today = last.map { RankHistoryCalendar.calendar.isDate($0.date, inSameDayAs: now) } ?? false
            let movement: Int?
            if today, let previous, let last, RankHistoryCalendar.adjacent(previous.date, last.date) {
                movement = previous.rank - last.rank
            } else { movement = nil }
            let gaps: [(date: Date, value: Int)] = isOwner ? [] : records.compactMap { record in
                guard let own = ownerByDay[record.day]?.rank(for: metric), let rival = record.rank(for: metric) else { return nil }
                return (record.chartDate, rival - own)
            }
            let gap = gaps.last.flatMap { $0.date == last?.date && $0.date == ownerLatestDate ? $0.value : nil }
            let dailyGap: Int?
            if today, gaps.count >= 2, gaps.last?.date == last?.date,
               RankHistoryCalendar.adjacent(gaps[gaps.count - 2].date, gaps[gaps.count - 1].date) {
                dailyGap = gaps[gaps.count - 1].value - gaps[gaps.count - 2].value
            } else { dailyGap = nil }
            return RankTrendSeries(callsign: callsign, countryIso: records.last?.countryIso, isOwner: isOwner,
                                   latestRank: last?.rank, latestGap: gap, latestMovement: movement,
                                   latestGapMovement: dailyGap, points: points)
        }
        return (owner.isEmpty || owner == "DEFAULT" ? [] : [make(owner, owner: true)])
            + tracked.map { make($0, owner: false) }
    }
}

nonisolated struct QRZRankHistoryEnvelope: Decodable, Sendable {
    struct Observation: Decodable, Sendable {
        let observed_at: String
        let data: QRZRankResponse
    }
    let time_zone: String
    let watchlist: [String]
    let snapshots: [Observation]

    func validatedSnapshots(expected: Set<String>, now: Date = Date()) throws -> [QRZRankHistorySnapshot] {
        guard time_zone == "UTC", Set(watchlist) == expected, snapshots.count <= 9 * 366 else {
            throw QRZRankFetchFailure.invalidResponse
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        return try snapshots.map { observation in
            guard let date = fractional.date(from: observation.observed_at) ?? whole.date(from: observation.observed_at),
                  date <= now.addingTimeInterval(300), observation.observed_at.hasSuffix("Z"),
                  let callsign = observation.data.callsign, expected.contains(callsign) else {
                throw QRZRankFetchFailure.invalidResponse
            }
            let snapshot = QRZRankHistorySnapshot(date: date, response: observation.data)
            guard RankHistoryMetric.allCases.contains(where: { snapshot.rank(for: $0) != nil }) else {
                throw QRZRankFetchFailure.invalidResponse
            }
            return snapshot
        }
    }
}

nonisolated enum RankHistoryMetric: String, CaseIterable, Identifiable {
    case qso
    case bands
    case dxcc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qso: return "QSO Rank"
        case .bands: return "Bands Rank"
        case .dxcc: return "DXCC Rank"
        }
    }

    var icon: String {
        switch self {
        case .qso: return "antenna.radiowaves.left.and.right"
        case .bands: return "waveform.path.ecg"
        case .dxcc: return "globe.americas.fill"
        }
    }
}

nonisolated struct QRZRankHistorySnapshot: Identifiable, Codable, Sendable {
    let date: Date
    let callsign: String
    let countryIso: String?
    let qsoRank: Int?
    let bandRank: Int?
    let dxccRank: Int?
    let qsoScore: Int?
    let bandScore: Int?
    let dxccScore: Int?

    let recordedDay: String?
    var day: String { recordedDay ?? Self.legacyDayKey(for: date) }
    var chartDate: Date { RankHistoryCalendar.date(for: day) ?? date }
    var id: String { "\(day)-\(callsign)" }

    init(date: Date = Date(), response: QRZRankResponse, recordedDay: String? = nil) {
        self.recordedDay = recordedDay ?? Self.dayKey(for: date)
        self.date = date
        callsign = response.callsign?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        countryIso = response.country_iso
        qsoRank = Self.parseRank(response.rank_qso)
        bandRank = Self.parseRank(response.rank_band)
        dxccRank = Self.parseRank(response.rank_countries)
        qsoScore = Self.parseRank(response.score_qso)
        bandScore = Self.parseRank(response.score_band)
        dxccScore = Self.parseRank(response.score_countries)
    }

    func rank(for metric: RankHistoryMetric) -> Int? {
        switch metric {
        case .qso: return qsoRank.flatMap { $0 > 0 ? $0 : nil }
        case .bands: return bandRank.flatMap { $0 > 0 ? $0 : nil }
        case .dxcc: return dxccRank.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func legacyDayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // Freeze the original local calendar day of legacy snapshots during migration.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        callsign = try c.decode(String.self, forKey: .callsign)
        countryIso = try c.decodeIfPresent(String.self, forKey: .countryIso)
        qsoRank = try c.decodeIfPresent(Int.self, forKey: .qsoRank)
        bandRank = try c.decodeIfPresent(Int.self, forKey: .bandRank)
        dxccRank = try c.decodeIfPresent(Int.self, forKey: .dxccRank)
        qsoScore = try c.decodeIfPresent(Int.self, forKey: .qsoScore)
        bandScore = try c.decodeIfPresent(Int.self, forKey: .bandScore)
        dxccScore = try c.decodeIfPresent(Int.self, forKey: .dxccScore)
        recordedDay = try c.decodeIfPresent(String.self, forKey: .recordedDay) ?? Self.legacyDayKey(for: date)
    }

    private static func parseRank(_ value: String?) -> Int? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(cleaned)
    }
}

nonisolated struct RankTrendPoint: Identifiable, Sendable, Equatable {
    var id: String { "\(date.timeIntervalSince1970)-\(rank)" }
    let date: Date
    let label: String
    let rank: Int
}

nonisolated struct RankTrendSeries: Identifiable, Sendable, Equatable {
    var id: String { callsign }
    let callsign: String
    let countryIso: String?
    let isOwner: Bool
    let latestRank: Int?
    let latestGap: Int?
    let latestMovement: Int?
    let latestGapMovement: Int?
    let points: [RankTrendPoint]
}

