// swiftc -D STANDALONE_PRIVACY_TEST -parse-as-library Tests/StationPrivacyRegression.swift \
// YAAM/{WeatherLocationPrivacy,StationWeatherSafetyEngine,StationProfile,GridLocator,CountryNameNormalizer,CountryFlagEngine,QSLCardStationInfo,QSLCardView,CallHistoryLookupEngine}.swift \
// -o /tmp/yaam-station-privacy && /tmp/yaam-station-privacy
import Foundation
import AppKit
import PDFKit
import SwiftUI

#if STANDALONE_PRIVACY_TEST
struct QSORecordModel {
    var fields: [String: String]
    subscript(_ key: String) -> String { fields[key] ?? "" }
}
@MainActor final class RoverModeEngine {
    static let shared = RoverModeEngine()
    var grid: String?
    func effectiveGrid(homeGrid: String) -> String { grid ?? homeGrid }
}
#endif

final class WeatherRequestStub: URLProtocol {
    static let lock = NSLock()
    static var requests: [URLRequest] = []
    static var hold = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let hold = Self.hold
        Self.lock.unlock()
        if hold { return }
        let payload = #"{"current":{"temperature_2m":20,"relative_humidity_2m":40,"apparent_temperature":19,"precipitation":0,"rain":0,"weather_code":0,"wind_speed_10m":5,"wind_gusts_10m":9,"wind_direction_10m":90,"surface_pressure":1010},"hourly":{"time":[],"temperature_2m":[],"precipitation_probability":[],"precipitation":[],"weather_code":[],"wind_speed_10m":[],"wind_gusts_10m":[]}}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
    static var last: URLRequest { lock.lock(); defer { lock.unlock() }; return requests.last! }
    static func holdResponses() { lock.lock(); hold = true; lock.unlock() }
    static func resumeResponses() { lock.lock(); hold = false; lock.unlock() }
}

