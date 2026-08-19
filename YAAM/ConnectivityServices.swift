//
//  ConnectivityServices.swift
//  YAAM
//

import Darwin
import Combine
import Foundation
import Network

nonisolated struct CloudSyncQSO: Codable, Equatable, Sendable {
    var id: UUID
    var index: Int
    var fields: [String: String]

    init(_ record: QSORecordModel) {
        id = record.id
        index = record.index
        fields = record.fields
    }

    var model: QSORecordModel { QSORecordModel(id: id, index: index, fields: fields) }
}

nonisolated struct CloudSyncPackage: Codable, Sendable {
    var formatVersion: Int
    var appVersion: String
    var generatedAt: Date
    var deviceID: String
    var stationProfile: StationProfile
    var headers: [String]
    var qsos: [CloudSyncQSO]
}

nonisolated struct CloudMergeResult: Sendable {
    var records: [QSORecordModel]
    var headers: [String]
    var added: Int
    var updated: Int
    var unchanged: Int
}

nonisolated enum CloudSyncMerge {
    static func merge(
        local: [QSORecordModel],
        localHeaders: [String],
        incoming: [CloudSyncQSO],
        incomingHeaders: [String]
    ) -> CloudMergeResult {
        var output = local
        var indexByID: [UUID: Int] = [:]
        var indexByKey: [String: Int] = [:]
        for (index, record) in output.enumerated() {
            indexByID[record.id] = index
            if indexByKey[record.uniqueKey] == nil { indexByKey[record.uniqueKey] = index }
        }
        var added = 0
        var updated = 0
        var unchanged = 0

        for cloud in incoming {
            let candidate = cloud.model
            if let index = indexByID[candidate.id] ?? indexByKey[candidate.uniqueKey] {
                let merged = ImportReviewAnalyzer.mergeUpdate(incoming: candidate.fields, into: output[index].fields)
                if merged != output[index].fields {
                    output[index].fields = merged
                    updated += 1
                } else {
                    unchanged += 1
                }
            } else {
                output.append(candidate)
                let index = output.count - 1
                indexByID[candidate.id] = index
                indexByKey[candidate.uniqueKey] = index
                added += 1
            }
        }

        output.sort { lhs, rhs in
            let left = "\(lhs["QSO_DATE"])\(lhs["TIME_ON"])"
            let right = "\(rhs["QSO_DATE"])\(rhs["TIME_ON"])"
            if left != right { return left < right }
            return lhs.uniqueKey < rhs.uniqueKey
        }
        for index in output.indices { output[index].index = index + 1 }
        var headers = localHeaders
        for header in incomingHeaders + incoming.flatMap({ Array($0.fields.keys) }) where !headers.contains(header) {
            headers.append(header)
        }
        return CloudMergeResult(records: output, headers: headers, added: added, updated: updated, unchanged: unchanged)
    }
}

