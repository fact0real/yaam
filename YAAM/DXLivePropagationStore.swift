import Foundation
import Combine

struct DXReception: Identifiable {
    let id: String
    let receiver: String
    let country: String
    let grid: String
    let band: String
    let mode: String
    let snr: Int?
    let observedAt: Date
    let distanceKm: Int?
}

struct DXWSPRBand: Identifiable {
    let band: String
    let reports: Int
    let latest: Date
    let farthestKm: Int
    var id: String { band }
}

struct DXWSPRReceiver: Identifiable {
    let grid: String
    let distanceKm: Int
    let band: String
    let reports: Int
    let latest: Date
    var id: String { "\(grid)-\(band)" }
}

struct DXRBNReception: Identifiable {
    let id: String
    let spotter: String
    let grid: String
    let band: String
    let mode: String
    let snr: Int
    let observedAt: Date
}

struct DXNOAAConditions {
    var estimatedKp: Double?
    var kpObservedAt: Date?
    var solarFlux: Double?
    var fluxObservedAt: Date?
    var radioBlackoutScale: Int?
    var scalesObservedAt: Date?
}

struct DXIonosonde: Identifiable {
    let id: String
    let name: String
    let foF2MHz: Double
    let distanceKm: Int
    let observedAt: Date
    let confidence: Double?
}

@MainActor final class DXLivePropagationStore: ObservableObject {
    static let shared = DXLivePropagationStore()

    @Published private(set) var receptions: [DXReception] = []
    @Published private(set) var wsprBands: [DXWSPRBand] = []
    @Published private(set) var wsprReceivers: [DXWSPRReceiver] = []
    @Published private(set) var rbnReceptions: [DXRBNReception] = []
    @Published private(set) var noaa = DXNOAAConditions()
    @Published private(set) var ionosondes: [DXIonosonde] = []
    @Published private(set) var pskStatus = "Waiting for station callsign"
    @Published private(set) var wsprStatus = "Waiting for station grid"
    @Published private(set) var ionoStatus = "Not loaded"
    @Published private(set) var rbnStatus = "Waiting for station callsign"
    @Published private(set) var noaaStatus = "Not loaded"
    @Published private(set) var refreshNotice = ""
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private var lastPSKRequest: Date?
    private var lastWSPRRequest: Date?
    private var lastIonoRequest: Date?
    private var lastRBNRequest: Date?
    private var lastNOAARequest: Date?
    private var rbnVersionHash: String?
    private var queriedCallsign = ""
    private var queriedGrid = ""
    private var pendingStation: (callsign: String, grid: String, coordinate: GeoCoordinate)?

