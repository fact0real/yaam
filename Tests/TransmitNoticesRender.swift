import AppKit
import SwiftUI

@main
struct TransmitNoticesRender {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let notices = TransmitNotices.shared
        for (width, dark, count) in [(760, false, 1), (1000, true, 2), (340, false, 2), (760, true, 0)] {
            for notice in notices.notices { notices.dismiss(notice.id) }
            for slot in 0..<count {
                notices.post(.init(name: "rigctld · Slot \(slot + 1)"), text:
                    TXLimits.safetyTimerMessage(radio: "rigctld · Slot \(slot + 1)", keyedAt: Date().addingTimeInterval(-14), limit: 14, elapsed: 14))
            }
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            app.appearance = appearance
            let height = max(360, count * 300 + 240)
            let root = VStack(alignment: .leading, spacing: 12) {
                Text("Transmit safety").font(.headline)
                TransmitNoticesView()
                RadioTuningNotice(message: "POTA/SOTA: the spot’s frequency is invalid. The radio was not tuned. Refresh remains available; tune by hand or choose another spot.") {}
                Label(count > 0 ? "Receive and logbook remain available" : "No transmit safety notices", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .frame(width: CGFloat(width), height: CGFloat(height))
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
            let view = NSHostingView(rootView: root)
            view.appearance = appearance
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("notices-\(width)-\(dark ? "dark" : "light")-\(count).png"))
            window.orderOut(nil)
        }
        print("PASS actual SwiftUI notice snapshots: compact/normal, light/dark, one/two/empty")
    }
}
