//
//  LocalClusterServer.swift
//  YAAM
//
//  Embedded local Telnet cluster server and UDP spot broadcaster.
//  Distributes filtered DX cluster spots to local logging applications
//  (WSJT-X, RUMlogNG, MacLoggerDX, N1MM Logger, Log4OM).
//

import Foundation
import Network
import Combine

public final class LocalClusterServer: ObservableObject {
    public static let shared = LocalClusterServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public var port: Int = 7300 {
        didSet {
            defaults.set(port, forKey: "localClusterServerPort")
            if isRunning {
                restart()
            }
        }
    }
    @Published public private(set) var clientCount: Int = 0
    @Published public private(set) var clientCallsigns: [String] = []

    @Published public var udpEnabled: Bool = false {
        didSet {
            defaults.set(udpEnabled, forKey: "localClusterUDPEnabled")
        }
    }
    @Published public var udpPort: Int = 12060 {
        didSet {
            defaults.set(udpPort, forKey: "localClusterUDPPort")
        }
    }
    @Published public private(set) var broadcastSpotCount: Int = 0
    @Published public private(set) var lastErrorMessage: String?

    private var udpRequestID: UUID?
    private var listener: NWListener?
    private var clients: [UUID: LocalClientSession] = [:]
    private var recentSpots: [DXSpot] = []
    private let maxRecentSpots: Int = 100
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "app.yaam.local-cluster-server", qos: .userInitiated)
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let savedPort = defaults.value(forKey: "localClusterServerPort") as? Int, (1...65535).contains(savedPort) {
            self.port = savedPort
        }
        if let savedUDPPort = defaults.value(forKey: "localClusterUDPPort") as? Int, (1...65535).contains(savedUDPPort) {
            self.udpPort = savedUDPPort
        }
        if let savedUDPEnabled = defaults.value(forKey: "localClusterUDPEnabled") as? Bool {
            self.udpEnabled = savedUDPEnabled
        }

        let autoStart = defaults.object(forKey: "localClusterAutoStart") as? Bool ?? false
        if autoStart {
            start()
        }
    }

    // MARK: - Lifecycle

    public func start() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.listener == nil else { return }

            do {
                guard (1...65535).contains(self.port), let nwPort = NWEndpoint.Port(rawValue: UInt16(self.port)) else {
                    throw NSError(domain: "LocalClusterServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port \(self.port)"])
                }

                let tcpOptions = NWProtocolTCP.Options()
                tcpOptions.enableKeepalive = true
                tcpOptions.keepaliveIdle = 30
                let params = NWParameters(tls: nil, tcp: tcpOptions)
                params.allowLocalEndpointReuse = true
                params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)

                let listener = try NWListener(using: params)
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, self.listener === listener else { return }
                    if case .failed = state { self.listener = nil }
                    self.handleListenerState(state)
                }

                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { return }
                    self.handleNewConnection(connection)
                }

                listener.start(queue: self.queue)
                self.listener = listener
            } catch {
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.stateUpdateHandler = nil
            self.listener?.cancel()
            self.listener = nil

            for (_, session) in self.clients {
                session.send("73! YAAM Local Server shutting down.\r\n")
                session.close()
            }
            self.clients.removeAll()

            DispatchQueue.main.async {
                self.isRunning = false
                self.clientCount = 0
                self.clientCallsigns = []
            }
        }
    }

    public func restart() {
        stop()
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.start()
        }
    }

    // MARK: - Listener & Connection Management

    private func handleListenerState(_ state: NWListener.State) {
        DispatchQueue.main.async {
            switch state {
            case .ready:
                self.isRunning = true
                self.lastErrorMessage = nil
            case .failed(let error):
                self.isRunning = false
                self.lastErrorMessage = error.localizedDescription
            case .cancelled:
                self.isRunning = false
            default:
                break
            }
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        guard clients.count < 8 else { connection.cancel(); return }
        let session = LocalClientSession(connection: connection)
        clients[session.id] = session

        session.onDisconnect = { [weak self] id in
            self?.queue.async {
                self?.clients.removeValue(forKey: id)
                self?.updateClientState()
            }
        }

        session.onCallsignSet = { [weak self] _ in
            self?.queue.async {
                self?.updateClientState()
            }
        }

        session.onCommand = { [weak self] cmd, reply in
            self?.handleClientCommand(cmd, reply: reply)
        }

        session.start(queue: queue)
        updateClientState()
    }

    private func updateClientState() {
        let calls = clients.values.compactMap { $0.callsign }
        let count = clients.count
        DispatchQueue.main.async {
            self.clientCount = count
            self.clientCallsigns = calls
        }
    }

    private func handleClientCommand(_ rawCommand: String, reply: @escaping (String) -> Void) {
        let cmd = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cmd == "HELP" {
            reply("""
            YAAM Local DX Cluster Commands:
              SH/DX [n]   - Show recent DX spots
              PING        - Keepalive test (replies PONG)
              BYE / QUIT  - Disconnect from local server
              HELP        - Show this help message
            YAAM> 
            """)
        } else if cmd.hasPrefix("SH/DX") || cmd.hasPrefix("SHOW/DX") {
            lock.lock()
            let spots = recentSpots.suffix(20)
            lock.unlock()

            if spots.isEmpty {
                reply("No spots in local cache.\r\nYAAM> ")
            } else {
                var out = "Recent DX Spots from YAAM:\r\n"
                for s in spots {
                    out.append(formatTelnetSpot(s))
                }
                out.append("YAAM> ")
                reply(out)
            }
        } else if cmd == "PING" {
            reply("PONG\r\nYAAM> ")
        } else if cmd == "QUIT" || cmd == "BYE" {
            reply("73 de YAAM Local Server!\r\n")
        } else {
            reply("YAAM: Unknown command '\(LocalClusterWirePolicy.line(rawCommand))'. Type HELP for commands.\r\nYAAM> ")
        }
    }

    // MARK: - Spot Broadcasting (Telnet + UDP)

    func broadcastSpot(_ spot: DXSpot) {
        lock.lock()
        recentSpots.append(spot)
        if recentSpots.count > maxRecentSpots {
            recentSpots.removeFirst(recentSpots.count - maxRecentSpots)
        }
        lock.unlock()

        let telnetLine = formatTelnetSpot(spot)

        queue.async { [weak self] in
            guard let self else { return }

            // 1. Broadcast to all active Telnet clients
            for (_, session) in self.clients where session.isAuthenticated {
                session.send(telnetLine)
            }

            // 2. Broadcast via UDP if enabled
            if self.udpEnabled && self.listener != nil {
                self.sendUDPBroadcast(spot: spot, telnetLine: telnetLine)
            }

            DispatchQueue.main.async {
                self.broadcastSpotCount += 1
            }
        }
    }

    private func formatTelnetSpot(_ spot: DXSpot) -> String {
        let spotterClean = LocalClusterWirePolicy.line(spot.spotter).replacingOccurrences(of: ":", with: "")
        let spotterField = (spotterClean + ":").padding(toLength: 10, withPad: " ", startingAt: 0)
        let freqStr = String(format: "%8.1f", spot.frequencyKHz)
        let callField = LocalClusterWirePolicy.line(spot.callsign).padding(toLength: 12, withPad: " ", startingAt: 0)
        let commentField = LocalClusterWirePolicy.line(spot.comment.isEmpty ? spot.grid : spot.comment)
            .prefix(30)
            .padding(toLength: 30, withPad: " ", startingAt: 0)

        let formatter = GregorianDate.formatter("HHmm", timeZone: TimeZone(secondsFromGMT: 0))
        let timeStr = formatter.string(from: spot.lastSeenAt)

        return "DX de \(spotterField) \(freqStr)  \(callField) \(commentField) \(timeStr)Z\r\n"
    }

    private func sendUDPBroadcast(spot: DXSpot, telnetLine: String) {
        guard (1...65535).contains(udpPort), spot.frequencyKHz.isFinite, udpRequestID == nil,
              let port = NWEndpoint.Port(rawValue: UInt16(udpPort)) else { return }
        let requestID = UUID()
        udpRequestID = requestID

        // Standard N1MM XML Spot packet for logging software
        let isoFormatter = ISO8601DateFormatter()
        let timeStr = isoFormatter.string(from: spot.lastSeenAt)

        let xmlPacket = """
        <?xml version="1.0" encoding="utf-8"?>
        <spot>
          <station>\(LocalClusterWirePolicy.xml(spot.callsign))</station>
          <frequency>\(spot.frequencyKHz * 1000.0)</frequency>
          <mode>\(LocalClusterWirePolicy.xml(spot.mode))</mode>
          <spotter>\(LocalClusterWirePolicy.xml(spot.spotter))</spotter>
          <comment>\(LocalClusterWirePolicy.xml(spot.comment))</comment>
          <grid>\(LocalClusterWirePolicy.xml(spot.grid))</grid>
          <band>\(LocalClusterWirePolicy.xml(spot.band))</band>
          <time>\(timeStr)</time>
        </spot>
        """

        let packetData = xmlPacket.data(using: String.Encoding.utf8) ?? telnetLine.data(using: String.Encoding.utf8) ?? Data()

        let udpParams = NWParameters.udp
        udpParams.allowLocalEndpointReuse = true
        let broadcastConn = NWConnection(to: .hostPort(host: .ipv4(.loopback), port: port), using: udpParams)
        broadcastConn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                broadcastConn.send(content: packetData, completion: .contentProcessed({ _ in
                    if self?.udpRequestID == requestID { self?.udpRequestID = nil }
                    broadcastConn.cancel()
                }))
            } else if case .failed = state {
                if self?.udpRequestID == requestID { self?.udpRequestID = nil }
                    broadcastConn.cancel()
            }
        }
        broadcastConn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            broadcastConn.stateUpdateHandler = nil
            broadcastConn.cancel()
            if self?.udpRequestID == requestID { self?.udpRequestID = nil }
        }
    }
}

