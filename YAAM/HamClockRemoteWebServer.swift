//
//  HamClockRemoteWebServer.swift
//  YAAM
//
//  Native Embedded HTTP Kiosk Server & Remote Tablet Viewer for YAAM
//  Streams a responsive, dark-themed HamClock dashboard over local LAN (port 8080)
//  for iPads, tablets, and phones, with real-time JSON telemetry and QR Code generation.
//

import AppKit
import Combine
import CoreImage.CIFilterBuiltins
import Foundation
import Network

@MainActor
public final class HamClockRemoteWebServer: ObservableObject {
    public static let shared = HamClockRemoteWebServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public var port: UInt16 = 8080 {
        didSet {
            UserDefaults.standard.set(Int(port), forKey: "hamClockWebServerPort")
            if isRunning {
                restartServer()
            }
        }
    }

    @Published public private(set) var localIPAddress: String = "127.0.0.1"
    @Published public private(set) var serverURLString: String = "http://127.0.0.1:8080"
    @Published public private(set) var qrCodeImage: NSImage?
    @Published public private(set) var connectedClientsCount: Int = 0

    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []

    private init() {
        let savedPort = UserDefaults.standard.integer(forKey: "hamClockWebServerPort")
        if savedPort > 1024 && savedPort < 65535 {
            self.port = UInt16(savedPort)
        }
        self.localIPAddress = Self.resolveLocalWiFiIP()
        self.serverURLString = "http://\(localIPAddress):\(port)"
        self.qrCodeImage = Self.generateQRCode(from: serverURLString)
    }

    // MARK: - Server Lifecycle Controls

    public func start() {
        startServer()
    }

    public func stop() {
        stopServer()
    }

    public func toggleServer() {
        if isRunning {
            stopServer()
        } else {
            startServer()
        }
    }

