import AppKit
import SwiftUI

@main struct QSLGraylistVisualReview {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let suite = "YAAM.QSLGraylist.Visual.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = QSLGraylistStore(defaults: defaults)
        let profile = UUID()
        store.reset(profileID: profile)
        let records: [QSORecordModel] = (0..<15).flatMap { call in
            (0..<(3 + call)).map { qso in
                QSORecordModel(fields: ["CALL": call == 0 ? "DL1TEST" : "G\(call)TEST",
                    "QSO_DATE": call == 1 ? "20261024" : "20260101", "TIME_ON": String(format: "12%02d00", qso),
                    "COUNTRY": call % 2 == 0 ? "Germany" : "United Kingdom",
                    "BAND": qso % 2 == 0 ? "20M" : "40M", "MODE": "FT8",
                    "QSL_SENT": qso % 3 == 0 ? "Y" : "N"])
            }
        }
        for dark in [false, true] {
            for width in [760.0, 1200.0] {
                store.reset(profileID: profile)
                try snapshot(content(store, evidence: "LoTW: never · history incomplete   •   QRZ: never · history incomplete"),
                             "unavailable-\(dark)-\(Int(width))", width: width, height: 380, dark: dark, out: out)
                store.schedule(records: records, profileID: profile)
                try snapshot(content(store), "loading-\(dark)-\(Int(width))", width: width, height: 380, dark: dark, out: out)
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                precondition(!store.isLoading && store.index.entries.count == 15)
                store.setReducesPriority(true)
                store.setException(true, callsign: "DL1TEST")
                try snapshot(content(store), "populated-\(dark)-\(Int(width))", width: width, height: width == 760 ? 380 : 620, dark: dark, out: out)
                try snapshot(QSLGraylistDetails(store: store, callsign: "DL1TEST", onOpenContacts: { _ in }),
                             "details-\(dark)-\(Int(width))", width: 540, height: 450, dark: dark, out: out)
                try snapshot(QSLGraylistCallBadge(store: store, callsign: "DL1TEST", onOpen: {}).padding(20).background(Color(nsColor: .windowBackgroundColor)),
                             "badge-\(dark)-\(Int(width))", width: 430, height: 90, dark: dark, out: out)
                store.schedule(records: [], profileID: profile)
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                try snapshot(content(store, evidence: "LoTW: Oct 24 · last run needs attention   •   QRZ: never · history incomplete"),
                             "empty-error-\(dark)-\(Int(width))", width: width, height: 380, dark: dark, out: out)
            }
        }
        print("Rendered actual QSL Graylist views: compact/normal, light/dark, loading, populated, empty/error, unavailable, details and badge at \(out.path)")
    }

    @MainActor static func content(_ store: QSLGraylistStore, evidence: String = "LoTW: Oct 24   •   QRZ Logbook: Oct 24") -> some View {
        QSLGraylistContent(store: store, station: "Test station · MY1CALL", syncEvidence: evidence, onOpenContacts: { _ in })
    }

    @MainActor static func snapshot<Content: View>(_ root: Content, _ name: String, width: Double, height: Double,
                                                   dark: Bool, out: URL) throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApplication.shared.appearance = appearance
        let host = NSHostingView(rootView: root.environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = appearance
        let size = CGSize(width: width, height: height)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        window.makeKeyAndOrderFront(nil)
        // Keep the loading capture inside the worker debounce interval.
        RunLoop.current.run(until: Date().addingTimeInterval(name.hasPrefix("loading") ? 0.05 : 0.15))
        host.layoutSubtreeIfNeeded()
        if name.hasPrefix("populated") {
            guard let table = nativeTable(in: host) else { fatalError("Native graylist table was not rendered") }
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            precondition(table.selectedRow == 0)
        }
        window.display()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
        window.orderOut(nil)
    }

    @MainActor static func nativeTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { nativeTable(in: $0) }.first
    }
}
