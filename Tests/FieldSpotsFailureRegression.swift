import AppKit
import Combine
import Foundation
import SwiftUI

public protocol FieldQSORecord { var fields: [String: String] { get }; subscript(key: String) -> String { get } }
nonisolated enum AmateurBandPlan { static func band(forMHz: Double) -> String? { "20M" } }
@MainActor public final class RigControlEngine: ObservableObject {
    public static let shared = RigControlEngine()
    enum Driver { case disabled, rigctld }
    var driverType = Driver.disabled
    @Published var lastError: String?
    var tunes = 0
    func tune(frequencyHz: UInt64, mode: String?) -> String? { tunes += 1; return "CAT is offline; no tuning command was sent." }
}
@MainActor final class TCIClient { static let shared = TCIClient(); var isConnected = false; func setFrequency(hz: UInt64) {} }
@MainActor public final class POTASOTAEngine: ObservableObject {
    public static let shared = POTASOTAEngine()
    var activeSession: FieldActivationSession?
}
nonisolated final class SpotsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var phase = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let pota = request.url!.host == "api.pota.app"
        if Self.phase == 0 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let status = (Self.phase == 2 && pota) ? 503 : 200
        let text: String
        if Self.phase == 3 { text = "[]" }
        else if Self.phase == 4 { text = "not JSON" }
        else if pota { text = #"[{"spotId":1,"activator":"TEST/P","frequency":14074,"mode":"FT8","reference":"TEST-1","name":"Fixture park","spotTime":"2026-10-23T11:00:00Z"}]"# }
        else { text = #"[{"id":1,"timeStamp":"2026-10-23T11:00:00Z","summitCode":"TEST/1","activatorCallsign":"TEST/P","frequency":"14.062","mode":"CW"}]"# }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct FieldSpotsFailureRegression {
    static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpotsURLProtocol.self]
        let client = POTASpotsClient(session: URLSession(configuration: config), autoRefresh: false)
        await client.refreshSpots()
        precondition(client.potaSpots.isEmpty && client.sotaSpots.isEmpty && client.lastUpdated == nil)
        precondition(client.potaError != nil && client.sotaError != nil)
        print("PASS offline launch shows no fabricated spots or successful-fetch timestamp")
        let output = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil
        try output.map { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
        if let output { try render(client, output, "offline") }
        SpotsURLProtocol.phase = 1; await client.refreshSpots()
        precondition(client.potaSpots.count == 1 && client.sotaSpots.count == 1 && client.selectedError == nil)
        let good = client.potaUpdated
        client.tuneRig(frequencyKHz: 14074, mode: "FT8")
        precondition(client.tuneErrorMessage?.contains("offline") == true)
        if let output { try render(client, output, "live-tune-error") }
        SpotsURLProtocol.phase = 2; await client.refreshSpots()
        precondition(client.potaUpdated == good && client.potaSpots.count == 1 && client.potaError!.contains("503"))
        precondition(client.sotaError == nil && client.sotaUpdated! > good!)
        let count = RigControlEngine.shared.tunes
        client.tuneRig(frequencyKHz: 14074, mode: "FT8")
        precondition(RigControlEngine.shared.tunes == count && client.tuneErrorMessage!.contains("stale"))
        if let output { try render(client, output, "stale") }
        client.selectedProgram = .sota
        precondition(!client.selectedIsStale)
        print("PASS partial failure retains and labels only that source's stale list; stale Tune cannot send CAT")
        SpotsURLProtocol.phase = 3; await client.refreshSpots()
        precondition(client.potaSpots.isEmpty && client.sotaSpots.isEmpty && client.potaError == nil && client.sotaError == nil)
        print("PASS successful empty fetch clears old spots and recovers each source")
        SpotsURLProtocol.phase = 4; await client.refreshSpots()
        precondition(client.potaError != nil && client.sotaError != nil)
        client.tuneRig(frequencyKHz: .infinity, mode: "FT8")
        precondition(client.tuneErrorMessage!.contains("not a usable"))
        precondition(SOTASpotItem(frequency: "garbage").frequencyKHz.isNaN)
        print("PASS malformed JSON/frequency fails visibly without inventing a tuning frequency")
    }
    static func render(_ client: POTASpotsClient, _ directory: URL, _ state: String) throws {
        for width in [760, 1100] {
            for dark in [false, true] {
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
                NSApplication.shared.appearance = appearance
                let view = NSHostingView(rootView: FieldSpotsRadarView(client: client).environment(\.colorScheme, dark ? .dark : .light).frame(width: CGFloat(width), height: 500))
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 500), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view; window.makeKeyAndOrderFront(nil)
                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
                view.layoutSubtreeIfNeeded()
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(state)-\(width)-\(dark ? "dark" : "light").png"))
                window.orderOut(nil)
            }
        }
    }
}