actor CloudFileCoordinator {
    func write(_ package: CloudSyncPackage, to folderURL: URL) throws -> URL {
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer { if didAccess { folderURL.stopAccessingSecurityScopedResource() } }
        let directory = folderURL.appendingPathComponent("YAAM Sync", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.fileName(for: package.stationProfile))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(package)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func read(profile: StationProfile, from folderURL: URL) throws -> CloudSyncPackage? {
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer { if didAccess { folderURL.stopAccessingSecurityScopedResource() } }
        let directory = folderURL.appendingPathComponent("YAAM Sync", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let safeCallsign = Self.safe(profile.normalizedCallsign)
        let candidates = files
            .filter({ $0.pathExtension == "yaamsync" && $0.lastPathComponent.hasPrefix("\(safeCallsign)-") })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        let expectedName = Self.fileName(for: profile)
        let url: URL
        if let exact = candidates.first(where: { $0.lastPathComponent == expectedName }) {
            url = exact
        } else if candidates.count == 1, let only = candidates.first {
            url = only
        } else if candidates.isEmpty {
            return nil
        } else {
            throw QSLHubError.invalidResponse("More than one cloud package exists for this callsign. Rename the station profile to match the package you want to merge.")
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(CloudSyncPackage.self, from: data)
        guard package.formatVersion == 1,
              package.stationProfile.normalizedCallsign == profile.normalizedCallsign else {
            throw QSLHubError.invalidResponse("The selected cloud package belongs to another callsign or a newer YAAM format.")
        }
        return package
    }

    private static func fileName(for profile: StationProfile) -> String {
        "\(safe(profile.normalizedCallsign))-\(safe(profile.name)).yaamsync"
    }

    private static func safe(_ value: String) -> String {
        let clean = value.uppercased().replacingOccurrences(of: "[^A-Z0-9_-]", with: "-", options: .regularExpression)
        return clean.isEmpty ? "STATION" : clean
    }
}

nonisolated struct MobileAwardSnapshot: Codable, Sendable {
    var id: String
    var title: String
    var confirmed: Int
    var target: Int?
    var percent: Double?
    var stage: String
}

nonisolated struct MobileQSOSnapshot: Codable, Sendable {
    var id: UUID
    var call: String
    var date: String
    var time: String
    var band: String
    var mode: String
    var confirmed: Bool
}

nonisolated struct MobileCompanionSnapshot: Codable, Sendable {
    var station: String
    var generatedAt: Date
    var qsoCount: Int
    var confirmedCount: Int
    var gridCount: Int
    var awards: [MobileAwardSnapshot]
    var recentQSOs: [MobileQSOSnapshot]

    static let empty = MobileCompanionSnapshot(
        station: "NOCALL",
        generatedAt: Date(),
        qsoCount: 0,
        confirmedCount: 0,
        gridCount: 0,
        awards: [],
        recentQSOs: []
    )
}

nonisolated struct MobileQSOPage: Codable, Sendable {
    var items: [MobileQSOSnapshot]
    var total: Int
    var offset: Int
    var limit: Int
}

nonisolated struct MobileQuickLogRequest: Codable, Sendable {
    var callsign: String
    var frequencyMHz: String
    var mode: String
    var rstSent: String?
    var rstReceived: String?
    var comment: String?
}

nonisolated private final class MobileSnapshotStore: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = MobileCompanionSnapshot.empty
    private var qsos: [MobileQSOSnapshot] = []

    func set(_ value: MobileCompanionSnapshot, qsos: [MobileQSOSnapshot]) {
        lock.lock()
        snapshot = value
        self.qsos = qsos
        lock.unlock()
    }

    func get() -> MobileCompanionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func qsoPage(offset: Int, limit: Int) -> MobileQSOPage {
        lock.lock()
        defer { lock.unlock() }
        let start = min(max(0, offset), qsos.count)
        let pageLimit = max(1, limit)
        let end = min(qsos.count, start + pageLimit)
        return MobileQSOPage(
            items: Array(qsos[start..<end]),
            total: qsos.count,
            offset: start,
            limit: pageLimit
        )
    }
}

final class MobileCompanionServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Off"
    @Published private(set) var address = ""

    private let snapshotStore = MobileSnapshotStore()
    private var listener: NWListener?
    private var token = ""
    private var port: UInt16 = 7373
    var quickLogHandler: ((MobileQuickLogRequest) -> Void)?

    func update(snapshot: MobileCompanionSnapshot, qsos: [MobileQSOSnapshot]) {
        snapshotStore.set(snapshot, qsos: qsos)
    }

    func start(port requestedPort: UInt16, token: String) throws {
        stop()
        guard !token.isEmpty else { throw QSLHubError.missingCredential("mobile API token") }
        let nwPort = NWEndpoint.Port(rawValue: requestedPort) ?? 7373
        let listener = try NWListener(using: .tcp, on: nwPort)
        self.token = token
        port = requestedPort
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.apply(state: state) }
        }
        listener.start(queue: DispatchQueue(label: "app.yaam.mobile-companion", qos: .utility))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        status = "Off"
        address = ""
    }

    private func apply(state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            status = "Available on the local network"
            address = "http://\(Self.localIPv4Address() ?? "127.0.0.1"):\(port)/?token=\(token)"
        case .failed(let error):
            isRunning = false
            status = error.localizedDescription
        case .cancelled:
            isRunning = false
            status = "Off"
        default:
            status = "Starting..."
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "app.yaam.mobile-client", qos: .utility))
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, _, error in
            Task { @MainActor [weak self, data, error, connection, buffer] in
                guard let self else { return }
                guard error == nil else {
                    connection.cancel()
                    return
                }
                var combined = buffer
                if let data { combined.append(data) }
                guard combined.count <= 1_048_576 else {
                    connection.send(content: Self.http(status: 400, type: "text/plain", body: Data("Request too large".utf8)), completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
                if Self.isCompleteHTTPRequest(combined) {
                    let response = self.route(combined)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                } else {
                    self.receiveRequest(on: connection, buffer: combined)
                }
            }
        }
    }

    private func route(_ data: Data) -> Data {
        guard let request = String(data: data, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            return Self.http(status: 400, type: "text/plain", body: Data("Bad request".utf8))
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return Self.http(status: 400, type: "text/plain", body: Data("Bad request".utf8)) }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let components = URLComponents(string: "http://localhost\(target)")
        let queryToken = components?.queryItems?.first(where: { $0.name == "token" })?.value ?? ""
        let bearer = request.components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("authorization: bearer ") })?
            .dropFirst("Authorization: Bearer ".count)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard queryToken == token || bearer == token else {
            return Self.http(status: 401, type: "application/json", body: Data("{\"error\":\"unauthorized\"}".utf8))
        }

        let path = components?.path ?? "/"
        let snapshot = snapshotStore.get()
        if method == "GET", path == "/" {
            return Self.http(status: 200, type: "text/html; charset=utf-8", body: Data(Self.dashboardHTML(token: token).utf8))
        }
        if method == "GET", path == "/api/v1/status" {
            return Self.json(snapshot)
        }
        if method == "GET", path == "/api/v1/qsos" {
            let requestedLimit = components?.queryItems?
                .first(where: { $0.name == "limit" })?.value.flatMap(Int.init) ?? 100
            let requestedOffset = components?.queryItems?
                .first(where: { $0.name == "offset" })?.value.flatMap(Int.init) ?? 0
            return Self.json(
                snapshotStore.qsoPage(
                    offset: max(0, requestedOffset),
                    limit: min(500, max(1, requestedLimit))
                )
            )
        }
        if method == "GET", path == "/api/v1/awards" {
            return Self.json(snapshot.awards)
        }
        if method == "POST", path == "/api/v1/qsos" {
            guard let bodyRange = request.range(of: "\r\n\r\n") else {
                return Self.http(status: 400, type: "application/json", body: Data("{\"error\":\"missing body\"}".utf8))
            }
            let body = Data(request[bodyRange.upperBound...].utf8)
            guard let payload = try? JSONDecoder().decode(MobileQuickLogRequest.self, from: body) else {
                return Self.http(status: 400, type: "application/json", body: Data("{\"error\":\"invalid QSO\"}".utf8))
            }
            Task { @MainActor [weak self] in self?.quickLogHandler?(payload) }
            return Self.http(status: 202, type: "application/json", body: Data("{\"status\":\"queued\"}".utf8))
        }
        return Self.http(status: 404, type: "application/json", body: Data("{\"error\":\"not found\"}".utf8))
    }

    private nonisolated static func json<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return http(status: 200, type: "application/json", body: data)
    }

    private nonisolated static func http(status: Int, type: String, body: Data) -> Data {
        let reason = switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        default: "Error"
        }
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        response.append(body)
        return response
    }

    private nonisolated static func isCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8), let marker = text.range(of: "\r\n\r\n") else { return false }
        let headers = String(text[..<marker.lowerBound])
        let lengthLine = headers.components(separatedBy: "\r\n").first {
            $0.lowercased().hasPrefix("content-length:")
        }
        let contentLength = lengthLine.flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
        let bodyLength = text[marker.upperBound...].utf8.count
        return bodyLength >= contentLength
    }

    private nonisolated static func dashboardHTML(token: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>YAAM Mobile</title><style>
        :root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,sans-serif}body{margin:0;background:#101214;color:#f5f5f5}header{padding:20px;background:#1877e8}main{padding:16px;max-width:760px;margin:auto}.metrics{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.metric,.panel{border:1px solid #34383c;border-radius:8px;padding:14px;background:#191c1f}.metric b{font-size:24px;display:block}h2{font-size:17px;margin-top:24px}table{width:100%;border-collapse:collapse}td,th{padding:10px 4px;border-bottom:1px solid #34383c;text-align:left}input,select,button{font:inherit;padding:12px;border-radius:6px;border:1px solid #555;background:#24282c;color:inherit}form{display:grid;grid-template-columns:2fr 1fr 1fr;gap:8px}button{background:#1877e8;border:0;font-weight:700}@media(max-width:560px){form{grid-template-columns:1fr}.metrics{grid-template-columns:1fr}}
        </style></head><body><header><strong id="station">YAAM Mobile</strong><div>Local station companion</div></header><main>
        <div class="metrics"><div class="metric"><b id="qso">0</b>QSOs</div><div class="metric"><b id="confirmed">0</b>Confirmed</div><div class="metric"><b id="grids">0</b>Grids</div></div>
        <h2>Quick Log</h2><form id="log"><input id="call" placeholder="Callsign" required><input id="freq" placeholder="MHz" required><select id="mode"><option>SSB</option><option>CW</option><option>FT8</option><option>FM</option></select><button>Log QSO</button></form>
        <h2>Recent QSOs</h2><div class="panel"><table><thead><tr><th>Call</th><th>Band</th><th>Mode</th><th>UTC</th></tr></thead><tbody id="rows"></tbody></table></div>
        <h2>Award progress</h2><div class="panel" id="awards"></div></main><script>
        const token='\(token)';const headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'};const esc=s=>{const d=document.createElement('div');d.textContent=String(s??'');return d.innerHTML};
        async function load(){const s=await fetch('/api/v1/status',{headers}).then(r=>r.json());station.textContent=s.station;qso.textContent=s.qsoCount;confirmed.textContent=s.confirmedCount;grids.textContent=s.gridCount;rows.innerHTML=s.recentQSOs.map(x=>`<tr><td>${esc(x.call)}</td><td>${esc(x.band)}</td><td>${esc(x.mode)}</td><td>${esc(x.time)}</td></tr>`).join('');awards.innerHTML=s.awards.map(x=>`<p><b>${esc(x.title)}</b><br>${x.confirmed}${x.target?' / '+x.target:''} ${x.percent==null?'':'· '+Math.round(x.percent)+'%'}</p>`).join('')}
        log.onsubmit=async e=>{e.preventDefault();await fetch('/api/v1/qsos',{method:'POST',headers,body:JSON.stringify({callsign:call.value,frequencyMHz:freq.value,mode:mode.value})});call.value='';setTimeout(load,600)};load();setInterval(load,10000);
        </script></body></html>
        """
    }

    private nonisolated static func localIPv4Address() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            let interface = item.pointee
            defer { cursor = interface.ifa_next }
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            if getnameinfo(address, length, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: hostname)
            }
        }
        return nil
    }
}
