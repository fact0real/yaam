// Compile with the monitor/chart section extracted unchanged from LeaderboardView.swift,
// RankHistory.swift, QRZRankAPIContract.swift, QRZRankService.swift and country helpers.
// Uses an isolated preference suite and synthetic observations; never starts AppState.
import SwiftUI
import AppKit

@main struct RankHistoryVisualReview {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let defaults = UserDefaults(suiteName: "YAAM.RankHistory.VisualReview")!
        defer { defaults.removePersistentDomain(forName: "YAAM.RankHistory.VisualReview") }
        let now = Date()
        let calls = ["EP2AES", "EP2DES", "EP2LMA", "EP4HR", "EP5APP", "EP5MMS", "EP6DSP", "G0JHC"]
        let ranks = [9056, 223898, 9883, 4802, 51753, 74863, 39794, 798]
        var records: [QRZRankHistorySnapshot] = []
        for day in 0..<21 where day < 10 || day > 16 {
            for (index, call) in calls.enumerated() {
                let date = RankHistoryCalendar.calendar.date(byAdding: .day, value: day - 20, to: now)!
                let rank = ranks[index] + (20 - day) * (index == 0 ? 40 : 3 - index)
                let response = QRZRankResponse(bid: nil, callsign: call, country_iso: index == 7 ? "gb" : "ir", country_name: nil,
                    rank_band: nil, rank_countries: nil, rank_qso: String(rank), score_band: nil, score_countries: nil, score_qso: nil)
                records.append(QRZRankHistorySnapshot(date: date, response: response))
            }
        }
        let series = RankHistoryAnalysis.series(snapshots: records, owner: calls[0], tracked: Array(calls.dropFirst()), metric: .qso, now: now)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            for (width, height) in [(1620.0, 940.0), (760.0, 500.0)] {
                defaults.set(RankChartMode.actualRank.rawValue, forKey: "leaderboardRankChartMode")
                snapshot(series: series, calls: Array(calls.dropFirst()), status: "Server daily tracking · 8/8 observed today (UTC). Missing past days remain gaps.",
                         loading: false, defaults: defaults, appearance: appearance, size: CGSize(width: width, height: height),
                         to: output.appendingPathComponent("rank-\(name)-\(Int(width)).png"))
            }
            for mode in [RankChartMode.dailyChange, .sinceBaseline] {
                defaults.set(mode.rawValue, forKey: "leaderboardRankChartMode")
                snapshot(series: series, calls: Array(calls.dropFirst()), status: "Server daily tracking", loading: false, defaults: defaults,
                         appearance: appearance, size: CGSize(width: 1100, height: 800), to: output.appendingPathComponent("\(mode.id)-\(name).png"))
            }
            for state in ["empty", "loading", "error"] {
                snapshot(series: state == "empty" ? [] : series, calls: state == "empty" ? [] : Array(calls.dropFirst()),
                         status: state == "error" ? "History sync failed. Saved observations remain available. The service is unavailable." : "Synchronizing server daily history…",
                         loading: state == "loading", defaults: defaults, appearance: appearance, size: CGSize(width: 760, height: 500),
                         to: output.appendingPathComponent("\(state)-\(name).png"))
            }
        }
        print("Rendered 14 isolated rank monitor review images at \(output.path)")
    }

    @MainActor static func snapshot(series: [RankTrendSeries], calls: [String], status: String, loading: Bool,
        defaults: UserDefaults, appearance: NSAppearance.Name, size: CGSize, to url: URL) {
        NSApplication.shared.appearance = NSAppearance(named: appearance)
        let content = ScrollView {
            RankPerformanceMonitor(metric: .constant(.qso), series: series, trackedCallsigns: calls,
                isRefreshing: loading, status: status, refreshAction: {}, removeAction: { _ in }).padding(16)
        }
        .defaultAppStorage(defaults)
        .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
        .background(Color(nsColor: .windowBackgroundColor))
        let view = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.appearance = NSAppearance(named: appearance)
        view.frame = CGRect(origin: .zero, size: size)
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        view.layoutSubtreeIfNeeded()
        window.display()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
        window.orderOut(nil)
    }
}
