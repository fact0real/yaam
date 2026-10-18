import Foundation

nonisolated enum RankGrowthPeriod: String, CaseIterable, Identifiable {
    case week = "7 days", month = "30 days", quarter = "90 days", all = "All history"
    var id: String { rawValue }
    func start(now: Date) -> Date? {
        let days: Int
        switch self { case .week: days = 7; case .month: days = 30; case .quarter: days = 90; case .all: return nil }
        return RankHistoryCalendar.calendar.date(byAdding: .day, value: -(days - 1), to: RankHistoryCalendar.calendar.startOfDay(for: now))
    }
}

nonisolated struct RankGrowthComparison: Identifiable {
    let callsign: String
    let dates: [Date]
    let owner: [RankTrendPoint]
    let rival: [RankTrendPoint]
    var id: String { callsign }
    var gain: Int? {
        guard dates.count >= 2, let a = owner.first, let b = owner.last,
              let c = rival.first, let d = rival.last else { return nil }
        return (a.rank - b.rank) - (c.rank - d.rank)
    }
    var gap: Int? { guard let a = owner.last, let b = rival.last else { return nil }; return b.rank - a.rank }
}

nonisolated enum RankGrowthAnalysis {
    static func points(_ points: [RankTrendPoint], period: RankGrowthPeriod, now: Date) -> [RankTrendPoint] {
        let end = RankHistoryCalendar.calendar.startOfDay(for: now)
        let start = period.start(now: now)
        // One observation per UTC day; ignore future and invalid ranks.
        let valid = points.sorted { $0.date < $1.date }.compactMap { point -> RankTrendPoint? in
            let day = RankHistoryCalendar.calendar.startOfDay(for: point.date)
            guard point.rank > 0, day <= end, start == nil || day >= start! else { return nil }
            return RankTrendPoint(date: day, label: point.label, rank: point.rank)
        }
        let unique = Dictionary(valid.map { ($0.date, $0) }, uniquingKeysWith: { _, latest in latest })
        return unique.values.sorted { $0.date < $1.date }
    }
    static func comparisons(series: [RankTrendSeries], period: RankGrowthPeriod, now: Date) -> [RankGrowthComparison] {
        guard let owner = series.first(where: \.isOwner) else { return [] }
        let own = points(owner.points, period: period, now: now)
        let ownByDay = Dictionary(uniqueKeysWithValues: own.map { (RankHistoryCalendar.calendar.startOfDay(for: $0.date), $0) })
        return series.filter { !$0.isOwner }.map { item in
            let rivals = points(item.points, period: period, now: now).filter { ownByDay[RankHistoryCalendar.calendar.startOfDay(for: $0.date)] != nil }
            let matched = rivals.compactMap { ownByDay[RankHistoryCalendar.calendar.startOfDay(for: $0.date)] }
            return RankGrowthComparison(callsign: item.callsign, dates: matched.map(\.date), owner: matched, rival: rivals)
        }
    }
    static func improvement(_ points: [RankTrendPoint]) -> Int? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return first.rank - last.rank
    }
    static func percent(_ rank: Int, baseline: Int) -> Double { 100 * Double(baseline - rank) / Double(max(1, baseline)) }
    static func segmentIDs(_ points: [RankTrendPoint]) -> [Int] {
        var segment = 0
        return points.indices.map { i in
            if i > 0 && !RankHistoryCalendar.adjacent(points[i - 1].date, points[i].date) { segment += 1 }
            return segment
        }
    }
}