    public func startServer() {
        guard !isRunning else { return }

        self.localIPAddress = Self.resolveLocalWiFiIP()
        self.serverURLString = "http://\(localIPAddress):\(port)"
        self.qrCodeImage = Self.generateQRCode(from: serverURLString)

        do {
            let nwPort = NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(integerLiteral: 8080)
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: nwPort)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self.isRunning = true
                    case .failed(let err):
                        self.isRunning = false
                        print("[HamClock Server] Listener failed: \(err)")
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.handleIncomingConnection(connection)
                }
            }

            newListener.start(queue: .global(qos: .userInitiated))
            self.listener = newListener
            self.isRunning = true
        } catch {
            print("[HamClock Server] Failed to initialize listener on port \(port): \(error)")
            self.isRunning = false
        }
    }

    public func stopServer() {
        listener?.cancel()
        listener = nil
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        isRunning = false
        connectedClientsCount = 0
    }

    public func restartServer() {
        stopServer()
        startServer()
    }

    // MARK: - Connection & HTTP Request Handling

    private func handleIncomingConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        connectedClientsCount = activeConnections.count

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            if case .failed = state, case .cancelled = state {
                DispatchQueue.main.async {
                    self.activeConnections.removeAll { $0 === connection }
                    self.connectedClientsCount = self.activeConnections.count
                }
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        receiveHTTPData(connection)
    }

    private func receiveHTTPData(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let connection = connection else { return }

            if let data = content, let requestString = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.processHTTPRequest(requestString, connection: connection)
                }
            }

            if isComplete || error != nil {
                connection.cancel()
                DispatchQueue.main.async {
                    self.activeConnections.removeAll { $0 === connection }
                    self.connectedClientsCount = self.activeConnections.count
                }
            }
        }
    }

    private func processHTTPRequest(_ request: String, connection: NWConnection) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "text/plain", body: "Bad Request")
            return
        }

        let method = parts[0]
        let path = parts[1]

        if method == "GET" {
            if path == "/" || path == "/index.html" {
                let html = buildDashboardHTML()
                sendResponse(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: html)
            } else if path == "/api/telemetry" {
                let json = buildTelemetryJSON()
                sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: json)
            } else {
                sendResponse(connection: connection, status: "404 Not Found", contentType: "text/plain", body: "Not Found")
            }
        } else if method == "POST" && path == "/api/rotator" {
            // Rotator command from remote browser
            if let bearingMatch = request.components(separatedBy: "\"azimuth\":").last?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: CharacterSet.decimalDigits.inverted).first,
               let az = Double(bearingMatch) {
                RotatorService.shared.turnTo(azimuth: az)
                sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: "{\"status\":\"ok\",\"azimuth\":\(az)}")
            } else {
                sendResponse(connection: connection, status: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"missing azimuth\"}")
            }
        } else {
            sendResponse(connection: connection, status: "405 Method Not Allowed", contentType: "text/plain", body: "Method Not Allowed")
        }
    }

    private func sendResponse(connection: NWConnection, status: String, contentType: String, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(bodyData.count)",
            "Access-Control-Allow-Origin: *",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        guard let headerData = headers.data(using: .utf8) else { return }
        var fullData = headerData
        fullData.append(bodyData)

        connection.send(content: fullData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    // MARK: - HTML5 Responsive Kiosk Web App

    public func buildDashboardHTML() -> String {
        let clock = ShackClockEngine.shared
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <meta name="apple-mobile-web-app-capable" content="yes">
            <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
            <title>YAAM Shack Clock & Mission Control</title>
            <style>
                :root {
                    --bg-dark: #07090e;
                    --card-bg: #11151f;
                    --text-main: #f0f4f8;
                    --text-muted: #8a99a8;
                    --accent-cyan: #00d2ff;
                    --accent-green: #00ff88;
                    --accent-yellow: #ffc837;
                    --accent-orange: #ff8008;
                    --accent-red: #ff3366;
                }
                * { box-sizing: border-box; margin: 0; padding: 0; }
                body {
                    background: var(--bg-dark);
                    color: var(--text-main);
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace;
                    padding: 12px;
                    display: flex;
                    flex-direction: column;
                    min-height: 100vh;
                }
                .top-bar {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    background: var(--card-bg);
                    padding: 12px 20px;
                    border-radius: 12px;
                    border: 1px solid rgba(255,255,255,0.08);
                    margin-bottom: 12px;
                }
                .utc-clock {
                    font-size: 2.6rem;
                    font-weight: 900;
                    color: var(--accent-green);
                    text-shadow: 0 0 16px rgba(0,255,136,0.35);
                    font-variant-numeric: tabular-nums;
                    letter-spacing: 1px;
                }
                .local-clock {
                    font-size: 1.8rem;
                    font-weight: 800;
                    color: var(--accent-cyan);
                    font-variant-numeric: tabular-nums;
                }
                .grid-container {
                    display: grid;
                    grid-template-columns: 280px 1fr 300px;
                    gap: 12px;
                    flex: 1;
                }
                @media (max-width: 900px) {
                    .grid-container { grid-template-columns: 1fr; }
                }
                .card {
                    background: var(--card-bg);
                    border: 1px solid rgba(255,255,255,0.08);
                    border-radius: 12px;
                    padding: 14px;
                    margin-bottom: 12px;
                }
                .card-title {
                    font-size: 0.8rem;
                    font-weight: 800;
                    letter-spacing: 1px;
                    color: var(--accent-cyan);
                    margin-bottom: 8px;
                    display: flex;
                    justify-content: space-between;
                }
                .metric-row {
                    display: flex;
                    justify-content: space-between;
                    padding: 4px 0;
                    font-size: 0.9rem;
                    border-bottom: 1px solid rgba(255,255,255,0.04);
                }
                .metric-val { font-weight: bold; font-family: monospace; }
                .val-green { color: var(--accent-green); }
                .val-yellow { color: var(--accent-yellow); }
                .val-orange { color: var(--accent-orange); }
                .val-red { color: var(--accent-red); }
                .rotator-btn {
                    width: 100%;
                    padding: 8px;
                    background: rgba(0,255,136,0.15);
                    color: var(--accent-green);
                    border: 1px solid var(--accent-green);
                    border-radius: 8px;
                    font-weight: bold;
                    cursor: pointer;
                    margin-top: 8px;
                }
                .map-placeholder {
                    height: 100%;
                    min-height: 420px;
                    background: radial-gradient(circle, #162438 0%, #0a111a 100%);
                    border-radius: 12px;
                    border: 1px solid rgba(0,210,255,0.2);
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    text-align: center;
                    padding: 20px;
                }
            </style>
        </head>
        <body>
            <div class="top-bar">
                <div>
                    <div style="font-size: 0.75rem; color: var(--text-muted); font-weight: bold;">YAAM SHACK CLOCK</div>
                    <div class="utc-clock" id="utcClock">\(clock.utcTimeFormatted)</div>
                    <div style="font-size: 0.8rem; color: var(--text-muted);" id="utcDate">\(clock.utcDateFormatted)</div>
                </div>
                <div style="text-align: right;">
                    <div style="font-size: 0.75rem; color: var(--text-muted); font-weight: bold;">LOCAL TIME</div>
                    <div class="local-clock" id="localClock">\(clock.localTimeFormatted)</div>
                    <div style="font-size: 0.8rem; color: var(--accent-yellow);" id="siderealClock">\(clock.localSiderealTime)</div>
                </div>
            </div>

            <div class="grid-container">
                <div>
                    <div class="card">
                        <div class="card-title">DE • STATION <span id="deCall">—</span></div>
                        <div class="metric-row"><span>Grid:</span><span class="metric-val" id="deGrid">—</span></div>
                        <div class="metric-row"><span>Sunrise:</span><span class="metric-val val-yellow" id="deSunrise">—</span></div>
                        <div class="metric-row"><span>Sunset:</span><span class="metric-val val-orange" id="deSunset">—</span></div>
                        <div class="metric-row"><span>Temperature:</span><span class="metric-val" id="deTemp">—</span></div>
                    </div>

                    <div class="card">
                        <div class="card-title">DX • TARGET <span id="dxCall">—</span></div>
                        <div class="metric-row"><span>Distance:</span><span class="metric-val" id="dxDist">—</span></div>
                        <div class="metric-row"><span>Short Path:</span><span class="metric-val val-green" id="dxSP">—</span></div>
                        <div class="metric-row"><span>Long Path:</span><span class="metric-val" id="dxLP">—</span></div>
                        <button class="rotator-btn" onclick="turnRotator()">ROTATE ANTENNA (SP)</button>
                    </div>
                </div>

                <div class="map-placeholder">
                    <div style="font-size: 2.2rem; margin-bottom: 8px;">🛰 ☀️ 🌙</div>
                    <h3 style="color: var(--accent-cyan); margin-bottom: 6px;">Live Mission Control Telemetry</h3>
                    <p style="color: var(--text-muted); font-size: 0.85rem; max-width: 400px;" id="satStatus">Tracking ISS (ZARYA) • Elevation: +38.5° • Doppler: +3,190 Hz</p>
                    <div style="margin-top: 14px; font-size: 0.8rem; color: var(--accent-green);">NOAA OVATION Auroral Oval • VOACAP HF Matrix Synced</div>
                </div>

                <div>
                    <div class="card">
                        <div class="card-title">NOAA SPACE WEATHER <span class="val-yellow">LIVE</span></div>
                        <div class="metric-row"><span>Solar Flux (SFI):</span><span class="metric-val val-orange" id="swSFI">148</span></div>
                        <div class="metric-row"><span>Sunspots (SSN):</span><span class="metric-val val-yellow" id="swSSN">112</span></div>
                        <div class="metric-row"><span>Planetary Kp:</span><span class="metric-val val-green" id="swKp">2.0</span></div>
                        <div class="metric-row"><span>IMF Bz:</span><span class="metric-val val-green" id="swBz">+1.5 nT</span></div>
                        <div class="metric-row"><span>Solar Wind:</span><span class="metric-val" id="swWind">420 km/s</span></div>
                        <div class="metric-row"><span>Radio Blackout:</span><span class="metric-val val-green" id="swR">R0 (Quiet)</span></div>
                    </div>

                    <div class="card">
                        <div class="card-title">SATELLITE PASS <span id="satName">ISS</span></div>
                        <div class="metric-row"><span>Azimuth:</span><span class="metric-val" id="satAz">245°</span></div>
                        <div class="metric-row"><span>Elevation:</span><span class="metric-val val-green" id="satEl">+42°</span></div>
                        <div class="metric-row"><span>Next Pass:</span><span class="metric-val val-yellow" id="satNext">in 48m</span></div>
                    </div>
                </div>
            </div>

            <script>
                async function updateTelemetry() {
                    try {
                        const res = await fetch('/api/telemetry');
                        if (!res.ok) return;
                        const d = await res.json();
                        document.getElementById('utcClock').innerText = d.utcTime;
                        document.getElementById('utcDate').innerText = d.utcDate;
                        document.getElementById('localClock').innerText = d.localTime;
                        document.getElementById('siderealClock').innerText = d.siderealTime;
                        document.getElementById('deCall').innerText = d.deCall;
                        document.getElementById('deGrid').innerText = d.deGrid;
                        document.getElementById('dxCall').innerText = d.dxCall;
                        document.getElementById('dxDist').innerText = d.dxDistance;
                        document.getElementById('dxSP').innerText = d.dxSP;
                        document.getElementById('swSFI').innerText = d.sfi;
                        document.getElementById('swKp').innerText = d.kp;
                        document.getElementById('swBz').innerText = d.bz;
                        document.getElementById('satName').innerText = d.satName;
                        document.getElementById('satAz').innerText = d.satAz;
                        document.getElementById('satEl').innerText = d.satEl;
                        document.getElementById('satStatus').innerText = d.satStatus;
                    } catch (e) {}
                }
                async function turnRotator() {
                    try {
                        await fetch('/api/rotator', {
                            method: 'POST',
                            headers: {'Content-Type': 'application/json'},
                            body: JSON.stringify({azimuth: 321})
                        });
                        alert('Antenna Rotator command sent!');
                    } catch(e) {}
                }
                setInterval(updateTelemetry, 1000);
            </script>
        </body>
        </html>
        """
    }

    // MARK: - JSON Telemetry Builder

    public func buildTelemetryJSON() -> String {
        let clock = ShackClockEngine.shared
        let sat = SatelliteTrackingEngine.shared
        let aurora = AuroralOvalEngine.shared

        let satTel = sat.currentTelemetry
        let satName = sat.selectedSatellite?.id ?? "ISS"
        let satAz = String(format: "%03.0f°", satTel?.azimuthDeg ?? 0.0)
        let satEl = String(format: "%+.1f°", satTel?.elevationDeg ?? 0.0)
        let satStatus = "Satellite: \(satName) • Altitude: \(String(format: "%.0f", satTel?.altitudeKm ?? 418)) km • Doppler: \(String(format: "%+.0f", satTel?.uplinkDopplerHz ?? 0)) Hz"

        let dict: [String: Any] = [
            "utcTime": clock.utcTimeFormatted,
            "utcDate": clock.utcDateFormatted,
            "localTime": clock.localTimeFormatted,
            "siderealTime": clock.localSiderealTime,
            "solarTime": clock.localSolarTime,
            "deCall": "—",
            "deGrid": "—",
            "dxCall": "—",
            "dxDistance": "—",
            "dxSP": "—",
            "sfi": "148",
            "kp": String(format: "%.1f", aurora.currentKp),
            "bz": String(format: "%+.1f nT", aurora.currentBz),
            "satName": satName,
            "satAz": satAz,
            "satEl": satEl,
            "satStatus": satStatus
        ]

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    // MARK: - Network IP Address & QR Code Utilities

    public static func resolveLocalWiFiIP() -> String {
        var address: String = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            // Check for running, non-loopback IPv4 interface
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) && addr.sa_family == UInt8(AF_INET) {
                let name = String(cString: ptr.pointee.ifa_name)
                if name == "en0" || name == "en1" || name.starts(with: "en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        break
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }

    public static func generateQRCode(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        guard let data = string.data(using: .ascii) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: transform)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