@main @MainActor enum StationPrivacyRegression {
    static func main() async throws {
        let approximate = WeatherLocationPrecision.square
        let precise = WeatherLocationPrecision.subsquare
        let a = approximate.location(for: " jn18aa ")!
        let b = approximate.location(for: "JN18XX99XX")!
        precondition(a.grid == "JN18" && a.latitude == 48.5 && a.longitude == 3)
        precondition(a.latitude == b.latitude && a.longitude == b.longitude, "Suffix must not leak through coarse position")
        let c = precise.location(for: "JN18AA")!
        precondition(c.grid == "JN18AA" && abs(c.longitude - 2.0416666667) < 0.000001)
        precondition(precise.location(for: "JN18")!.latitude == a.latitude)
        for bad in ["", "A", "AAAA", "ZZ99", "JN18A", "JN18YY", "JN١٨AA", "JN18AA1X", "JN18AA00ZZ", "JN18AAgarbage"] {
            precondition(approximate.location(for: bad) == nil && precise.location(for: bad) == nil, "Reject malformed locator: \(bad)")
        }
        for grid in ["AA00AA", "RR99XX", "AA00AA00AA", "RR99XX99XX"] {
            let pos = precise.location(for: grid)!
            precondition((-90...90).contains(pos.latitude) && (-180...180).contains(pos.longitude))
        }

        let suite = "YAAM-Privacy-Regression-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("JN18AA", forKey: "stationGrid")
        defaults.set(false, forKey: "weatherAudioAlertsEnabled")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeatherRequestStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let engine = StationWeatherSafetyEngine(defaults: defaults, session: session, startsAutomatically: false)
        precondition(!engine.isEnabled && engine.locationPrecision == .square)
        await engine.refresh()
        precondition(WeatherRequestStub.count == 0, "Disabled weather must not connect")
        engine.isEnabled = true
        // Enabling schedules a refresh. Await a completed fixture response.
        for _ in 0..<100 where engine.lastUpdated == nil { try await Task.sleep(for: .milliseconds(10)) }
        precondition(engine.lastUpdated != nil && engine.resolvedGrid == "JN18")
        var query = URLComponents(url: WeatherRequestStub.last.url!, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.first { $0.name == "latitude" }?.value == "48.5")
        precondition(query.first { $0.name == "longitude" }?.value == "3.0")
        precondition(!WeatherRequestStub.last.url!.absoluteString.contains("JN18AA"))
        engine.locationPrecision = .subsquare
        for _ in 0..<100 where engine.lastUpdated == nil { try await Task.sleep(for: .milliseconds(10)) }
        precondition(engine.resolvedGrid == "JN18AA")
        query = URLComponents(url: WeatherRequestStub.last.url!, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(abs(Double(query.first { $0.name == "longitude" }!.value!)! - c.longitude) < 0.000001)
        #if STANDALONE_PRIVACY_TEST
        RoverModeEngine.shared.grid = "IO91XX"
        await engine.refresh()
        precondition(engine.resolvedGrid == "IO91XX", "Timer/manual refresh must respect active rover")
        RoverModeEngine.shared.grid = nil
        #endif
        let beforeBad = WeatherRequestStub.count
        await engine.refresh(forcedGrid: "ZZ99AA")
        precondition(WeatherRequestStub.count == beforeBad && engine.currentTelemetry == nil && engine.resolvedCoordinates == nil)
        WeatherRequestStub.holdResponses()
        let pending = Task { await engine.refresh(forcedGrid: "JN18AA") }
        for _ in 0..<100 where WeatherRequestStub.count == beforeBad { try await Task.sleep(for: .milliseconds(10)) }
        engine.isEnabled = false
        await pending.value
        precondition(!engine.isFetching && engine.lastUpdated == nil && engine.currentTelemetry == nil)
        let disabledCount = WeatherRequestStub.count
        await engine.refresh(forcedGrid: "IO91AA")
        precondition(WeatherRequestStub.count == disabledCount, "Disabled rover/forced requests must not connect")
        let restored = StationWeatherSafetyEngine(defaults: defaults, session: session, startsAutomatically: false)
        precondition(!restored.isEnabled && restored.locationPrecision == .subsquare)

        let historyFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("YAAM-History-\(UUID().uuidString).json")
        let legacySeed = CallHistoryRecord(callsign: "DEMO-LEGACY", name: "Legacy sample", source: .builtInSeed)
        let imported = CallHistoryRecord(callsign: "DEMO-IMPORTED", name: "Imported operator", cqZone: 14, source: .importedFile)
        try JSONEncoder().encode([legacySeed, imported]).write(to: historyFile)
        let history = CallHistoryLookupEngine(defaults: defaults, storageURL: historyFile)
        precondition(history.totalRecordsCount == 1 && history.lookup(callsign: "DEMO-LEGACY") == nil)
        precondition(history.lookup(callsign: "demo-imported")?.name == "Imported operator")
        let freshHistory = CallHistoryLookupEngine(defaults: defaults, storageURL: historyFile.appendingPathExtension("empty"))
        precondition(freshHistory.totalRecordsCount == 0, "Fresh history must not invent operator identities")
        try FileManager.default.removeItem(at: historyFile)

        var profile = StationProfile(callsign: "DEMO-A", qth: "Example City", grid: "JN18AA", country: "France", cqZone: "14", ituZone: "27", radioModel: "Example Radio", powerWatts: 50, antennaDescription: "Example Antenna", antennaHeightMeters: 12)
        let station = QSLCardStationInfo(callsign: profile.callsign, profile: profile)
        precondition(station.flag == "🇫🇷" && station.locationLine.contains("Example City") && station.locationLine.contains("CQ: 14") && station.locationLine.contains("ITU: 27"))
        let empty = QSLCardStationInfo(callsign: "DEMO-B", profile: nil)
        precondition(empty.flag.isEmpty && empty.locationLine.isEmpty && empty.radio.isEmpty && empty.antenna.isEmpty && empty.powerWatts == 0)
        profile.country = "Unknown country"
        profile.cqZone = "41"
        profile.ituZone = "0"
        let invalid = QSLCardStationInfo(callsign: "DEMO-C", profile: profile)
        precondition(invalid.flag.isEmpty && !invalid.locationLine.contains("CQ:") && !invalid.locationLine.contains("ITU:"))
        precondition(QSLCardRenderer.usesPersonalTemplate(stationCallsign: " ep2aes\n"))
        for call in ["", "DEMO-A", "EP2AES/P", "EP2AES2", "F/EP2AES"] {
            precondition(!QSLCardRenderer.usesPersonalTemplate(stationCallsign: call))
        }
        let record = QSORecordModel(fields: ["CALL": "DEMO-Z", "QSO_DATE": "20261018", "TIME_ON": "120000", "FREQ": "14.074", "MODE": "FT8", "RST_SENT": "-10", "RST_RCVD": "-08", "NAME": "Example Operator"])
        let output = URL(fileURLWithPath: "/tmp/yaam-privacy-review", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, info) in [("profile", station), ("empty", empty), ("ep2aes", QSLCardStationInfo(callsign: "EP2AES", profile: profile))] {
            let png = output.appendingPathComponent("\(name).png")
            let pdf = output.appendingPathComponent("\(name).pdf")
            try QSLCardRenderer.exportPNG(record: record, station: info, to: png)
            try QSLCardRenderer.exportPDF(record: record, station: info, to: pdf)
            let doc = PDFDocument(url: pdf)!
            precondition(doc.pageCount == 2 && NSImage(contentsOf: png) != nil)
            for pageIndex in 0..<2 {
                let page = doc.page(at: pageIndex)!
                let image = page.thumbnail(of: CGSize(width: 1000, height: 625), for: .mediaBox)
                let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name)-page\(pageIndex + 1).png"))
            }
        }
        #if PRIVACY_VISUAL_REVIEW
        WeatherRequestStub.resumeResponses()
        restored.locationPrecision = .square
        restored.isEnabled = true
        for _ in 0..<100 where restored.lastUpdated == nil { try await Task.sleep(for: .milliseconds(10)) }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            for (width, height) in [(760.0, 500.0), (1100.0, 800.0)] {
                snapshot(AntennaWeatherSafetySettingsView(engine: restored), appearance: appearance, size: CGSize(width: width, height: height), to: output.appendingPathComponent("weather-\(name)-\(Int(width)).png"))
                snapshot(ScrollView { PrivacyHelpView().padding(24) }, appearance: appearance, size: CGSize(width: width, height: height), to: output.appendingPathComponent("privacy-\(name)-\(Int(width)).png"))
            }
        }
        restored.isEnabled = false
        #endif
        print("PASS: privacy defaults, locator precision/validation, actual request coordinates, rover refresh, cancellation, settings persistence and profile/empty QSL PNG + 2-page PDF exports")
    }
    #if PRIVACY_VISUAL_REVIEW
    static func snapshot<Content: View>(_ content: Content, appearance: NSAppearance.Name, size: CGSize, to url: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: appearance)
        let view = NSHostingView(rootView: content
            .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = CGRect(origin: .zero, size: size)
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        view.layoutSubtreeIfNeeded()
        window.display()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
        window.orderOut(nil)
    }
    #endif

}
