import AppKit
import SwiftUI

// Data stand-ins: only the production rendering code and viewport run.
struct QSORecordModel: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let fields: [String: String]
    subscript(_ key: String) -> String { fields[key] ?? "" }
    var isConfirmed: Bool { index % 3 == 0 }
    var isAnyQSLSent: Bool { index % 2 == 0 }
    var qslWaitingDays: Int? { index % 180 }
    var qsoAgeInDays: Int? { index % 365 }
    var qslSentDate: Date? { nil }
    var latestConfirmationDate: Date? { nil }
    var confirmationSourcesSummary: String { "Fixture" }
}
struct EmailHistoryEntry: Equatable {
    let date: Date; let email: String; let subject: String; let status: String
}
struct SentEmailDetailContext { let record: QSORecordModel; let entry: EmailHistoryEntry }
struct QSOConfirmationOpportunity: Equatable {
    let isConfirmed = false, hasCountryBandData = true, addsCountryBandCredit = true, addsGridCredit = false
    let band = "20m", country = "Fixture", grid: String? = "AA00"
}
enum ConfirmationCreditColumn {
    static let countryBand = "CREDIT_BAND", grid = "CREDIT_GRID"
    static func isDerived(_ header: String) -> Bool { [countryBand, grid].contains(header) }
}
func countryToFlag(_ value: String) -> String { "🏳️" }
@MainActor final class ScrollMetrics {
    static let shared = ScrollMetrics()
    var cellBuilds = 0
}
private let baseline = BASELINE_MODE
private let pinned = ["QSO_DATE", "TIME_ON", "CALL", "QSL"]
private let trailing = ["AGING", "FREQ", "BAND", "MODE", "GRIDSQUARE", "COUNTRY", "NAME", "QTH", "CONT", "DXCC", "CQZ", "ITUZ", "QSL_VIA", "EMAIL", "COMMENT", "RST_SENT", "RST_RCVD", "RANK_QSO", "RANK_BAND", "RANK_DXCC", "PROP_MODE", "SAT_NAME", "FREQ_RX", "BAND_RX", "SUBMODE", "TIME_OFF"]
private var pinnedWidth: CGFloat { 48 + pinned.reduce(0) { $0 + LogTableLayout.defaultColumnWidth(for: $1) } }
@MainActor final class ReviewControls: ObservableObject {
    @Published var rowLimit = 100000
    @Published var headers = trailing
    @Published var selected: Set<UUID> = []
    @Published var editing: UUID?
    @Published var editingHeader: String?
    @Published var text = ""
}
struct ReviewTable: View {
    let records: [QSORecordModel]
    @ObservedObject var controls: ReviewControls
    var widths: [CGFloat] { controls.headers.map { LogTableLayout.defaultColumnWidth(for: $0) } }
    var body: some View {
        VStack(spacing: 0) {
            Text("Invented contacts · \(records.count) rows · \(baseline ? "baseline" : "optimized") · no services")
                .font(.caption).padding(8)
            if baseline {
                ScrollView([.horizontal, .vertical]) {
                    rows(window: LogTableColumnWindow(range: 0..<controls.headers.count, leadingWidth: 0, trailingWidth: 0))
                }.coordinateSpace(name: "logTableScrollSpace")
            } else {
                LogTableScrollViewport(columnWidths: widths, pinnedWidth: pinnedWidth) { window in rows(window: window) }
            }
        }
    }
    func rows(window: LogTableColumnWindow) -> some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(Array(records.prefix(controls.rowLimit))) { record in
                    LogRowView(record: record, isSelected: controls.selected.contains(record.id), isNewlyConfirmed: record.index % 7 == 0,
                        isTodayConfirmed: false, ordinal: record.index + 1, sentEmail: nil, opportunity: nil,
                        isEditingThisRow: controls.editing == record.id, editingHeader: controls.editing == record.id ? controls.editingHeader : nil,
                        editingText: $controls.text, isTrackedRival: false, hasBatchSelection: !controls.selected.isEmpty,
                        batchSelectionCount: controls.selected.count, pinnedHeaders: pinned, unpinnedHeaders: controls.headers,
                        columnWindow: window, columnWidths: [:], utilityColumnWidth: 48, onAction: { action in
                            switch action {
                            case .toggleSelection: if !controls.selected.insert(record.id).inserted { controls.selected.remove(record.id) }
                            case .startEditing(let header, let value): controls.editing = record.id; controls.editingHeader = header; controls.text = value
                            case .commitEditing: controls.editing = nil
                            default: break
                            }
                        }).equatable()
                }
            } header: {
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("#").frame(width: 48, height: 28)
                        ForEach(pinned, id: \.self) { Text($0).frame(width: LogTableLayout.defaultColumnWidth(for: $0), height: 28) }
                    }.background(Color(NSColor.windowBackgroundColor)).modifier(PinnedLogColumns()).zIndex(10)
                    HStack(spacing: 0) { ForEach(controls.headers, id: \.self) { Text($0).frame(width: LogTableLayout.defaultColumnWidth(for: $0), height: 28) } }
                }.font(.system(size: 10, weight: .bold)).background(Color(NSColor.windowBackgroundColor))
            }
        }
    }
}
@main struct LogTableScrollReview {
    @MainActor static func main() throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        let records = (0..<100000).map { index in QSORecordModel(id: UUID(), index: index, fields: [
            "CALL": "ZZ\(index)TEST", "QSO_DATE": "20261020", "TIME_ON": "143500", "FREQ": "14.074",
            "BAND": "20M", "MODE": "FT8", "GRIDSQUARE": "AA00aa", "COUNTRY": "Fixture", "NAME": "Operator \(index)",
            "QTH": "Invented", "LOTW_QSL_RCVD": index % 3 == 0 ? "Y" : "", "EMAIL": "fixture@example.org"
        ]) }
        let controls = ReviewControls()
        let host = NSHostingView(rootView: ReviewTable(records: records, controls: controls).background(Color(NSColor.textBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host; window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5)); host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.compactMap(find).first
        }
        let scroll = find(host)!
        precondition(scroll.documentView!.frame.height > 2_799_000, "Entire log must be scrollable without pagination")
        func move(x: CGFloat, y: CGFloat) {
            let extent = scroll.documentView!.bounds.size
            let viewport = scroll.contentView.bounds.size
            let point = NSPoint(x: min(max(0, x), max(0, extent.width - viewport.width)),
                                y: min(max(0, y), max(0, extent.height - viewport.height)))
            scroll.contentView.scroll(to: point); scroll.reflectScrolledClipView(scroll.contentView)
        }
        let initialCells = ScrollMetrics.shared.cellBuilds
        ScrollMetrics.shared.cellBuilds = 0
        var times: [Double] = []
        for y: CGFloat in [1000, 5000, 28000, 56000, 140000, 280000, 700000, 1400000, 2100000, 2799300] {
            let start = CFAbsoluteTimeGetCurrent()
            move(x: 0, y: y)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            host.layoutSubtreeIfNeeded()
            times.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        let verticalCells = ScrollMetrics.shared.cellBuilds
        for dark in [false, true] {
            for width: CGFloat in [760, 1280] {
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.setContentSize(NSSize(width: width, height: 500))
                for x: CGFloat in [0, 1200, 2500] {
                    move(x: x, y: 28000)
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1)); host.layoutSubtreeIfNeeded(); window.display()
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(baseline ? "baseline" : "optimized")-\(dark)-\(Int(width))-\(Int(x)).png"))
                }
            }
        }
        // Exercise filtering, selection, editing and column removal while scrolled far right.
        move(x: 0, y: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        controls.headers = ["NAME", "EMAIL"]
        controls.rowLimit = 3
        controls.selected = [records[0].id]
        controls.editing = records[1].id; controls.editingHeader = "NAME"; controls.text = "Edited fixture"
        RunLoop.main.run(until: Date().addingTimeInterval(0.2)); host.layoutSubtreeIfNeeded()
        precondition(scroll.documentView!.frame.height < 600, "Filtered extent must shrink")
        move(x: 0, y: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1)); host.layoutSubtreeIfNeeded()
        let edited = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: edited)
        try edited.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("selected-editing.png"))
        controls.rowLimit = 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.1)); host.layoutSubtreeIfNeeded()
        controls.rowLimit = 100000; controls.headers = trailing
        RunLoop.main.run(until: Date().addingTimeInterval(0.2)); host.layoutSubtreeIfNeeded()
        precondition(scroll.documentView!.frame.height > 2_799_000, "Clearing filters must restore full extent")
        let result: [String: Any] = ["baseline": baseline, "rows": records.count, "columns": pinned.count + trailing.count,
            "initialCellBuilds": initialCells, "verticalCellBuilds": verticalCells,
            "scrollMilliseconds": times, "meanScrollMilliseconds": times.reduce(0, +) / Double(times.count)]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: out.appendingPathComponent(baseline ? "baseline.json" : "optimized.json"))
        print(String(data: data, encoding: .utf8)!)
        window.orderOut(nil)
    }
}
