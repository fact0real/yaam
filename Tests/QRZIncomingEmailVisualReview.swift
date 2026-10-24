// Compile with QRZIncomingEmailLookup.swift, QRZIncomingRecoveryArchive.swift and the extracted production Requests/Reject views.
// Inert fixtures: no production AppState, credentials, logbook, network lookup, email sending or rejection transport.
import AppKit
import SwiftUI
import WebKit

@MainActor enum QRZWebKitSession {
    static let userAgent = "YAAM visual fixture"
    static func browserLikeConfiguration() -> WKWebViewConfiguration { WKWebViewConfiguration() }
    static func browserLikeRequest(url: URL, timeoutInterval: TimeInterval) -> URLRequest { URLRequest(url: url) }
}
@MainActor enum QRZSessionStore { static func restoreToWebKit(completion: (() -> Void)? = nil) { completion?() } }
struct QSORecordModel { }
enum IncomingContactReview { static func clean(_ call: String) -> String { call.uppercased() } }
@MainActor final class AppState: ObservableObject {
    @Published var activeStationProfileID: UUID? = UUID()
    @Published var qrzIncomingStatus = "Visual fixture · no services"
    @Published var showIncomingEmailComposer = false
    let qsoRecordsRevision = 0
    let isFetchingQRZIncoming = false, isRejectingQRZIncoming = false
    let rejectingQRZIncomingID: String? = nil, incomingEmailLookupCallsign: String? = nil
    let qrzIncomingRequests = ["ZZ1TEST", "ZZ2TEST", "ZZ3TEST", "ZZ4TEST", "ZZ5TEST"].enumerated().map {
        QRZIncomingConfirmation(callsign: $0.element, qsoDate: "2026-10-20", requestedAt: "2026-10-24", rawSummary: "Fixture", qsoID: String(42 + $0.offset))
    }
    var qrzIncomingArchive: QRZIncomingRecoveryArchive { var archive = QRZIncomingRecoveryArchive(); archive.refresh(qrzIncomingRequests); return archive }
    func incomingRecoveryRecord(_ request: QRZIncomingConfirmation) -> QSORecordModel? { nil }
    func hasIncomingCandidate(for request: QRZIncomingConfirmation) -> Bool { false }
    func fetchQRZIncomingRequests() { }
    func draftIncomingQRZDetailsEmail(for request: QRZIncomingConfirmation) { }
    func archiveQRZIncomingRecovery(_ request: QRZIncomingConfirmation) { }
    func retainQRZIncomingRecovery(_ request: QRZIncomingConfirmation) { }
    func rejectQRZIncomingRequest(_ request: QRZIncomingConfirmation, reason: String, comments: String) { fatalError("Visual fixture never rejects") }
}
struct QRZIncomingReviewView: View {
    let request: QRZIncomingConfirmation; let onRequestDetails: () -> Void
    var body: some View { Text("Fixture · recovery not used") }
}
struct QRZLoginView: View { var body: some View { Text("Fixture · authentication not used") } }
struct EmailComposerView: View { var body: some View { Text("Fixture · email not used") } }
struct QRZIncomingBulkEmailView: View { let requests: [QRZIncomingConfirmation]; var body: some View { Text("Fixture · bulk email not used") } }
extension View { func resizablePresentation(minWidth: CGFloat, minHeight: CGFloat) -> some View { self } }

@MainActor final class VisualControls: NSObject {
    var window: NSWindow!
    @objc func compactLight() { resize(760, 500, false) }
    @objc func compactDark() { resize(760, 500, true) }
    @objc func normalLight() { resize(980, 680, false) }
    @objc func normalDark() { resize(980, 680, true) }
    func resize(_ w: CGFloat, _ h: CGFloat, _ dark: Bool) { window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua); window.setContentSize(NSSize(width: w, height: h)) }
}
@main struct IncomingEmailVisualReview {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        let appState = AppState()
        let checker = QRZIncomingEmailChecker(initialStates: ["ZZ1TEST": .notPublished, "ZZ2TEST": .available("fixture@example.org"), "ZZ3TEST": .unavailable, "ZZ5TEST": .signInRequired], lookup: { _ in .unavailable })
        let root = QRZIncomingRequestsView(emailChecker: checker).environmentObject(appState)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 760, height: 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: root)
        window.title = "YAAM Incoming Email Preview · invented contacts · no services"
        let controls = VisualControls(); controls.window = window
        let bar = NSMenu(); let parent = NSMenuItem(title: "Preview", action: nil, keyEquivalent: ""); let menu = NSMenu(title: "Preview")
        for (title, action) in [("Compact light", #selector(VisualControls.compactLight)), ("Compact dark", #selector(VisualControls.compactDark)), ("Normal light", #selector(VisualControls.normalLight)), ("Normal dark", #selector(VisualControls.normalDark))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = controls; menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        parent.submenu = menu; bar.addItem(parent); NSApp.mainMenu = bar
        controls.compactLight(); window.center(); window.makeKeyAndOrderFront(nil)
        withExtendedLifetime(controls) { NSApp.run() }
    }
}
