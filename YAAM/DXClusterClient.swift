//
//  DXClusterClient.swift
//  YAAM
//
//  Resilient High-Availability DX Cluster Client with Primary/Backup Failover,
//  LoTW Intelligence, Proximity Filtering, Sleep/Wake Recovery, and Display Freeze.
//

import AppKit
import Foundation
import Network
import Combine

public enum ClusterNodeRole: String, CaseIterable, Identifiable, Sendable {
    case primary = "Primary"
    case backup = "Backup"

    public var id: String { rawValue }
}

final class DXClusterClient: ObservableObject {
    @Published private(set) var state: DXClusterConnectionState = .disconnected
    @Published private(set) var spots: [DXSpot] = []
    @Published private(set) var lastMessage = "Ready to connect"
    @Published private(set) var connectedSince: Date?
    @Published private(set) var receivedSpotCount = 0

    // High-Availability & Failover
    @Published private(set) var activeNodeRole: ClusterNodeRole = .primary
    @Published var primaryHost: String = "dxcluster.co.uk"
    @Published var primaryPort: Int = 7373
    @Published var backupHost: String = "dxc.nc7j.com"
    @Published var backupPort: Int = 7373
    @Published var ssid: String = ""
    @Published var homeGrid: String = ""

    // Display Pause / Freeze
    @Published private(set) var isDisplayPaused: Bool = false
    @Published private(set) var pausedBufferCount: Int = 0

    // Interactive Terminal Console
    @Published private(set) var rawConsoleLines: [String] = []

    // Upstream Server-Side Filter Checking (Priority P1)
    @Published private(set) var upstreamFiltersDetected: Bool = false
    @Published private(set) var upstreamFilterDetails: String = ""
    @Published var isUpstreamFilterBannerDismissed: Bool = false
    private var isCheckingFilters = false
    private var hasBootstrappedSession = false

    // RBN Matrix (Priority P1)
    @Published var rbnSettings: RBNMatrixSettings = RBNMatrixSettings()

