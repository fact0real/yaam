// Compile with -D MESSAGING_REGRESSION, SKEDMessaging{Service,Model,View}.swift.
// Uses synthetic data and never connects to a service or opens the real vault.
import SwiftUI
import AppKit

@main struct SKEDMessagingVisualReview {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.accessory)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for size in [CGSize(width: 760, height: 500), CGSize(width: 1100, height: 800)] {
                for state in ["loading", "unavailable", "unverified", "disabled", "inbox", "retry", "self"] {
                    let model = SKEDMessagingModel(recipient: "G0JHC", userAgent: "visual-test", tokenProvider: { "" })
                    let enabled = SKEDMessagingStatus(available: true, verifiedCallsign: "EP2AES", enabled: true, retentionDays: 30)
                    let received = SKEDPrivateMessage(id: "42", clientID: UUID().uuidString.lowercased(), sender: "G0JHC", recipient: "EP2AES",
                        body: "Hello! Can we try 20m FT8 at 14:00 UTC?\nسلام، برای SKED آماده‌ام.\n[plain text](https://example.invalid) — no link preview",
                        createdAt: "2026-10-24T10:00:00.000000Z")
                    switch state {
                    case "loading": model.preview(status: nil, working: true)
                    case "unavailable": model.preview(status: nil, error: SKEDMessagingError.unavailable.localizedDescription)
                    case "unverified": model.preview(status: .init(available: true, verifiedCallsign: nil, enabled: false, retentionDays: 30))
                    case "disabled": model.preview(status: .init(available: true, verifiedCallsign: "EP2AES", enabled: false, retentionDays: 30))
                    case "self": model.preview(status: enabled, messages: [SKEDPrivateMessage(id: "43", clientID: UUID().uuidString.lowercased(), sender: "EP2AES", recipient: "EP2AES", body: "Test message to myself — checking SKED messaging.", createdAt: "2026-10-24T12:00:00.000000Z")])
                    case "retry": model.preview(status: enabled, messages: [received], error: SKEDMessagingError.transport.localizedDescription,
                        pending: try SKEDMessageDraft(recipient: "G0JHC", body: "14:00 UTC on 20m works for me, 73!"), blocks: ["K1ABC"])
                    default: model.preview(status: enabled, messages: [received])
                    }
                    let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
                    NSApplication.shared.appearance = NSAppearance(named: appearance)
                    let host = NSHostingView(rootView: SKEDMessagingView(model: model).environment(\.colorScheme, scheme))
                    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = host
                    host.appearance = NSAppearance(named: appearance)
                    host.frame = CGRect(origin: .zero, size: size)
                    window.makeKeyAndOrderFront(nil)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                    host.layoutSubtreeIfNeeded()
                    window.display()
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let file = "\(state)-\(scheme == .dark ? "dark" : "light")-\(Int(size.width)).png"
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(file))
                    window.orderOut(nil)
                }
            }
        }
        print("Rendered 28 synthetic messaging states in light/dark at compact/normal sizes.")
    }
}
