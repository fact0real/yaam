// swiftc -D MESSAGING_REGRESSION -parse-as-library Tests/LoTWProofVisualReview.swift
// YAAM/LoTWVerificationView.swift YAAM/LoTWProofSigner.swift YAAM/SKEDMessagingService.swift
// -o /tmp/lotw-visual && /tmp/lotw-visual /tmp/lotw-visuals
import SwiftUI
import AppKit

@main struct LoTWProofVisualReview {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.accessory)
        for scheme in [ColorScheme.light, .dark] {
            let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
            NSApplication.shared.appearance = appearance
            for size in [CGSize(width: 640, height: 520), CGSize(width: 760, height: 600)] {
                for state in ["empty", "working", "error", "success"] {
                    let view = LoTWVerificationView(service: SKEDMessagingService(userAgent: "visual-test"),
                        tokenProvider: { "" }, completed: {}).preview(state).environment(\.colorScheme, scheme)
                    let host = NSHostingView(rootView: view)
                    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = host
                    host.appearance = appearance
                    host.frame = CGRect(origin: .zero, size: size)
                    window.makeKeyAndOrderFront(nil)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
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
        print("Rendered 16 synthetic LoTW verification states; no service or real keys accessed.")
    }
}