    // Dual-Node Aggregation
    @Published var isAggregationEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isAggregationEnabled, forKey: "clusterAggregationEnabled")
            if isAggregationEnabled && state.isConnected && secondaryConnection == nil {
                startSecondaryConnection()
            } else if !isAggregationEnabled && secondaryConnection != nil {
                stopSecondaryConnection()
            }
        }
    }
    @Published private(set) var secondaryState: DXClusterConnectionState = .disconnected
    private var secondaryConnection: NWConnection?
    private var secondaryConnectionID = UUID()
    private var secondaryReceiveBuffer = ""

    // Flap Protection (Priority P2)
    @Published private(set) var isFlapProtectionActive: Bool = false
    @Published private(set) var flapCooldownRemaining: Int = 0
    private var disconnectHistory: [Date] = []
    private let flapThreshold = 6
    private let flapWindowSeconds: TimeInterval = 60.0
    private let flapCooldownSeconds: Int = 120
    private var flapCooldownTimer: DispatchSourceTimer?

    private let queue = DispatchQueue(label: "app.yaam.dx-cluster", qos: .userInitiated)
    private var connection: NWConnection?
    private var reconnectWorkItem: DispatchWorkItem?
    private var keepaliveTimer: DispatchSourceTimer?
    private var primaryProbeTimer: DispatchSourceTimer?
    private var receiveBuffer = ""
    private var pendingSpots: [DXSpot] = []
    private var pausedBuffer: [DXSpot] = []
    private var flushWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0
    private var consecutiveFailures = 0
    private var userDisconnected = true
    private var currentHost = ""
    private var currentPort: UInt16 = 0
    private var baseCallsign = ""
    private var connectionID = UUID()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.isAggregationEnabled = UserDefaults.standard.bool(forKey: "clusterAggregationEnabled")
        if let data = UserDefaults.standard.data(forKey: "clusterRBNSettings"),
           let decoded = try? JSONDecoder().decode(RBNMatrixSettings.self, from: data) {
            self.rbnSettings = decoded
        }
        setupWakeNotification()
    }

    deinit {
        connection?.cancel()
        secondaryConnection?.cancel()
        keepaliveTimer?.cancel()
        primaryProbeTimer?.cancel()
        reconnectWorkItem?.cancel()
        flapCooldownTimer?.cancel()
    }

    // MARK: - Connection Management

    func connect(
        primaryHost: String,
        primaryPort: Int,
        backupHost: String = "dxc.nc7j.com",
        backupPort: Int = 7373,
        callsign: String,
        ssid: String = "",
        homeGrid: String = ""
    ) {
        self.primaryHost = primaryHost.trimmingCharacters(in: .whitespacesAndNewlines)
        self.primaryPort = primaryPort
        self.backupHost = backupHost.trimmingCharacters(in: .whitespacesAndNewlines)
        self.backupPort = backupPort
        self.baseCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.ssid = ssid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.homeGrid = homeGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !self.primaryHost.isEmpty, (1...65_535).contains(self.primaryPort), !self.baseCallsign.isEmpty else {
            state = .failed("Enter a valid cluster host, port, and station callsign.")
            lastMessage = "Cluster settings are incomplete"
            return
        }

        disconnect(userInitiated: false)
        activeNodeRole = .primary
        currentHost = self.primaryHost
        currentPort = UInt16(self.primaryPort)
        consecutiveFailures = 0
        reconnectAttempt = 0
        userDisconnected = false
        startConnection(isReconnect: false)
    }

    func connect(host rawHost: String, port rawPort: Int, callsign rawCallsign: String) {
        connect(
            primaryHost: rawHost,
            primaryPort: rawPort,
            backupHost: backupHost,
            backupPort: backupPort,
            callsign: rawCallsign,
            ssid: ssid,
            homeGrid: homeGrid
        )
    }

    /// Dynamically updates the reference home/rover grid and recomputes distance and beam headings for all active spots
    func updateHomeGrid(_ newGrid: String) {
        let clean = newGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean != homeGrid else { return }
        self.homeGrid = clean

        guard !clean.isEmpty, let homeBox = MaidenheadGridEngine.boundingBox(for: clean) else { return }
        let home = homeBox.center

        var updated = spots
        for i in 0..<updated.count {
            if !updated[i].grid.isEmpty {
                if let info = SpotterDistanceEngine.locationInfo(fromGrid: clean, toGrid: updated[i].grid) {
                    updated[i].spotterDistanceKm = info.distanceKm
                    updated[i].spotterBearingDeg = info.bearingDeg
                    updated[i].spotterCardinalDirection = info.cardinalDirection
                }
            }
            let ctyInfo = CTYDatabaseManager.shared.lookup(callsign: updated[i].callsign)
            if let lat = ctyInfo?.latitude, let lon = ctyInfo?.longitude {
                let target = GeoCoordinate(latitude: lat, longitude: lon)
                updated[i].beamHeadingDeg = GeodesicMath.initialBearing(from: home, to: target)
            }
        }
        DispatchQueue.main.async {
            self.spots = updated
        }
    }

    func disconnect(userInitiated: Bool = true) {
        self.userDisconnected = userInitiated
        connectionID = UUID()
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        primaryProbeTimer?.cancel()
        primaryProbeTimer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        receiveBuffer = ""
        stopSecondaryConnection()

        if userInitiated {
            disconnectHistory.removeAll()
            flapCooldownTimer?.cancel()
            flapCooldownTimer = nil
            isFlapProtectionActive = false
            flapCooldownRemaining = 0
            upstreamFiltersDetected = false
            upstreamFilterDetails = ""
            state = .disconnected
            connectedSince = nil
            lastMessage = "Disconnected"
            appendConsole(">>> Disconnected from cluster by user.")
        }
    }

    func clearSpots() {
        spots.removeAll(keepingCapacity: true)
        pausedBuffer.removeAll(keepingCapacity: true)
        pausedBufferCount = 0
        receivedSpotCount = 0
    }

    func clearConsole() {
        rawConsoleLines.removeAll()
    }

    // MARK: - Display Freeze / Pause

    func toggleDisplayPause() {
        if isDisplayPaused {
            resumeDisplay()
        } else {
            pauseDisplay()
        }
    }

    func pauseDisplay() {
        guard !isDisplayPaused else { return }
        isDisplayPaused = true
        pausedBuffer.removeAll(keepingCapacity: true)
        pausedBufferCount = 0
    }

    func resumeDisplay() {
        guard isDisplayPaused else { return }
        isDisplayPaused = false
        if !pausedBuffer.isEmpty {
            let buffer = pausedBuffer
            pausedBuffer.removeAll(keepingCapacity: true)
            pausedBufferCount = 0
            apply(buffer)
        }
    }

    // MARK: - Interactive Terminal Console & Raw Sending

    func sendCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendConsole("> \(trimmed)")
        send("\(trimmed)\r\n")
    }

    func sendSpot(callsign: String, frequencyKHz: Double, comment: String) {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCall.isEmpty, frequencyKHz > 0 else { return }
        let cmd = "DX \(String(format: "%.1f", frequencyKHz)) \(cleanCall) \(cleanComment)"
        sendCommand(cmd)
    }

    func setRBNEnabled(_ enabled: Bool) {
        if enabled {
            sendCommand("set/skimmer")
            sendCommand("set/dx/rbn")
        } else {
            sendCommand("unset/skimmer")
            sendCommand("unset/dx/rbn")
        }
    }

    // MARK: - Upstream Server-Side Filter Checker (Priority P1)

    func checkUpstreamFilters() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isCheckingFilters = true
            self.send("sh/filter\r\n")
            self.appendConsole(">>> Checking node for active server-side filters (sh/filter)...")
            self.queue.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                self?.isCheckingFilters = false
            }
        }
    }

    func clearUpstreamFilters() {
        queue.async { [weak self] in
            guard let self else { return }
            self.send("clear/spots 1\r\n")
            self.send("clear/spots all\r\n")
            self.send("clear/filter all\r\n")
            self.appendConsole(">>> Sent node filter reset: clear/spots all & clear/filter all")
            DispatchQueue.main.async {
                self.upstreamFiltersDetected = false
                self.isUpstreamFilterBannerDismissed = true
            }
            self.queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.checkUpstreamFilters()
            }
        }
    }

    func dismissUpstreamFilterBanner() {
        isUpstreamFilterBannerDismissed = true
    }

    // MARK: - RBN Skimmer Control Matrix (Priority P1)

    func toggleRBN(mode: String, enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            let cmd = enabled ? "set/rbn \(mode)" : "unset/rbn \(mode)"
            self.send("\(cmd)\r\n")
            self.appendConsole(">>> RBN Matrix: \(cmd)")
        }
    }

    func syncRBNSettings() {
        toggleRBN(mode: "cw", enabled: rbnSettings.cw)
        toggleRBN(mode: "rtty", enabled: rbnSettings.rtty)
        toggleRBN(mode: "ft8", enabled: rbnSettings.ft8)
        toggleRBN(mode: "ft4", enabled: rbnSettings.ft4)
        toggleRBN(mode: "psk", enabled: rbnSettings.psk)
        toggleRBN(mode: "beacon", enabled: rbnSettings.beacons)
    }

    func updateRBNSettings(_ newSettings: RBNMatrixSettings) {
        self.rbnSettings = newSettings
        if let encoded = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(encoded, forKey: "clusterRBNSettings")
        }
        syncRBNSettings()
    }

    // MARK: - Flap Protection (Priority P2)

    private func recordDisconnectAndCheckFlapping() -> Bool {
        let now = Date()
        disconnectHistory.append(now)
        disconnectHistory = disconnectHistory.filter { now.timeIntervalSince($0) <= flapWindowSeconds }

        if disconnectHistory.count >= flapThreshold {
            engageFlapProtection()
            return true
        }
        return false
    }

    private func engageFlapProtection() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        flapCooldownTimer?.cancel()

        DispatchQueue.main.async {
            self.isFlapProtectionActive = true
            self.flapCooldownRemaining = self.flapCooldownSeconds
            self.state = .failed("Flap Protection Active: Cooldown 120s")
            self.lastMessage = "Frequent disconnects (6 in 60s). Pausing reconnects to prevent cluster IP ban."
        }
        appendConsole("⚠️ FLAP PROTECTION ENGAGED: 6 disconnects in 60s. Auto-reconnect paused for \(flapCooldownSeconds)s to prevent cluster ban.")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                if self.flapCooldownRemaining > 1 {
                    self.flapCooldownRemaining -= 1
                } else {
                    self.flapCooldownRemaining = 0
                    self.isFlapProtectionActive = false
                    self.flapCooldownTimer?.cancel()
                    self.flapCooldownTimer = nil
                    self.disconnectHistory.removeAll()
                    self.appendConsole("🛡️ Flap Protection cooldown finished. Reconnecting cluster...")
                    self.startConnection(isReconnect: true)
                }
            }
        }
        timer.resume()
        flapCooldownTimer = timer
    }

    func overrideFlapProtection() {
        queue.async { [weak self] in
            guard let self else { return }
            self.flapCooldownTimer?.cancel()
            self.flapCooldownTimer = nil
            self.disconnectHistory.removeAll()
            DispatchQueue.main.async {
                self.isFlapProtectionActive = false
                self.flapCooldownRemaining = 0
                self.appendConsole(">>> Flap Protection manually overridden by operator. Connecting now...")
                self.startConnection(isReconnect: false)
            }
        }
    }

    // MARK: - Network Pipeline

    private func startConnection(isReconnect: Bool) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        hasBootstrappedSession = false
        isCheckingFilters = false

        let host = currentHost
        let port = currentPort
        let nodeRole = activeNodeRole

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            state = .failed("Invalid port: \(port)")
            return
        }

        let id = UUID()
        connectionID = id

        state = isReconnect ? .reconnecting(attempt: reconnectAttempt) : .connecting
        lastMessage = isReconnect ? "Reconnecting to \(host):\(port)..." : "Connecting to \(host):\(port)..."
        appendConsole(">>> Connecting to \(host):\(port) (\(nodeRole.rawValue))...")

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 30
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            self?.handleStateChange(state, connectionID: id)
        }

        conn.start(queue: queue)
    }

    private func handleStateChange(_ state: NWConnection.State, connectionID: UUID) {
        queue.async { [weak self] in
            guard let self, self.connectionID == connectionID else { return }
            self.handleStateChangeOnQueue(state, connectionID: connectionID)
        }
    }

    private func handleStateChangeOnQueue(_ state: NWConnection.State, connectionID: UUID) {
        switch state {
        case .ready:
            let now = Date()
            consecutiveFailures = 0
            reconnectAttempt = 0
            disconnectHistory.removeAll()

            DispatchQueue.main.async {
                guard self.connectionID == connectionID else { return }
                self.state = .connected
                self.connectedSince = now
                self.lastMessage = "Connected to \(self.currentHost) (\(self.activeNodeRole.rawValue))"
            }
            appendConsole("✅ Connected to \(currentHost):\(currentPort) (\(activeNodeRole.rawValue))")

            receiveNext(connectionID: connectionID)
            startKeepalive()

            if isAggregationEnabled {
                startSecondaryConnection()
            } else if activeNodeRole == .backup {
                startPrimaryProbeTimer()
            }
        case .failed(let error):
            consecutiveFailures += 1
            appendConsole(">>> Connection failed: \(error.localizedDescription) (Failures: \(consecutiveFailures))")
            scheduleReconnect(after: error, connectionID: connectionID)
        case .cancelled:
            if !userDisconnected {
                appendConsole(">>> Connection closed unexpectedly.")
                scheduleReconnect(after: nil, connectionID: connectionID)
            }
        default:
            break
        }
    }

    private func effectiveLoginCallsign() -> String {
        if !ssid.isEmpty {
            let cleanSSID = ssid.replacingOccurrences(of: "-", with: "")
            return "\(baseCallsign)-\(cleanSSID)"
        }
        return baseCallsign
    }

    private func scheduleReconnect(after error: Error?, connectionID: UUID) {
        guard self.connectionID == connectionID, !userDisconnected, reconnectWorkItem == nil else { return }
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        connection?.cancel()
        connection = nil

        // Flap Protection check (Priority P2): Prevent cluster IP bans from rapid reconnect cycling
        if recordDisconnectAndCheckFlapping() {
            return
        }

        // Check for Failover: If primary failed 3 times and backup is configured, switch to backup
        if activeNodeRole == .primary && consecutiveFailures >= 3 && !backupHost.isEmpty && backupHost != primaryHost {
            currentHost = backupHost
            currentPort = UInt16(backupPort)
            reconnectAttempt = 0
            appendConsole("⚠️ Primary cluster unavailable after 3 attempts. Failing over to Backup: \(backupHost):\(backupPort)...")
            DispatchQueue.main.async {
                self.activeNodeRole = .backup
                self.lastMessage = "Failing over to backup cluster \(self.backupHost)..."
            }
        }

        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), 25.0)

        DispatchQueue.main.async {
            guard self.connectionID == connectionID else { return }
            self.state = .reconnecting(attempt: self.reconnectAttempt)
            self.connectedSince = nil
            self.lastMessage = error.map { "\($0.localizedDescription). Retry in \(Int(delay))s" } ?? "Connection closed. Retry in \(Int(delay))s"
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectionID == connectionID, !self.userDisconnected else { return }
            self.reconnectWorkItem = nil
            DispatchQueue.main.async {
                self.startConnection(isReconnect: true)
            }
        }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startKeepalive() {
        keepaliveTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in self?.send("\r\n") }
        timer.resume()
        keepaliveTimer = timer
    }

    // MARK: - Primary Probe for Failback

    private func startPrimaryProbeTimer() {
        primaryProbeTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 300, repeating: 300, leeway: .seconds(10))
        timer.setEventHandler { [weak self] in
            self?.probePrimaryNode()
        }
        timer.resume()
        primaryProbeTimer = timer
    }

    private func probePrimaryNode() {
        guard activeNodeRole == .backup, !primaryHost.isEmpty, let port = NWEndpoint.Port(rawValue: UInt16(primaryPort)) else { return }
        appendConsole(">>> Probing primary node \(primaryHost):\(primaryPort) for availability...")

        let probeConn = NWConnection(host: NWEndpoint.Host(primaryHost), port: port, using: .tcp)
        probeConn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                probeConn.cancel()
                self.queue.async {
                    self.appendConsole("✅ Primary cluster \(self.primaryHost) is back online! Reverting from backup...")
                    DispatchQueue.main.async {
                        self.activeNodeRole = .primary
                        self.currentHost = self.primaryHost
                        self.currentPort = UInt16(self.primaryPort)
                        self.primaryProbeTimer?.cancel()
                        self.primaryProbeTimer = nil
                        self.disconnect(userInitiated: false)
                        self.userDisconnected = false
                        self.startConnection(isReconnect: false)
                    }
                }
            }
        }
        probeConn.start(queue: queue)
    }

    // MARK: - Sleep / Wake Handling

    private func setupWakeNotification() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleSystemWake() {
        guard !userDisconnected else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.appendConsole(">>> Mac woke from sleep. Waiting 3 seconds for network interface stabilization...")
            self.connection?.cancel()
            self.connection = nil

            self.queue.asyncAfter(deadline: .now() + 3.0) {
                guard !self.userDisconnected else { return }
                self.appendConsole(">>> Reconnecting cluster after system wake...")
                DispatchQueue.main.async {
                    self.startConnection(isReconnect: true)
                }
            }
        }
    }

    // MARK: - Data Ingestion & Enrichment

    private func receiveNext(connectionID: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                guard self.connectionID == connectionID else { return }
                if let data, !data.isEmpty {
                    self.consume(data)
                }
                if let error {
                    self.scheduleReconnect(after: error, connectionID: connectionID)
                } else if isComplete {
                    self.scheduleReconnect(after: nil, connectionID: connectionID)
                } else {
                    self.receiveNext(connectionID: connectionID)
                }
            }
        }
    }

    private func consume(_ data: Data) {
        let cleanData = removeTelnetNegotiation(from: data)
        guard let chunk = String(data: cleanData, encoding: .utf8) ?? String(data: cleanData, encoding: .isoLatin1) else { return }
        receiveBuffer.append(chunk)
        receiveBuffer = receiveBuffer
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = receiveBuffer.components(separatedBy: "\n")
        guard lines.count > 1 else { return }
        receiveBuffer = lines.last ?? ""

        for rawLine in lines.dropLast() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            appendConsole(line)

            if line.localizedCaseInsensitiveContains("login:") || line.localizedCaseInsensitiveContains("call:") {
                let effectiveCall = effectiveLoginCallsign()
                send("\(effectiveCall)\r\n")
            }

            // Session bootstrap: Check filters and sync RBN
            if !hasBootstrappedSession && (line.contains(">") || line.localizedCaseInsensitiveContains("hello") || line.localizedCaseInsensitiveContains("welcome")) {
                hasBootstrappedSession = true
                queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.checkUpstreamFilters()
                    self?.syncRBNSettings()
                }
            }

            // Upstream server-side filter inspection
            if isCheckingFilters {
                let lower = line.lowercased()
                if lower.contains("filter") && (lower.contains("accept") || lower.contains("reject") || lower.contains("spots")) {
                    DispatchQueue.main.async {
                        self.upstreamFiltersDetected = true
                        self.upstreamFilterDetails = line
                        self.isUpstreamFilterBannerDismissed = false
                    }
                } else if lower.contains("no filter") || lower.contains("not found") {
                    DispatchQueue.main.async {
                        self.upstreamFiltersDetected = false
                        self.upstreamFilterDetails = ""
                    }
                }
            }

            if var spot = DXSpotParser.parse(line: line) {
                // Enrich with LoTW User Activity Database
                spot.isLoTWActive = LoTWActivityDatabase.shared.isUserActive(spot.callsign)
                spot.lotwLastUpload = LoTWActivityDatabase.shared.lastUploadDate(for: spot.callsign)

                // Enrich with Spotter Distance & Bearing from Home Grid (spotter → home)
                if !homeGrid.isEmpty, !spot.grid.isEmpty {
                    if let info = SpotterDistanceEngine.locationInfo(fromGrid: homeGrid, toGrid: spot.grid) {
                        spot.spotterDistanceKm = info.distanceKm
                        spot.spotterBearingDeg = info.bearingDeg
                        spot.spotterCardinalDirection = info.cardinalDirection
                    }
                }

                // P0-C: Enrich with DXCC entity (flag + beam heading from home to spotted station)
                let dxcc = DXCCDatabase.resolve(callsign: spot.callsign)
                spot.dxccEntityName = dxcc.entityName
                spot.flagEmoji = dxcc.flagEmoji
                // Beam heading: from user home grid to the spotted station's entity coordinates
                if !homeGrid.isEmpty {
                    let ctyInfo = CTYDatabaseManager.shared.lookup(callsign: spot.callsign)
                    if let lat = ctyInfo?.latitude, let lon = ctyInfo?.longitude {
                        if let homeBox = MaidenheadGridEngine.boundingBox(for: homeGrid) {
                            let home = homeBox.center
                            let target = GeoCoordinate(latitude: lat, longitude: lon)
                            spot.beamHeadingDeg = GeodesicMath.initialBearing(from: home, to: target)
                        }
                    }
                }

                // Broadcast to Local Cluster Server (P0: Telnet & UDP redistribution)
                LocalClusterServer.shared.broadcastSpot(spot)

                enqueue(spot)
            } else if line.localizedCaseInsensitiveContains("welcome") || line.localizedCaseInsensitiveContains("connected") {
                DispatchQueue.main.async { self.lastMessage = line }
            }
        }
    }

    // MARK: - Dual-Node Aggregation Pipeline

    func startSecondaryConnection() {
        guard isAggregationEnabled, !backupHost.isEmpty, (1...65_535).contains(backupPort) else { return }
        stopSecondaryConnection()

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(backupPort)) else { return }
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 30
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: NWEndpoint.Host(backupHost), port: nwPort, using: params)
        self.secondaryConnection = conn

        let id = UUID()
        secondaryConnectionID = id

        conn.stateUpdateHandler = { [weak self] state in
            self?.queue.async {
                guard let self, self.secondaryConnectionID == id else { return }
                switch state {
                case .ready:
                    DispatchQueue.main.async {
                        self.secondaryState = .connected
                        self.appendConsole("✅ Connected to Secondary Aggregation node: \(self.backupHost):\(self.backupPort)")
                    }
                    self.receiveNextSecondary(connectionID: id)
                case .failed(let err):
                    DispatchQueue.main.async {
                        self.secondaryState = .failed(err.localizedDescription)
                        self.appendConsole("⚠️ Secondary node error: \(err.localizedDescription)")
                    }
                case .cancelled:
                    DispatchQueue.main.async {
                        self.secondaryState = .disconnected
                    }
                default:
                    break
                }
            }
        }
        conn.start(queue: queue)
    }

    func stopSecondaryConnection() {
        secondaryConnectionID = UUID()
        secondaryConnection?.stateUpdateHandler = nil
        secondaryConnection?.cancel()
        secondaryConnection = nil
        secondaryReceiveBuffer = ""
        DispatchQueue.main.async {
            self.secondaryState = .disconnected
        }
    }

    private func receiveNextSecondary(connectionID: UUID) {
        secondaryConnection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, isComplete, error in
            guard let self, self.secondaryConnectionID == connectionID else { return }
            self.queue.async {
                if let data, !data.isEmpty {
                    self.consumeSecondary(data)
                }
                if isComplete || error != nil {
                    self.stopSecondaryConnection()
                } else {
                    self.receiveNextSecondary(connectionID: connectionID)
                }
            }
        }
    }

    private func consumeSecondary(_ data: Data) {
        let cleanData = removeTelnetNegotiation(from: data)
        guard let chunk = String(data: cleanData, encoding: .utf8) ?? String(data: cleanData, encoding: .isoLatin1) else { return }
        secondaryReceiveBuffer.append(chunk)
        secondaryReceiveBuffer = secondaryReceiveBuffer
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = secondaryReceiveBuffer.components(separatedBy: "\n")
        guard lines.count > 1 else { return }
        secondaryReceiveBuffer = lines.last ?? ""

        for rawLine in lines.dropLast() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.localizedCaseInsensitiveContains("login:") || line.localizedCaseInsensitiveContains("call:") {
                let effectiveCall = effectiveLoginCallsign() + "-2"
                if let callData = "\(effectiveCall)\r\n".data(using: .utf8) {
                    secondaryConnection?.send(content: callData, completion: .idempotent)
                }
            }

            if var spot = DXSpotParser.parse(line: line) {
                spot.isLoTWActive = LoTWActivityDatabase.shared.isUserActive(spot.callsign)
                spot.lotwLastUpload = LoTWActivityDatabase.shared.lastUploadDate(for: spot.callsign)

                if !homeGrid.isEmpty, !spot.grid.isEmpty {
                    if let info = SpotterDistanceEngine.locationInfo(fromGrid: homeGrid, toGrid: spot.grid) {
                        spot.spotterDistanceKm = info.distanceKm
                        spot.spotterBearingDeg = info.bearingDeg
                        spot.spotterCardinalDirection = info.cardinalDirection
                    }
                }

                let dxcc = DXCCDatabase.resolve(callsign: spot.callsign)
                spot.dxccEntityName = dxcc.entityName
                spot.flagEmoji = dxcc.flagEmoji

                if !homeGrid.isEmpty {
                    let ctyInfo = CTYDatabaseManager.shared.lookup(callsign: spot.callsign)
                    if let lat = ctyInfo?.latitude, let lon = ctyInfo?.longitude {
                        if let homeBox = MaidenheadGridEngine.boundingBox(for: homeGrid) {
                            let home = homeBox.center
                            let target = GeoCoordinate(latitude: lat, longitude: lon)
                            spot.beamHeadingDeg = GeodesicMath.initialBearing(from: home, to: target)
                        }
                    }
                }

                LocalClusterServer.shared.broadcastSpot(spot)
                enqueue(spot)
            }
        }
    }

    private func enqueue(_ spot: DXSpot) {
        // NOTE: called from background queue (self.queue) – hop to main for all @Published mutations
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isDisplayPaused {
                self.pausedBuffer.insert(spot, at: 0)
                self.pausedBufferCount = self.pausedBuffer.count
                self.receivedSpotCount += 1
                return
            }
            self.pendingSpots.append(spot)
            guard self.flushWorkItem == nil else { return }
            let batch = self.pendingSpots
            self.pendingSpots.removeAll(keepingCapacity: true)
            self.flushWorkItem = nil
            self.apply(batch)
        }
    }

    private func apply(_ batch: [DXSpot]) {
        guard !batch.isEmpty else { return }
        var updated = spots
        var indexByID = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($0.element.id, $0.offset) })

        for spot in batch {
            receivedSpotCount += 1
            SignalFootprintEngine.shared.ingestRBNSpot(
                callsign: spot.callsign,
                spotter: spot.spotter,
                freqKHz: spot.frequencyKHz,
                comment: spot.comment,
                time: spot.spottedAt
            )
            // P0-A: Smart deduplication within ±2.0 kHz window on the same band & callsign
            let matchIndex = indexByID[spot.id] ?? updated.firstIndex(where: {
                $0.callsign == spot.callsign && $0.band == spot.band && abs($0.frequencyKHz - spot.frequencyKHz) <= 2.0
            })

            if let index = matchIndex, updated.indices.contains(index) {
                updated[index].lastSeenAt = spot.lastSeenAt
                updated[index].frequencyKHz = spot.frequencyKHz
                updated[index].comment = spot.comment.isEmpty ? updated[index].comment : spot.comment
                updated[index].grid = spot.grid.isEmpty ? updated[index].grid : spot.grid
                updated[index].spotter = spot.spotter
                updated[index].reportCount += 1
                if let snr = spot.snrDB {
                    updated[index].snrDB = snr
                }
                if let beam = spot.beamHeadingDeg {
                    updated[index].beamHeadingDeg = beam
                }
                if !spot.flagEmoji.isEmpty {
                    updated[index].flagEmoji = spot.flagEmoji
                    updated[index].dxccEntityName = spot.dxccEntityName
                }
                if spot.lotwLastUpload != nil {
                    updated[index].lotwLastUpload = spot.lotwLastUpload
                    updated[index].isLoTWActive = spot.isLoTWActive
                }
                if spot.spotterDistanceKm != nil {
                    updated[index].spotterDistanceKm = spot.spotterDistanceKm
                    updated[index].spotterBearingDeg = spot.spotterBearingDeg
                    updated[index].spotterCardinalDirection = spot.spotterCardinalDirection
                }
            } else {
                updated.insert(spot, at: 0)
                indexByID = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($0.element.id, $0.offset) })
            }
        }

        updated.sort { $0.lastSeenAt > $1.lastSeenAt }
        spots = Array(updated.prefix(800))
        lastMessage = "\(receivedSpotCount) spots received"

        // P1: Automatically feed live spots into graphical BandmapEngine
        for spot in batch {
            BandmapEngine.shared.addSpot(
                callsign: spot.callsign,
                frequencyKHz: spot.frequencyKHz,
                band: spot.band,
                mode: spot.submode.isEmpty ? spot.mode : spot.submode,
                comment: spot.comment,
                source: "DX Cluster",
                snr: spot.snrDB
            )
        }

        // P2: Persist into multi-day SQLite SpotArchiveDatabase
        SpotArchiveDatabase.shared.archiveSpots(batch)
    }

    private func send(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            self?.queue.async {
                guard let self else { return }
                self.scheduleReconnect(after: error, connectionID: self.connectionID)
            }
        })
    }

    private func appendConsole(_ line: String) {
        DispatchQueue.main.async {
            self.rawConsoleLines.append(line)
            if self.rawConsoleLines.count > 600 {
                self.rawConsoleLines.removeFirst(100)
            }
        }
    }

    private func removeTelnetNegotiation(from data: Data) -> Data {
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 255 {
                if index + 1 < bytes.count, bytes[index + 1] == 250 {
                    index += 2
                    while index + 1 < bytes.count, !(bytes[index] == 255 && bytes[index + 1] == 240) {
                        index += 1
                    }
                    index = min(index + 2, bytes.count)
                } else {
                    index = min(index + 3, bytes.count)
                }
            } else {
                output.append(bytes[index])
                index += 1
            }
        }
        return Data(output)
    }
}
