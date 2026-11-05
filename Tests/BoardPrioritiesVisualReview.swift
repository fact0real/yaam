// Renders actual changed SwiftUI views with inert data. No user archive, network, audio or radio access.
import AppKit
import SwiftUI

#if !OLIVIA_VISUAL
nonisolated struct QSORecordModel {
    var fields: [String: String] = [:]
    var isConfirmed = false
    subscript(_ key: String) -> String { fields[key] ?? "" }
}
actor TQSLCoordinator {
    static let shared = TQSLCoordinator()
    func execute(adifContent: String? = nil, adifFileURL: URL? = nil, stationLocation: String? = nil,
                 certificatePassword: String? = nil, customExecutablePath: String? = nil,
                 securityBookmark: Data? = nil, timeoutSeconds: TimeInterval = 45) async -> (success: Bool, message: String) {
        (false, "Disabled in visual fixture")
    }
}
#endif

@main @MainActor struct BoardPrioritiesVisualReview {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            for width in [760.0, 1100.0] {
#if OLIVIA_VISUAL
                let engine = OliviaMFSKEngine()
                try render(OliviaMFSKView(engine: engine), name: "olivia-experimental", width: width, dark: dark, output: output)
#else
                let a = UUID()
                let preview = QSLSyncPreview(profileID: UUID(), stationCallsign: "EA3JIC", uploads: [.qrz: [a], .eqsl: [a]], fieldsByID: [:],
                                             notChecked: [.lotw: "no LoTW callsign, station location or TQSL", .clubLog: "switched off in the Station Workspace"], blocker: nil)
                try render(QSLSyncPreviewSheet(preview: preview, confirm: {}, cancel: {}), name: "sync-review", width: width, dark: dark, output: output)
                var blocked = preview
                blocked.uploads = [:]; blocked.blocker = "A Guest Log is open; open the master log."
                try render(QSLSyncPreviewSheet(preview: blocked, confirm: {}, cancel: {}), name: "sync-blocked", width: width, dark: dark, output: output)
                let draft = DigitalQSODraft(callsign: "EA3JIC", mode: "OLIVIA", reportSent: "", reportReceived: "", radioFrequencyHz: nil)
                try render(DigitalQSOConfirmationSheet(center: DigitalQSOConfirmationCenter(), draft: draft), name: "digital-missing", width: width, dark: dark, output: output)
                var manual = DigitalQSODraft(callsign: "EA3JIC", mode: "RTTY", reportSent: "599", reportReceived: "579", radioFrequencyHz: 14_085_000)
                manual.frequencyText = "7.074"
                try render(DigitalQSOConfirmationSheet(center: DigitalQSOConfirmationCenter(), draft: manual), name: "digital-manual", width: width, dark: dark, output: output)
#endif
            }
        }
        print("Rendered actual views at 760×500 and 1100×500, light/dark, using inert fixture data.")
    }

    static func render<V: View>(_ content: V, name: String, width: Double, dark: Bool, output: URL) throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApp.appearance = appearance
        let host = NSHostingView(rootView: content.frame(width: width, height: 500)
            .background(Color(NSColor.windowBackgroundColor)).environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = appearance
        let size = CGSize(width: width, height: 500)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; host.frame = CGRect(origin: .zero, size: size); window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded(); window.display()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let filename = "\(name)-\(Int(width))-\(dark ? "dark" : "light").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
        window.orderOut(nil)
    }
}