    func refresh(callsign: String, grid: String, coordinate: GeoCoordinate, force: Bool = false) {
        let call = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let grid4 = String(grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(4))
        if isRefreshing {
            if call != queriedCallsign || grid4 != queriedGrid {
                pendingStation = (call, grid, coordinate)
            }
            return
        }
        let validCall = call.range(of: #"^[A-Z0-9/]{3,15}$"#, options: .regularExpression) != nil && call != "NOCALL"
        let validGrid = grid4.range(of: #"^[A-R]{2}[0-9]{2}$"#, options: .regularExpression) != nil
        let now = Date()
        let doPSK = validCall && (lastPSKRequest.map { now.timeIntervalSince($0) >= 300 } ?? true)
        let doWSPR = validGrid && (queriedGrid != grid4 || lastWSPRRequest.map { now.timeIntervalSince($0) >= 300 } ?? true)
        let doIono = lastIonoRequest.map { now.timeIntervalSince($0) >= 900 } ?? true
        let doRBN = validCall && (queriedCallsign != call || lastRBNRequest.map { now.timeIntervalSince($0) >= 120 } ?? true)
        let doNOAA = lastNOAARequest.map { now.timeIntervalSince($0) >= 300 } ?? true
        if !validCall { receptions = []; pskStatus = "Set an active station callsign" }
        else if queriedCallsign != call && !doPSK {
            receptions = []
            pskStatus = "Station changed; PSK Reporter refreshes after its five-minute cooldown"
        }
        if !validCall { rbnReceptions = []; rbnStatus = "Set an active station callsign" }
        if !validGrid { wsprBands = []; wsprReceivers = []; wsprStatus = "Set an active station grid" }
        guard doPSK || doWSPR || doIono || doRBN || doNOAA else {
            if force {
                refreshNotice = "All sources were checked recently. PSK Reporter refreshes after five minutes."
            }
            return
        }
        refreshNotice = ""
        isRefreshing = true
        if doPSK { lastPSKRequest = now; queriedCallsign = call; receptions = []; pskStatus = "Loading actual receptions…" }
        if doWSPR { lastWSPRRequest = now; queriedGrid = grid4; wsprBands = []; wsprReceivers = []; wsprStatus = "Loading nearby WSPR spots…" }
        if doIono { lastIonoRequest = now; ionosondes = []; ionoStatus = "Loading ionosonde measurements…" }
        if doRBN { lastRBNRequest = now; rbnReceptions = []; rbnStatus = "Loading RBN skimmer reports…" }
        if doNOAA { lastNOAARequest = now; noaaStatus = "Loading NOAA measurements…" }
        Task {
            async let pskResult: Void = doPSK ? loadPSK(callsign: call, coordinate: coordinate) : ()
            async let wsprResult: Void = doWSPR ? loadWSPR(coordinate: coordinate) : ()
            async let ionoResult: Void = doIono ? loadIonosondes(coordinate: coordinate) : ()
            async let rbnResult: Void = doRBN ? loadRBN(callsign: call) : ()
            async let noaaResult: Void = doNOAA ? loadNOAA() : ()
            _ = await (pskResult, wsprResult, ionoResult, rbnResult, noaaResult)
            lastRefresh = Date()
            isRefreshing = false
            if let pending = pendingStation {
                pendingStation = nil
                refresh(callsign: pending.callsign, grid: pending.grid, coordinate: pending.coordinate)
            }
        }
    }

    private func loadPSK(callsign: String, coordinate: GeoCoordinate) async {
        var parts = URLComponents(string: "https://retrieve.pskreporter.info/query")!
        parts.queryItems = [
            URLQueryItem(name: "senderCallsign", value: callsign),
            URLQueryItem(name: "flowStartSeconds", value: "-7200"),
            URLQueryItem(name: "rptlimit", value: "200"),
            URLQueryItem(name: "rronly", value: "1")
        ]
        do {
            var request = URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            request.setValue("YAAM macOS propagation advisor", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let xml = String(data: data, encoding: .utf8) ?? ""
            let pattern = try NSRegularExpression(pattern: #"<receptionReport\b([^>]*)/?>"#, options: .caseInsensitive)
            let attrPattern = try NSRegularExpression(pattern: #"([A-Za-z0-9_]+)\s*=\s*"([^"]*)""#)
            let now = Date()
            receptions = pattern.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
                guard let range = Range(match.range(at: 1), in: xml) else { return nil }
                let raw = String(xml[range])
                var attrs: [String: String] = [:]
                for attr in attrPattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
                    if let k = Range(attr.range(at: 1), in: raw), let v = Range(attr.range(at: 2), in: raw) {
                        attrs[String(raw[k]).lowercased()] = String(raw[v])
                    }
                }
                guard let frequency = attrs["frequency"].flatMap(Double.init),
                      let seconds = attrs["flowstartseconds"].flatMap(Double.init) else { return nil }
                let date = Date(timeIntervalSince1970: seconds)
                guard now.timeIntervalSince(date) <= 7200, date.timeIntervalSince(now) <= 300 else { return nil }
                let grid = attrs["receiverlocator"] ?? ""
                let distance = MaidenheadGridEngine.boundingBox(for: grid).map {
                    Int(GeodesicMath.distanceKm(from: coordinate, to: $0.center).rounded())
                }
                let band = Self.bandName(frequencyMHz: frequency / 1_000_000)
                let receiver = attrs["receivercallsign"] ?? "?"
                return DXReception(
                    id: "\(attrs["receivercallsign"] ?? "?")-\(Int(seconds))-\(Int(frequency))",
                    receiver: receiver, country: DXCCDatabase.resolve(callsign: receiver).entityName,
                    grid: grid, band: band,
                    mode: attrs["mode"] ?? "?", snr: attrs["snr"].flatMap(Int.init),
                    observedAt: date, distanceKm: distance
                )
            }.sorted { $0.observedAt > $1.observedAt }
            pskStatus = receptions.isEmpty ? "No reception reports in the last 2 hours; this does not prove the band is closed" : "\(receptions.count) reports · latest \(Self.age(receptions[0].observedAt))"
        } catch {
            receptions = []
            pskStatus = "PSK Reporter unavailable: \(error.localizedDescription)"
        }
    }

    private func loadWSPR(coordinate: GeoCoordinate) async {
        // Request the same worldwide grid aggregation for every user. The station location
        // is used only below, on this Mac, and is never sent to WSPR.live.
        let query = "SELECT band, substring(rx_loc,1,4) AS grid4, count() AS reports, max(time) AS latest, max(distance) AS farthest FROM wspr.rx WHERE time > now() - INTERVAL 1 HOUR AND band IN (1,3,5,7,10,14,18,21,24,28) AND match(grid4,'^[A-R]{2}[0-9]{2}$') GROUP BY band, grid4 FORMAT JSON"
        var parts = URLComponents(string: "https://db1.wspr.live/")!
        parts.queryItems = [URLQueryItem(name: "query", value: query)]
        do {
            let (data, response) = try await URLSession.shared.data(from: parts.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let root = try JSONDecoder().decode(WSPRResult.self, from: data)
            var byBand: [Int: DXWSPRBand] = [:]
            var regional: [DXWSPRReceiver] = []
            for row in root.data {
                guard let box = MaidenheadGridEngine.boundingBox(for: row.grid4),
                      let date = Self.utcDate(row.latest),
                      Date().timeIntervalSince(date) >= -300,
                      Date().timeIntervalSince(date) <= 3600 else { continue }
                let distance = Int(GeodesicMath.distanceKm(from: coordinate, to: box.center).rounded())
                regional.append(DXWSPRReceiver(grid: row.grid4, distanceKm: distance,
                                                band: Self.wsprBandName(row.band), reports: row.reports, latest: date))
                guard distance <= 600 else { continue }
                let old = byBand[row.band]
                byBand[row.band] = DXWSPRBand(
                    band: Self.wsprBandName(row.band), reports: (old?.reports ?? 0) + row.reports,
                    latest: max(old?.latest ?? date, date), farthestKm: max(old?.farthestKm ?? 0, row.farthest)
                )
            }
            wsprBands = byBand.values.sorted { $0.reports > $1.reports }
            wsprReceivers = Array(regional.sorted {
                $0.distanceKm == $1.distanceKm ? $0.reports > $1.reports : $0.distanceKm < $1.distanceKm
            }.prefix(12))
            if wsprBands.isEmpty {
                wsprStatus = wsprReceivers.first.map { "No receiver within 600 km; nearest report \($0.distanceKm) km away" }
                    ?? "No WSPR receiver reports in the last hour"
            } else {
                wsprStatus = "Last hour · receiving stations within 600 km · matched locally"
            }
        } catch {
            wsprBands = []
            wsprReceivers = []
            wsprStatus = "WSPR.live unavailable: \(error.localizedDescription)"
        }
    }

    private func loadRBN(callsign: String) async {
        do {
            func spotURL(hash: String?) -> URL? {
                var parts = URLComponents(string: "https://www.reversebeacon.net/spots.php")!
                parts.queryItems = [
                    URLQueryItem(name: "cdx", value: callsign),
                    URLQueryItem(name: "ma", value: "7200"),
                    URLQueryItem(name: "s", value: "0"),
                    URLQueryItem(name: "r", value: "100")
                ]
                if let hash { parts.queryItems?.append(URLQueryItem(name: "h", value: hash)) }
                return parts.url
            }
            guard let initialURL = spotURL(hash: rbnVersionHash) else { throw URLError(.badURL) }
            let initialRequest = URLRequest(url: initialURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
            var (data, response) = try await URLSession.shared.data(for: initialRequest)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if root["error"] != nil, let hash = root["ver_h"] as? String, let retryURL = spotURL(hash: hash) {
                rbnVersionHash = hash
                let retryRequest = URLRequest(url: retryURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
                (data, response) = try await URLSession.shared.data(for: retryRequest)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            }
            if root["error"] != nil { throw URLError(.cannotParseResponse) }
            if let hash = root["ver_h"] as? String { rbnVersionHash = hash }
            let spots = root["spots"] as? [String: [Any]] ?? [:]
            let callInfo = root["call_info"] as? [String: [Any]] ?? [:]
            let now = Date()
            rbnReceptions = spots.compactMap { id, columns in
                guard columns.count >= 11,
                      let spotter = columns[0] as? String,
                      let spotted = columns[2] as? String,
                      spotted.uppercased() == callsign,
                      let frequencyKHz = Double(String(describing: columns[1])),
                      let snr = Int(String(describing: columns[3])),
                      let modeCode = Int(String(describing: columns[9])),
                      let epoch = Double(String(describing: columns[10])) else { return nil }
                let observed = Date(timeIntervalSince1970: epoch)
                guard now.timeIntervalSince(observed) <= 7200,
                      observed.timeIntervalSince(now) <= 300 else { return nil }
                let grid = callInfo[spotter].flatMap { $0.count > 8 ? $0[8] as? String : nil } ?? ""
                let mode = [1: "CW", 11: "RTTY", 34: "FT8", 45: "FT4"][modeCode] ?? "Digital"
                return DXRBNReception(id: id, spotter: spotter, grid: grid,
                                      band: Self.bandName(frequencyMHz: frequencyKHz / 1000),
                                      mode: mode, snr: snr, observedAt: observed)
            }.sorted { $0.observedAt > $1.observedAt }
            rbnStatus = rbnReceptions.isEmpty
                ? "RBN returned no skimmer spots for \(callsign) in the last 2 hours"
                : "\(rbnReceptions.count) direct RBN reports · latest \(Self.age(rbnReceptions[0].observedAt))"
        } catch {
            rbnReceptions = []
            rbnStatus = "RBN feed unavailable: \(error.localizedDescription)"
        }
    }

    private func loadNOAA() async {
        var snapshot = DXNOAAConditions()
        var failures = 0
        do {
            let data = try await publicData("https://services.swpc.noaa.gov/json/planetary_k_index_1m.json")
            let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            if let row = rows.last,
               let time = row["time_tag"] as? String,
               let observed = Self.isoUTCDate(time),
               Date().timeIntervalSince(observed) >= -300,
               Date().timeIntervalSince(observed) < 1800 {
                snapshot.estimatedKp = Self.number(row["estimated_kp"]) ?? Self.number(row["kp_index"])
                snapshot.kpObservedAt = observed
            }
        } catch { failures += 1 }
        do {
            let data = try await publicData("https://services.swpc.noaa.gov/products/summary/10cm-flux.json")
            let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            if let row = rows.last,
               let time = row["time_tag"] as? String,
               let observed = Self.isoUTCDate(time),
               Date().timeIntervalSince(observed) >= -300,
               Date().timeIntervalSince(observed) < 129_600 {
                snapshot.solarFlux = Self.number(row["flux"])
                snapshot.fluxObservedAt = observed
            }
        } catch { failures += 1 }
        do {
            let data = try await publicData("https://services.swpc.noaa.gov/products/noaa-scales.json")
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let current = root["0"] as? [String: Any],
               let day = current["DateStamp"] as? String,
               let time = current["TimeStamp"] as? String,
               let observed = Self.isoUTCDate("\(day)T\(time)"),
               Date().timeIntervalSince(observed) >= -300,
               Date().timeIntervalSince(observed) < 1800,
               let radio = current["R"] as? [String: Any] {
                snapshot.radioBlackoutScale = Int(String(describing: radio["Scale"] ?? ""))
                snapshot.scalesObservedAt = observed
            }
        } catch { failures += 1 }
        noaa = snapshot
        let available = [snapshot.estimatedKp != nil, snapshot.solarFlux != nil, snapshot.radioBlackoutScale != nil].filter { $0 }.count
        noaaStatus = available == 0
            ? (failures == 3 ? "NOAA SWPC is unavailable" : "NOAA values are missing or too old")
            : "\(available) NOAA indicators available · each shown with its own observation time"
    }

    private func publicData(_ address: String) async throws -> Data {
        var request = URLRequest(url: URL(string: address)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 16)
        request.setValue("YAAM macOS propagation advisor", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value else { return nil }
        return Double(String(describing: value))
    }

    private func loadIonosondes(coordinate: GeoCoordinate) async {
        do {
            let (data, response) = try await URLSession.shared.data(from: URL(string: "https://prop.kc2g.com/api/stations.json")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let rows = try JSONDecoder().decode([IonoResult].self, from: data)
            let now = Date()
            ionosondes = rows.compactMap { row in
                guard let value = row.fof2, value > 0, value < 30,
                      row.cs.map({ $0 >= 50 }) ?? true,
                      let date = Self.isoUTCDate(row.time),
                      now.timeIntervalSince(date) >= -300,
                      now.timeIntervalSince(date) <= 5400,
                      let lat = Double(row.station.latitude), let lonRaw = Double(row.station.longitude) else { return nil }
                let lon = lonRaw > 180 ? lonRaw - 360 : lonRaw
                let distance = Int(GeodesicMath.distanceKm(from: coordinate, to: GeoCoordinate(latitude: lat, longitude: lon)).rounded())
                return DXIonosonde(id: row.station.code, name: row.station.name, foF2MHz: value, distanceKm: distance, observedAt: date, confidence: row.cs)
            }.sorted { $0.distanceKm < $1.distanceKm }
            ionoStatus = ionosondes.isEmpty ? "No ionosonde measurements newer than 90 minutes" : "\(ionosondes.count) fresh GIRO-derived measurements worldwide · nearest first"
        } catch {
            ionosondes = []
            ionoStatus = "Ionosonde feed unavailable: \(error.localizedDescription)"
        }
    }

    private static func utcDate(_ value: String) -> Date? {
        wsprDateFormatter.date(from: value)
    }

    private static func isoUTCDate(_ value: String) -> Date? {
        isoDateFormatter.date(from: value)
    }

    private static let wsprDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static func age(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        return minutes < 60 ? "\(minutes)m ago" : "\(minutes / 60)h \(minutes % 60)m ago"
    }

    private static func wsprBandName(_ channel: Int) -> String {
        let bands = [1: "160m", 3: "80m", 5: "60m", 7: "40m", 10: "30m", 14: "20m", 18: "17m", 21: "15m", 24: "12m", 28: "10m"]
        return bands[channel] ?? "\(channel) MHz"
    }

    private static func bandName(frequencyMHz: Double) -> String {
        for (min, max, label) in [(1.8, 2.0, "160m"), (3.5, 4.0, "80m"), (5.25, 5.45, "60m"), (7.0, 7.3, "40m"), (10.1, 10.15, "30m"), (14.0, 14.35, "20m"), (18.068, 18.168, "17m"), (21.0, 21.45, "15m"), (24.89, 24.99, "12m"), (28.0, 29.7, "10m"), (50.0, 54.0, "6m")] {
            if frequencyMHz >= min && frequencyMHz <= max { return label }
        }
        return String(format: "%.2f MHz", frequencyMHz)
    }
}

private struct WSPRResult: Decodable {
    let data: [WSPRRow]
}

private struct WSPRRow: Decodable {
    let band: Int
    let grid4: String
    let reports: Int
    let latest: String
    let farthest: Int
}

private struct IonoResult: Decodable {
    let fof2: Double?
    let cs: Double?
    let time: String
    let station: IonoStation
}

private struct IonoStation: Decodable {
    let name: String
    let code: String
    let latitude: String
    let longitude: String
}