// MARK: - LocalClientSession

private final class LocalClientSession {
    let id = UUID()
    let connection: NWConnection
    var callsign: String?
    var isAuthenticated: Bool = false
    private var buffer = ""
    private var closed = false
    private var pendingBytes = 0
    private var commandWindowStart = ProcessInfo.processInfo.systemUptime
    private var commandsInWindow = 0

    var onDisconnect: ((UUID) -> Void)?
    var onCallsignSet: ((String) -> Void)?
    var onCommand: ((String, @escaping (String) -> Void) -> Void)?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendWelcome()
                self.receiveLoop()
            case .failed, .cancelled:
                self.close()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onDisconnect?(id)
    }

    func send(_ text: String) {
        guard !closed, let data = text.data(using: .utf8) else { return }
        guard pendingBytes + data.count <= 65536 else { close(); return }
        pendingBytes += data.count
        connection.send(content: data, completion: .contentProcessed({ [weak self] error in
            guard let self else { return }
            self.pendingBytes -= data.count
            if error != nil { self.close() }
        }))
    }

    private func sendWelcome() {
        let banner = """
        ======================================================================
        YAAM Local DX Cluster Server v1.0 (macOS)
        Bridging DX Spots to Local Loggers (WSJT-X / RUMlogNG / N1MM / MacLogger)
        ======================================================================
        Please enter your callsign: 
        """
        send(banner)
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, let chunk = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                self.consume(chunk)
            }
            if isComplete || error != nil {
                self.close()
            } else {
                self.receiveLoop()
            }
        }
    }

    private func consume(_ chunk: String) {
        guard !closed, buffer.utf8.count + chunk.utf8.count <= 8192 else { close(); return }
        buffer.append(chunk)
        buffer = buffer.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = buffer.components(separatedBy: "\n")
        guard lines.count > 1 else { return }
        buffer = lines.last ?? ""
        guard buffer.utf8.count <= 4096 else { close(); return }

        for rawLine in lines.dropLast() {
            guard !closed, rawLine.utf8.count <= 4096 else { close(); return }
            let uptime = ProcessInfo.processInfo.systemUptime
            if uptime - commandWindowStart >= 1 { commandWindowStart = uptime; commandsInWindow = 0 }
            commandsInWindow += 1
            guard commandsInWindow <= 20 else { close(); return }
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if !isAuthenticated {
                let call = LocalClusterWirePolicy.line(line.uppercased())
                guard call.count <= 20, call.range(of: #"^[A-Z0-9/]+$"#, options: .regularExpression) != nil else { close(); return }
                self.callsign = call
                self.isAuthenticated = true
                self.onCallsignSet?(call)
                send("""
                Hello \(call), welcome to YAAM Local DX Cluster.
                Filtered spots will stream automatically.
                Type HELP for available commands, BYE to exit.
                YAAM> 
                """)
            } else {
                if line.uppercased() == "QUIT" || line.uppercased() == "BYE" {
                    send("73! Disconnecting.\r\n")
                    close()
                    return
                }
                onCommand?(line) { [weak self] reply in
                    self?.send(reply)
                }
            }
        }
    }
}
