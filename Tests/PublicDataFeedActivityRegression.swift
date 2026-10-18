// swiftc -parse-as-library Tests/PublicDataFeedActivityRegression.swift YAAM/PublicDataFeedActivity.swift -o /tmp/yaam-feed-tests && /tmp/yaam-feed-tests
import Foundation
#if FEED_VISUAL_REVIEW
import AppKit
import SwiftUI
#endif

@main @MainActor enum PublicDataFeedActivityRegression {
    static func main() {
        let suite = "YAAM-Feed-Tests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = PublicDataFeedPolicy(defaults: defaults)
        var requests = 0
        var cancellations = 0
        let activity = PublicDataFeedActivity(interval: 3600, policy: policy,
            refresh: { requests += 1 }, cancel: { cancellations += 1 })
        precondition(requests == 0 && !activity.isActive, "Creating engines must not fetch")
        let first = UUID(), second = UUID()
        activity.setConsumer(first, active: true)
        activity.setConsumer(first, active: true)
        activity.setConsumer(second, active: true)
        precondition(requests == 1 && activity.isActive, "Visible windows share a single refresh")
        activity.setConsumer(first, active: false)
        precondition(activity.isActive && cancellations == 0)
        policy.isEnabled = false
        precondition(!activity.isActive && cancellations == 1)
        activity.setConsumer(UUID(), active: true)
        precondition(requests == 1, "Disabled policy blocks new consumers")
        policy.isEnabled = true
        precondition(activity.isActive && requests == 2, "Enabling resumes visible consumers")
        precondition(PublicDataFeedPolicy(defaults: defaults).isEnabled)
        policy.isEnabled = false
        precondition(!PublicDataFeedPolicy(defaults: defaults).isEnabled, "Disabled choice persists")
        let other = PublicDataFeedActivity(interval: 3600, policy: policy, refresh: { requests += 1 })
        other.setConsumer(first, active: true)
        other.setConsumer(first, active: false)
        policy.isEnabled = true
        precondition(!other.isActive, "Hidden consumer must not restart after re-enabling")
        #if FEED_VISUAL_REVIEW
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            for width in [720.0, 1060.0] {
                app.appearance = NSAppearance(named: appearance)
                let view = NSHostingView(rootView: PublicDataFeedSettingsView().padding(20)
                    .frame(width: width, height: 180, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
                view.appearance = NSAppearance(named: appearance)
                view.frame = NSRect(x: 0, y: 0, width: width, height: 180)
                let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/yaam-feeds-\(name)-\(Int(width)).png"))
            }
        }
        #endif
        var ticks = 0
        var stops = 0
        let timed = PublicDataFeedActivity(interval: 0.02, policy: policy,
            refresh: { ticks += 1 }, cancel: { stops += 1 })
        timed.setConsumer(first, active: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.07))
        precondition(ticks > 1, "Visible feed timer refreshes")
        timed.setConsumer(first, active: false)
        let stoppedAt = ticks
        RunLoop.main.run(until: Date().addingTimeInterval(0.07))
        precondition(ticks == stoppedAt && stops == 1 && !timed.isActive, "Last hidden consumer stops refreshes")
        print("PASS: no startup fetch, shared visible demand, cancellation, disabled gating and persistence")
    }
}
