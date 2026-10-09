//
//  HamTrackerEngine.swift
//  YAAM
//
//  Real-Time Callsign Activity Tracker & Digital Monitor
//  (Mirroring and extending ham_tracker.py for native macOS YAAM)
//
//  Subscribes directly to PSKReporter's live MQTT 3.1.1 feed (mqtt.pskreporter.info:1883),
//  performs instant REST catch-up for past sliding windows, queries DX Cluster Telnet,
//  and computes real-time FT8 15-second transmission cycle telemetry and radiation patterns.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import Network
import SwiftUI

// MARK: - Connection & Activity States

public enum HamTrackerConnectionStatus: Equatable, Sendable {
    case idle
    case connecting(String)
    case streaming(reportsCount: Int)
    case catchingUp(String)
    case reconnecting(attempt: Int)
    case paused
    case error(String)

    public var displayText: String {
        switch self {
        case .idle:
            return "Ready to Monitor"
        case .connecting(let host):
            return "Connecting to \(host)..."
        case .streaming(let count):
            return "Live MQTT Stream Active (\(count) spots)"
        case .catchingUp(let source):
            return "Fetching \(source) telemetry..."
        case .reconnecting(let attempt):
            return "Reconnecting (Attempt \(attempt))..."
        case .paused:
            return "Monitoring Paused"
        case .error(let msg):
            return "Connection Error: \(msg)"
        }
    }

    public var isLive: Bool {
        if case .streaming = self { return true }
        return false
    }

    public var indicatorColor: Color {
        switch self {
        case .idle: return .secondary
        case .connecting, .reconnecting, .catchingUp: return .orange
        case .streaming: return .green
        case .paused: return .yellow
        case .error: return .red
        }
    }
}

// MARK: - Time Window Option

public enum HamTrackerTimeWindow: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600
    case twoHours = 7200

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .fifteenMinutes: return "15 Minutes"
        case .thirtyMinutes: return "30 Minutes"
        case .oneHour: return "1 Hour"
        case .twoHours: return "2 Hours"
        }
    }

    public var shortLabel: String {
        switch self {
        case .fifteenMinutes: return "15m"
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        }
    }
}

// MARK: - Spot Model

public struct HamTrackSpot: Identifiable, Sendable, Hashable {
    public let id: String
    public let timestamp: Date
    public let senderCall: String
    public let senderGrid: String
    public let receiverCall: String
    public let receiverGrid: String
    public let receiverCountry: String
    public let receiverFlag: String
    public let frequencyHz: Int
    public let band: String
    public let mode: String
    public let snr: Int
    public let cycleSec: Int
    public let cycleType: String
    public let distanceKm: Double?
    public let bearingDeg: Double?
    public let bearingCompass: String?
    public let isRealtimeMQTT: Bool

    public var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000.0
    }

    public var isRecentTransmit: Bool {
        abs(Date().timeIntervalSince(timestamp)) <= 30.0
    }

    public var snrBadgeColor: Color {
        if snr >= 0 {
            return .green
        } else if snr >= -10 {
            return .cyan
        } else if snr >= -18 {
            return .orange
        } else {
            return .purple
        }
    }
}

// MARK: - Cluster Spot Model

public struct HamTrackClusterSpot: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let rawText: String
    public let spotterCall: String
    public let spottedCall: String
    public let frequencyKHz: Double
    public let comment: String
    public let timeString: String
    public let timestamp: Date
}

// MARK: - Cycle Slot Parity & Operational Activity State

public enum CycleSlotParity: String, Sendable, Equatable {
    case even = "EVEN (:00 / :30)"
    case odd = "ODD (:15 / :45)"

    public var shortLabel: String {
        switch self {
        case .even: return "EVEN"
        case .odd: return "ODD"
        }
    }
}

public enum StationActivityState: Equatable, Sendable {
    case idle(secondsAgo: Int?)
    case transmittingCQ(band: String, freqMHz: Double, slotRemaining: Int)
    case transmittingToPartner(partnerCall: String, band: String, freqMHz: Double, round: Int, slotRemaining: Int)
    case listeningForPartner(partnerCall: String, band: String, freqMHz: Double, decodeIn: Int)
    case listeningForCallers(band: String, freqMHz: Double, decodeIn: Int)
    case qrt(lastSeenSecondsAgo: Int)

    public var isTransmitting: Bool {
        switch self {
        case .transmittingCQ, .transmittingToPartner: return true
        default: return false
        }
    }

    public var isListening: Bool {
        switch self {
        case .listeningForPartner, .listeningForCallers: return true
        default: return false
        }
    }

    public var statusTitle: String {
        switch self {
        case .transmittingCQ:
            return "TRANSMITTING (CQ)"
        case .transmittingToPartner(let p, _, _, let round, _):
            return "TRANSMITTING ➔ \(p) [Cycle \(round)]"
        case .listeningForPartner(let p, _, _, _):
            return "LISTENING ➔ \(p)"
        case .listeningForCallers:
            return "LISTENING FOR CALLERS"
        case .idle:
            return "STANDBY"
        case .qrt:
            return "STATION IDLE"
        }
    }

    public var statusDescription: String {
        switch self {
        case .transmittingCQ(let band, let freq, let rem):
            return "\(band) • \(String(format: "%.4f", freq)) MHz • Calling CQ (\(rem)s remaining)"
        case .transmittingToPartner(let p, let band, let freq, _, let rem):
            return "\(band) • \(String(format: "%.4f", freq)) MHz • In QSO with \(p) (\(rem)s remaining)"
        case .listeningForPartner(let p, let band, _, let rem):
            return "\(band) • Awaiting reply from \(p) • Decode in \(rem)s"
        case .listeningForCallers(let band, let freq, let rem):
            return "\(band) • \(String(format: "%.4f", freq)) MHz • Waiting for CQ response • Decode in \(rem)s"
        case .idle(let ago):
            if let ago {
                return "Last heard \(ago)s ago • Monitoring slot"
            }
            return "Awaiting first digital decode..."
        case .qrt(let ago):
            return "No signals heard for \(ago)s (Station QRT or in RX)"
        }
    }

    public var badgeColor: Color {
        if isTransmitting { return .red }
        if isListening { return .blue }
        return .secondary
    }
}

// MARK: - Cycle Status & Timing

public struct HamTrackCycleStatus: Sendable {
    public var currentUTCSecond: Int = 0
    public var slotSecondsRemaining: Int = 15
    public var progress: Double = 0.0
    public var currentSlotParity: CycleSlotParity = .even
    public var currentSlotLabel: String = "EVEN (:00 / :30)"
    public var targetCadenceParity: CycleSlotParity? = nil
    public var detectedCadence: String = "Analyzing..."
    public var evenCount: Int = 0
    public var oddCount: Int = 0
    public var isTargetTransmittingNow: Bool = false
    public var isTargetListeningNow: Bool = false
    public var activityState: StationActivityState = .idle(secondsAgo: nil)
    public var lastSeenSecondsAgo: Int? = nil

    public var recommendedCallCycle: String {
        if let targetCadenceParity {
            switch targetCadenceParity {
            case .even: return "Call on ODD (:15 / :45)"
            case .odd: return "Call on EVEN (:00 / :30)"
            }
        }
        if evenCount > oddCount * 2 {
            return "Call on ODD (:15 / :45)"
        } else if oddCount > evenCount * 2 {
            return "Call on EVEN (:00 / :30)"
        } else {
            return "Adaptive / Mixed"
        }
    }
}

// MARK: - Completed Session QSO Model

public struct HamTrackCompletedQSO: Identifiable, Sendable, Hashable {
    public var id: String { "\(callsign)-\(Int(completedTimestamp.timeIntervalSince1970))" }
    public let callsign: String
    public let country: String
    public let flag: String
    public let grid: String
    public let frequencyMHz: Double
    public let band: String
    public let mode: String
    public let totalCycles: Int
    public let completedTimestamp: Date
    public let distanceKm: Double?
    public let bearingDeg: Double?

    public var timeAgoDescription: String {
        let diff = Int(Date().timeIntervalSince(completedTimestamp))
        if diff < 60 { return "\(diff)s ago" }
        let mins = diff / 60
        return "\(mins)m ago"
    }
}

// MARK: - Aggregate Statistics

public struct HamTrackStatistics: Sendable {
    public var totalSpots: Int = 0
    public var liveMQTTSpots: Int = 0
    public var uniqueSpottersCount: Int = 0
    public var averageSNR: Double = 0.0
    public var peakSNR: Int = -99
    public var peakSpotter: String = ""
    public var weakestSNR: Int = 99
    public var weakestSpotter: String = ""
    public var furthestDistanceKm: Double = 0.0
    public var furthestSpotter: String = ""
    public var furthestCountry: String = ""
    public var furthestFlag: String = ""
    public var activeBands: [String: Int] = [:]
    public var activeModes: [String: Int] = [:]
    public var continents: [String] = []
    public var targetTransmitterGrid: String = ""
    public var targetCountry: String = ""
    public var targetFlag: String = ""
    public var primaryFrequencyMHz: Double = 0.0
    public var primaryBand: String = ""
    public var primaryMode: String = ""
}

// MARK: - Active QSO Partner Candidate Model

public struct HamTrackPartnerCandidate: Identifiable, Sendable, Hashable {
    public var id: String { callsign }
    public let callsign: String
    public let country: String
    public let flag: String
    public let grid: String
    public var matchedFrequencyHz: Int
    public var frequencyOffsetHz: Int // candidate freq - target freq
    public var matchedCyclesCount: Int
    public var lastMatchedTimestamp: Date
    public var lastCycleSec: Int
    public var cycleParity: String
    public let distanceKmFromTarget: Double?
    public let bearingDegFromTarget: Double?
    public let distanceKmFromMe: Double?
    public var confidencePercentage: Int

    public var frequencyMHz: Double {
        Double(matchedFrequencyHz) / 1_000_000.0
    }

    public var confidenceBadgeColor: Color {
        if confidencePercentage >= 90 { return .green }
        if confidencePercentage >= 75 { return .cyan }
        return .orange
    }
}

// Internal Target Transmission Record
internal struct TargetTxRecord: Sendable {
    let frequencyHz: Int
    let timestamp: Date
    let isEven: Bool
    let grid: String
    let band: String
    let mode: String
}

// MARK: - Engine Class

@MainActor
public final class HamTrackerEngine: ObservableObject {
    public static let shared = HamTrackerEngine()

    // Configuration & Input
    @Published public var targetCallsign: String = "" {
        didSet {
            let clean = targetCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if clean != targetCallsign {
                targetCallsign = clean
            }
        }
    }
    @Published public var selectedTimeWindow: HamTrackerTimeWindow = .thirtyMinutes
    @Published public var audioAlertsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(audioAlertsEnabled, forKey: "hamTracker.audioAlerts") }
    }
    @Published public var includeClusterHistory: Bool = true {
        didSet { UserDefaults.standard.set(includeClusterHistory, forKey: "hamTracker.includeCluster") }
    }
    @Published public var monitorBidirectional: Bool = false // Also subscribe to spots where target is receiver
    @Published public var partnerDetectionEnabled: Bool = true {
        didSet { UserDefaults.standard.set(partnerDetectionEnabled, forKey: "hamTracker.partnerDetection") }
    }

    @Published public var homeCoordinate: GeoCoordinate = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)

    // Real-Time Published States
    @Published public private(set) var status: HamTrackerConnectionStatus = .idle
    @Published public private(set) var spots: [HamTrackSpot] = []
    @Published public private(set) var clusterSpots: [HamTrackClusterSpot] = []
    @Published public private(set) var cycleStatus = HamTrackCycleStatus()
    @Published public private(set) var statistics = HamTrackStatistics()
    @Published public private(set) var activePartner: HamTrackPartnerCandidate?
    @Published public private(set) var partnerCandidates: [HamTrackPartnerCandidate] = []
    @Published public private(set) var recentCompletedQSOs: [HamTrackCompletedQSO] = []
    @Published public private(set) var partnerScanningBand: String = ""
    @Published public private(set) var isTransmittingFlash: Bool = false
    @Published public private(set) var recentSearches: [String] = []
    @Published public private(set) var cliTerminalLog: String = ""
    @Published public private(set) var isRunningCLI: Bool = false

    // Private Networking & Tasks
    private var mqttConnection: NWConnection?
    private var clusterConnection: NWConnection?
    private var pingTimer: DispatchSourceTimer?
    private var cycleTicker: DispatchSourceTimer?
    private var flashResetTask: Task<Void, Never>?
    private let networkQueue = DispatchQueue(label: "app.yaam.ham-tracker.network", qos: .userInitiated)
    private var mqttReceiveBuffer = Data()
    private var clusterReceiveBuffer = ""
    private var activeSessionCallsign: String = ""
    private var reconnectAttempts = 0
    private var shouldKeepRunning = false
    private var recentTargetTxRecords: [TargetTxRecord] = []
    private var subscribedPartnerBands: Set<String> = []
    private var lastAudioAlertAt: Date?

    // Deduplication Set
    private var seenSpotKeys: Set<String> = []

    private init() {
        let quietDefaultsKey = "hamTracker.quietDefaultsV2"
        if UserDefaults.standard.bool(forKey: quietDefaultsKey) {
            self.audioAlertsEnabled = UserDefaults.standard.object(forKey: "hamTracker.audioAlerts") as? Bool ?? false
        } else {
            self.audioAlertsEnabled = false
            UserDefaults.standard.set(true, forKey: quietDefaultsKey)
        }
        self.includeClusterHistory = UserDefaults.standard.object(forKey: "hamTracker.includeCluster") as? Bool ?? true
        self.partnerDetectionEnabled = UserDefaults.standard.object(forKey: "hamTracker.partnerDetection") as? Bool ?? true
        loadRecentSearches()
        startCycleTicker()
    }

    deinit {
        pingTimer?.cancel()
        cycleTicker?.cancel()
        mqttConnection?.cancel()
        clusterConnection?.cancel()
    }

    // MARK: - Public Control API

    public func setTarget(_ callsign: String) {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        targetCallsign = clean
        saveRecentSearch(clean)
    }

    public func startMonitoring(callsign: String? = nil) {
        if let callsign {
            setTarget(callsign)
        }
        let activeCall = targetCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !activeCall.isEmpty else {
            status = .error("Please enter a callsign to track.")
            return
        }

        shouldKeepRunning = true
        activeSessionCallsign = activeCall
        saveRecentSearch(activeCall)

        // Clear existing session spots
        spots.removeAll()
        clusterSpots.removeAll()
        seenSpotKeys.removeAll()
        statistics = HamTrackStatistics()
        activePartner = nil
        partnerCandidates.removeAll()
        recentCompletedQSOs.removeAll()
        recentTargetTxRecords.removeAll()
        subscribedPartnerBands.removeAll()
        partnerScanningBand = ""
        updateTargetMetadata(activeCall)

        status = .connecting("mqtt.pskreporter.info")

        // 1. Kick off instant PSKReporter REST catch-up for past window
        fetchHistoricalCatchup(for: activeCall, secondsAgo: selectedTimeWindow.rawValue)

        // 2. Connect to DX Cluster if enabled
        if includeClusterHistory {
            queryClusterHistory(for: activeCall)
        }

        // 3. Connect live MQTT socket
        connectMQTT(callsign: activeCall)
    }

    public func stopMonitoring() {
        shouldKeepRunning = false
        disconnectMQTT()
        disconnectCluster()
        status = .idle
        isTransmittingFlash = false
    }

    public func refreshClusterSpots() {
        let activeCall = targetCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !activeCall.isEmpty else { return }
        queryClusterHistory(for: activeCall)
    }

    public func clearSession() {
        spots.removeAll()
        clusterSpots.removeAll()
        seenSpotKeys.removeAll()
        statistics = HamTrackStatistics()
        activePartner = nil
        partnerCandidates.removeAll()
        recentCompletedQSOs.removeAll()
        recentTargetTxRecords.removeAll()
        subscribedPartnerBands.removeAll()
        partnerScanningBand = ""
        updateTargetMetadata(targetCallsign)
    }

    public func switchTrackerToPartner() {
        guard let partner = activePartner else { return }
        switchTracker(to: partner.callsign)
    }

    public func switchTracker(to callsign: String) {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        setTarget(clean)
        startMonitoring(callsign: clean)
    }

    // MARK: - Target Station DXCC Metadata

    private func updateTargetMetadata(_ callsign: String) {
        guard !callsign.isEmpty else { return }
        let dxcc = DXCCDatabase.resolve(callsign: callsign)
        statistics.targetCountry = dxcc.entityName
        statistics.targetFlag = dxcc.flagEmoji
    }

    // MARK: - MQTT 3.1.1 Implementation (Over NWConnection)

    private func connectMQTT(callsign: String) {
        disconnectMQTT()

        status = .connecting("mqtt.pskreporter.info:1883")
        let host = NWEndpoint.Host("mqtt.pskreporter.info")
        let port = NWEndpoint.Port(rawValue: 1883) ?? .init(integerLiteral: 1883)
        let params = NWParameters.tcp
        params.preferNoProxies = true

        let connection = NWConnection(host: host, port: port, using: params)
        self.mqttConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.handleMQTTStateChange(state, callsign: callsign)
            }
        }

        connection.start(queue: networkQueue)
    }

    private func handleMQTTStateChange(_ state: NWConnection.State, callsign: String) {
        switch state {
        case .ready:
            reconnectAttempts = 0
            sendMQTTConnectPacket()
            startMQTTPingTimer()
            receiveNextMQTTData()
        case .waiting(let error):
            status = .error("Waiting: \(error.localizedDescription)")
            scheduleReconnect(callsign: callsign)
        case .failed(let error):
            status = .error("MQTT Failed: \(error.localizedDescription)")
            scheduleReconnect(callsign: callsign)
        case .cancelled:
            if shouldKeepRunning {
                status = .idle
            }
        @unknown default:
            break
        }
    }

    private func scheduleReconnect(callsign: String) {
        guard shouldKeepRunning else { return }
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0)
        status = .reconnecting(attempt: reconnectAttempts)

        networkQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.shouldKeepRunning else { return }
            Task { @MainActor in
                self.connectMQTT(callsign: callsign)
            }
        }
    }

    private func disconnectMQTT() {
        stopMQTTPingTimer()
        mqttConnection?.cancel()
        mqttConnection = nil
        mqttReceiveBuffer.removeAll()
    }

    // Packet Builders (MQTT 3.1.1)
    private func sendMQTTConnectPacket() {
        guard let connection = mqttConnection else { return }
        let clientID = "yaam-trk-\(Int(Date().timeIntervalSince1970))"

        var variableHeader = Data()
        variableHeader.append(encodeMQTTString("MQTT")) // Protocol Name
        variableHeader.append(0x04)                     // Version 3.1.1
        variableHeader.append(0x02)                     // Clean Session flag
        variableHeader.append(contentsOf: [0x00, 0x3C]) // Keep Alive 60 seconds

        var payload = Data()
        payload.append(encodeMQTTString(clientID))

        let remainingLen = variableHeader.count + payload.count
        var packet = Data([0x10]) // CONNECT
        packet.append(encodeRemainingLength(remainingLen))
        packet.append(variableHeader)
        packet.append(payload)

        connection.send(content: packet, completion: .contentProcessed({ [weak self] error in
            let errString = error?.localizedDescription
            Task { @MainActor [weak self] in
                if let errString {
                    self?.status = .error("Connect send error: \(errString)")
                }
            }
        }))
    }

    private func sendMQTTSubscribe(topic: String) {
        guard let connection = mqttConnection else { return }
        let packetID: UInt16 = 1

        var variableHeader = Data()
        variableHeader.append(contentsOf: [UInt8(packetID >> 8), UInt8(packetID & 0xFF)])

        var payload = Data()
        payload.append(encodeMQTTString(topic))
        payload.append(0x00) // Requested QoS 0

        let remainingLen = variableHeader.count + payload.count
        var packet = Data([0x82]) // SUBSCRIBE (QoS 1 required for header)
        packet.append(encodeRemainingLength(remainingLen))
        packet.append(variableHeader)
        packet.append(payload)

        connection.send(content: packet, completion: .contentProcessed({ [weak self] error in
            let errString = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errString {
                    self.status = .error("Subscribe send error: \(errString)")
                } else {
                    self.status = .streaming(reportsCount: self.spots.count)
                }
            }
        }))
    }

    private func sendMQTTPing() {
        guard let connection = mqttConnection else { return }
        let pingPacket = Data([0xC0, 0x00]) // PINGREQ
        connection.send(content: pingPacket, completion: .contentProcessed({ _ in }))
    }

    private func startMQTTPingTimer() {
        stopMQTTPingTimer()
        let timer = DispatchSource.makeTimerSource(queue: networkQueue)
        timer.schedule(deadline: .now() + 30.0, repeating: 30.0)
        timer.setEventHandler { [weak self] in
            self?.sendMQTTPing()
        }
        timer.resume()
        self.pingTimer = timer
    }

    private func stopMQTTPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    // MQTT Streaming Receiver
    private func receiveNextMQTTData() {
        guard let connection = mqttConnection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.processIncomingMQTTBytes(data)
            }
            if isComplete {
                Task { @MainActor in
                    if self.shouldKeepRunning {
                        self.scheduleReconnect(callsign: self.activeSessionCallsign)
                    }
                }
                return
            }
            if let error {
                Task { @MainActor in
                    self.status = .error("MQTT Recv: \(error.localizedDescription)")
                    if self.shouldKeepRunning {
                        self.scheduleReconnect(callsign: self.activeSessionCallsign)
                    }
                }
                return
            }
            self.receiveNextMQTTData()
        }
    }

    private func processIncomingMQTTBytes(_ data: Data) {
        mqttReceiveBuffer.append(data)

        while mqttReceiveBuffer.count >= 2 {
            let firstByte = mqttReceiveBuffer[0]
            let packetType = firstByte >> 4

            // Decode Remaining Length
            var offset = 1
            guard let remLen = decodeRemainingLength(from: mqttReceiveBuffer, offset: &offset) else {
                break // Wait for more bytes
            }

            let totalPacketLen = offset + remLen
            guard mqttReceiveBuffer.count >= totalPacketLen else {
                break // Incomplete packet, wait for more data
            }

            // Extract single packet
            let packetBody = mqttReceiveBuffer.subdata(in: offset..<totalPacketLen)
            mqttReceiveBuffer.removeSubrange(0..<totalPacketLen)

            // Handle packet
            handleMQTTPacket(type: packetType, body: packetBody)
        }
    }

    private func handleMQTTPacket(type: UInt8, body: Data) {
        switch type {
        case 2: // CONNACK
            if body.count >= 2 && body[1] == 0 {
                Task { @MainActor in
                    // Topic schema matching ham_tracker.py:
                    // pskr/filter/v2/{band}/{mode}/{tx_call}/{rx_call}/...
                    let topic = "pskr/filter/v2/+/+/\(self.activeSessionCallsign)/#"
                    self.sendMQTTSubscribe(topic: topic)

                    if self.monitorBidirectional {
                        let rxTopic = "pskr/filter/v2/+/+/+/+/+/\(self.activeSessionCallsign)/#"
                        self.sendMQTTSubscribe(topic: rxTopic)
                    }

                    if self.partnerDetectionEnabled && !self.statistics.primaryBand.isEmpty {
                        self.subscribeToBandTrafficIfNeeded(
                            band: self.statistics.primaryBand,
                            mode: self.statistics.primaryMode.isEmpty ? "FT8" : self.statistics.primaryMode
                        )
                    }
                }
            }
        case 9: // SUBACK
            Task { @MainActor in
                self.status = .streaming(reportsCount: self.spots.count)
            }
        case 3: // PUBLISH
            parseMQTTPublish(body: body)
        case 13: // PINGRESP
            break
        default:
            break
        }
    }

    private func parseMQTTPublish(body: Data) {
        guard body.count >= 2 else { return }
        let topicLen = (Int(body[0]) << 8) | Int(body[1])
        guard body.count >= 2 + topicLen else { return }

        let payloadData = body.subdata(in: (2 + topicLen)..<body.count)
        guard let jsonString = String(data: payloadData, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }

        let freqHz = json["f"] as? Int ?? 0
        let mode = json["md"] as? String ?? "FT8"
        let band = json["b"] as? String ?? ""
        let snr = json["rp"] as? Int ?? 0
        let rxStation = (json["rc"] as? String ?? "N/A").uppercased()
        let rxGrid = json["rl"] as? String ?? ""
        let txGrid = json["sl"] as? String ?? ""
        let txCall = (json["sc"] as? String ?? "").uppercased()
        let t_tx = json["t_tx"] as? Double ?? Date().timeIntervalSince1970
        let timestamp = Date(timeIntervalSince1970: t_tx)

        Task { @MainActor in
            let activeCall = self.activeSessionCallsign

            if txCall == activeCall {
                // 1. TARGET TRANSMISSION DETECTED
                let spotKey = "\(txCall)-\(rxStation)-\(freqHz)-\(Int(t_tx))"
                guard !self.seenSpotKeys.contains(spotKey) else { return }
                self.seenSpotKeys.insert(spotKey)

                let cycleSec = Int(t_tx) % 60
                let isEven = [0, 1, 29, 30, 59].contains(cycleSec)
                let cycleType: String
                if [14, 15, 44, 45].contains(cycleSec) {
                    cycleType = "Odd (:15 / :45)"
                } else if isEven {
                    cycleType = "Even (:00 / :30)"
                } else {
                    cycleType = ":\(String(format: "%02d", cycleSec))"
                }

                // Record target transmission for partner correlation
                let record = TargetTxRecord(
                    frequencyHz: freqHz,
                    timestamp: timestamp,
                    isEven: isEven,
                    grid: txGrid,
                    band: band,
                    mode: mode
                )
                self.recentTargetTxRecords.insert(record, at: 0)
                if self.recentTargetTxRecords.count > 25 {
                    self.recentTargetTxRecords.removeLast()
                }

                // Distance & Bearing calculations
                var distKm: Double? = nil
                var bearingDeg: Double? = nil
                var compass: String? = nil

                let rxDXCC = DXCCDatabase.resolve(callsign: rxStation)

                if !txGrid.isEmpty, !rxGrid.isEmpty,
                   let txBox = MaidenheadGridEngine.boundingBox(for: txGrid),
                   let rxBox = MaidenheadGridEngine.boundingBox(for: rxGrid) {
                    distKm = GeodesicMath.distanceKm(from: txBox.center, to: rxBox.center)
                    let az = GeodesicMath.initialBearing(from: txBox.center, to: rxBox.center)
                    bearingDeg = az
                    compass = GeodesicMath.compassCardinal(for: az)
                } else if !rxGrid.isEmpty, let rxBox = MaidenheadGridEngine.boundingBox(for: rxGrid) {
                    let homeCoord = self.homeCoordinate
                    distKm = GeodesicMath.distanceKm(from: homeCoord, to: rxBox.center)
                    let az = GeodesicMath.initialBearing(from: homeCoord, to: rxBox.center)
                    bearingDeg = az
                    compass = GeodesicMath.compassCardinal(for: az)
                }

                let spot = HamTrackSpot(
                    id: spotKey,
                    timestamp: timestamp,
                    senderCall: txCall,
                    senderGrid: txGrid,
                    receiverCall: rxStation,
                    receiverGrid: rxGrid,
                    receiverCountry: rxDXCC.entityName,
                    receiverFlag: rxDXCC.flagEmoji,
                    frequencyHz: freqHz,
                    band: band,
                    mode: mode,
                    snr: snr,
                    cycleSec: cycleSec,
                    cycleType: cycleType,
                    distanceKm: distKm,
                    bearingDeg: bearingDeg,
                    bearingCompass: compass,
                    isRealtimeMQTT: true
                )

                self.spots.insert(spot, at: 0)
                if self.spots.count > 400 {
                    self.spots.removeLast()
                }

                // Auto-subscribe to this band and mode traffic for partner correlation
                if self.partnerDetectionEnabled && !band.isEmpty {
                    self.subscribeToBandTrafficIfNeeded(band: band, mode: mode.isEmpty ? "FT8" : mode)
                }

                // Play alert & flash transmitting neon HUD
                self.triggerTransmissionAlert(spot: spot)
                self.recomputeStatistics()
                self.status = .streaming(reportsCount: self.spots.count)

            } else if !txCall.isEmpty && txCall != activeCall {
                // 2. NON-TARGET PACKET: EVALUATE FOR QSO PARTNER CANDIDACY
                self.evaluateQSOExchange(
                    sender: txCall,
                    freqHz: freqHz,
                    t_tx: t_tx,
                    txGrid: txGrid,
                    band: band,
                    mode: mode
                )
            }
        }
    }

    // MARK: - Active QSO Partner Correlation Engine

    private func subscribeToBandTrafficIfNeeded(band: String, mode: String) {
        let cleanBand = band.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanMode = (mode.isEmpty ? "FT8" : mode).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanBand.isEmpty else { return }

        let key = "\(cleanBand)/\(cleanMode)"
        guard !subscribedPartnerBands.contains(key) else { return }
        subscribedPartnerBands.insert(key)
        partnerScanningBand = "\(band.uppercased()) \(cleanMode)"

        let topic = "pskr/filter/v2/\(cleanBand)/\(cleanMode)/#"
        sendMQTTSubscribe(topic: topic)
    }

    private func evaluateQSOExchange(
        sender: String,
        freqHz: Int,
        t_tx: Double,
        txGrid: String,
        band: String,
        mode: String
    ) {
        guard partnerDetectionEnabled else { return }
        let now = Date()
        let sec = Int(t_tx) % 60
        let isEven = [0, 1, 29, 30, 59].contains(sec)
        let isOdd = [14, 15, 44, 45].contains(sec)
        guard isEven || isOdd else { return }

        // Prune old target records (older than 75 seconds)
        recentTargetTxRecords.removeAll(where: { now.timeIntervalSince($0.timestamp) > 75 })

        // Check if there is a matching target transmission in the opposite cycle within 45 Hz within last 45s
        guard let matchingTx = recentTargetTxRecords.first(where: { tx in
            let cycleOpposite = (isEven && !tx.isEven) || (isOdd && tx.isEven)
            let freqClose = abs(freqHz - tx.frequencyHz) <= 45
            let timeClose = abs(t_tx - tx.timestamp.timeIntervalSince1970) <= 45
            return cycleOpposite && freqClose && timeClose
        }) else {
            return
        }

        let deltaHz = freqHz - matchingTx.frequencyHz
        let cycleDesc = isEven ? "Even (:00 / :30)" : "Odd (:15 / :45)"

        // Distance & bearing from target station to this candidate partner
        var distFromTarget: Double? = nil
        var bearingFromTarget: Double? = nil
        if !matchingTx.grid.isEmpty, !txGrid.isEmpty,
           let targetBox = MaidenheadGridEngine.boundingBox(for: matchingTx.grid),
           let partnerBox = MaidenheadGridEngine.boundingBox(for: txGrid) {
            distFromTarget = GeodesicMath.distanceKm(from: targetBox.center, to: partnerBox.center)
            bearingFromTarget = GeodesicMath.initialBearing(from: targetBox.center, to: partnerBox.center)
        }

        // Distance from operator station to this candidate
        var distFromMe: Double? = nil
        if !txGrid.isEmpty, let partnerBox = MaidenheadGridEngine.boundingBox(for: txGrid) {
            distFromMe = GeodesicMath.distanceKm(from: homeCoordinate, to: partnerBox.center)
        }

        let dxcc = DXCCDatabase.resolve(callsign: sender)

        if let idx = partnerCandidates.firstIndex(where: { $0.callsign == sender }) {
            var candidate = partnerCandidates[idx]
            candidate.matchedCyclesCount += 1
            candidate.lastMatchedTimestamp = Date(timeIntervalSince1970: t_tx)
            candidate.matchedFrequencyHz = freqHz
            candidate.frequencyOffsetHz = deltaHz
            candidate.lastCycleSec = sec
            candidate.cycleParity = cycleDesc
            switch candidate.matchedCyclesCount {
            case 1: candidate.confidencePercentage = 60
            case 2: candidate.confidencePercentage = 85
            default: candidate.confidencePercentage = 98
            }
            partnerCandidates[idx] = candidate
        } else {
            let newCandidate = HamTrackPartnerCandidate(
                callsign: sender,
                country: dxcc.entityName,
                flag: dxcc.flagEmoji,
                grid: txGrid,
                matchedFrequencyHz: freqHz,
                frequencyOffsetHz: deltaHz,
                matchedCyclesCount: 1,
                lastMatchedTimestamp: Date(timeIntervalSince1970: t_tx),
                lastCycleSec: sec,
                cycleParity: cycleDesc,
                distanceKmFromTarget: distFromTarget,
                bearingDegFromTarget: bearingFromTarget,
                distanceKmFromMe: distFromMe,
                confidencePercentage: 60
            )
            partnerCandidates.append(newCandidate)
        }

        // Prune stale candidates older than 60 seconds
        partnerCandidates.removeAll(where: { now.timeIntervalSince($0.lastMatchedTimestamp) > 60 })

        // Sort candidates: most matched cycles first, then highest confidence, then most recent
        partnerCandidates.sort {
            if $0.matchedCyclesCount != $1.matchedCyclesCount {
                return $0.matchedCyclesCount > $1.matchedCyclesCount
            }
            return $0.lastMatchedTimestamp > $1.lastMatchedTimestamp
        }

        // Update active partner (highest ranked candidate seen within last 45 seconds)
        if let top = partnerCandidates.first(where: { now.timeIntervalSince($0.lastMatchedTimestamp) <= 45 }) {
            let isNew = (activePartner?.callsign != top.callsign)
            activePartner = top
            if isNew { playThrottledAlert("Hero") }
        }
    }

    // MARK: - Flash Animation & Audio Alert

    private func triggerTransmissionAlert(spot: HamTrackSpot) {
        playThrottledAlert("Glass")
    }

    private func playThrottledAlert(_ sound: String) {
        guard audioAlertsEnabled else { return }
        let now = Date()
        guard lastAudioAlertAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastAudioAlertAt = now
        NSSound(named: NSSound.Name(sound))?.play()
    }

    // MARK: - Instant PSKReporter REST Historical Catch-up

    private func fetchHistoricalCatchup(for callsign: String, secondsAgo: Int) {
        let endpoint = "https://retrieve.pskreporter.info/query?senderCallsign=\(callsign)&flowStartSeconds=-\(secondsAgo)&rptlimit=120"
        guard let url = URL(string: endpoint) else { return }

        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8.0
                request.setValue("YAAM-HamTracker/1.0 (Amateur Radio macOS)", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

                let parsedSpots = self.parsePSKReporterXML(data, targetCall: callsign)
                await MainActor.run {
                    for s in parsedSpots {
                        if !self.seenSpotKeys.contains(s.id) {
                            self.seenSpotKeys.insert(s.id)
                            self.spots.append(s)
                        }

                        if s.senderCall == callsign {
                            let isEven = [0, 1, 29, 30, 59].contains(s.cycleSec)
                            let record = TargetTxRecord(
                                frequencyHz: s.frequencyHz,
                                timestamp: s.timestamp,
                                isEven: isEven,
                                grid: s.senderGrid,
                                band: s.band,
                                mode: s.mode
                            )
                            self.recentTargetTxRecords.append(record)
                        }
                    }
                    self.spots.sort(by: { $0.timestamp > $1.timestamp })
                    self.recomputeStatistics()

                    if self.partnerDetectionEnabled && !self.statistics.primaryBand.isEmpty {
                        self.subscribeToBandTrafficIfNeeded(
                            band: self.statistics.primaryBand,
                            mode: self.statistics.primaryMode.isEmpty ? "FT8" : self.statistics.primaryMode
                        )
                    }
                }
            } catch {
                // Silently fallback to live MQTT stream
            }
        }
    }

    private func parsePSKReporterXML(_ data: Data, targetCall: String) -> [HamTrackSpot] {
        let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let pattern = #"<receptionReport\b([^>]*)/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)

        var parsed: [HamTrackSpot] = []
        for match in regex.matches(in: xml, range: range) where match.numberOfRanges > 1 {
            guard let attrRange = Range(match.range(at: 1), in: xml) else { continue }
            let attrs = parseXMLAttributes(String(xml[attrRange]))
            guard let sender = attrs["senderCallsign"],
                  let receiver = attrs["receiverCallsign"] else { continue }

            let freq = Int(attrs["frequency"] ?? "0") ?? 0
            let senderGrid = attrs["senderLocator"] ?? ""
            let receiverGrid = attrs["receiverLocator"] ?? ""
            let mode = attrs["mode"] ?? "FT8"
            let snr = Int(attrs["sNR"] ?? "") ?? 0
            let flowSeconds = Double(attrs["flowStartSeconds"] ?? "") ?? Date().timeIntervalSince1970
            let spotTime = Date(timeIntervalSince1970: flowSeconds)

            let cycleSec = Int(flowSeconds) % 60
            let cycleType: String
            if [14, 15, 44, 45].contains(cycleSec) {
                cycleType = "Odd (:15 / :45)"
            } else if [0, 1, 29, 30, 59].contains(cycleSec) {
                cycleType = "Even (:00 / :30)"
            } else {
                cycleType = ":\(String(format: "%02d", cycleSec))"
            }

            var dist: Double? = nil
            var bearing: Double? = nil
            var compass: String? = nil

            let dxcc = DXCCDatabase.resolve(callsign: receiver)

            if !senderGrid.isEmpty, !receiverGrid.isEmpty,
               let txBox = MaidenheadGridEngine.boundingBox(for: senderGrid),
               let rxBox = MaidenheadGridEngine.boundingBox(for: receiverGrid) {
                dist = GeodesicMath.distanceKm(from: txBox.center, to: rxBox.center)
                let az = GeodesicMath.initialBearing(from: txBox.center, to: rxBox.center)
                bearing = az
                compass = GeodesicMath.compassCardinal(for: az)
            } else if !receiverGrid.isEmpty, let rxBox = MaidenheadGridEngine.boundingBox(for: receiverGrid) {
                let homeCoord = self.homeCoordinate
                dist = GeodesicMath.distanceKm(from: homeCoord, to: rxBox.center)
                let az = GeodesicMath.initialBearing(from: homeCoord, to: rxBox.center)
                bearing = az
                compass = GeodesicMath.compassCardinal(for: az)
            }

            let spotId = "\(sender)-\(receiver)-\(freq)-\(Int(flowSeconds))"

            let resolvedBand: String
            if freq > 0 {
                let clBand = ClubLogSpotsService.bandFromFrequencyKHz(Double(freq) / 1000.0)
                if !clBand.isEmpty {
                    resolvedBand = clBand
                } else if let abp = AmateurBandPlan.band(forMHz: Double(freq) / 1_000_000.0) {
                    resolvedBand = abp.uppercased()
                } else {
                    resolvedBand = ""
                }
            } else {
                resolvedBand = ""
            }

            parsed.append(HamTrackSpot(
                id: spotId,
                timestamp: spotTime,
                senderCall: sender,
                senderGrid: senderGrid,
                receiverCall: receiver,
                receiverGrid: receiverGrid,
                receiverCountry: dxcc.entityName,
                receiverFlag: dxcc.flagEmoji,
                frequencyHz: freq,
                band: resolvedBand,
                mode: mode,
                snr: snr,
                cycleSec: cycleSec,
                cycleType: cycleType,
                distanceKm: dist,
                bearingDeg: bearing,
                bearingCompass: compass,
                isRealtimeMQTT: false
            ))
        }
        return parsed
    }

    private func parseXMLAttributes(_ raw: String) -> [String: String] {
        var results: [String: String] = [:]
        let pattern = #"(\w+)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return results }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for match in regex.matches(in: raw, range: range) where match.numberOfRanges == 3 {
            if let keyRange = Range(match.range(at: 1), in: raw),
               let valRange = Range(match.range(at: 2), in: raw) {
                results[String(raw[keyRange])] = String(raw[valRange])
            }
        }
        return results
    }

    // MARK: - DX Cluster Query (Telnet)

    private func queryClusterHistory(for callsign: String) {
        disconnectCluster()
        clusterReceiveBuffer = ""

        let host = NWEndpoint.Host("dxc.w3lpl.net")
        let port = NWEndpoint.Port(rawValue: 7373) ?? .init(integerLiteral: 7373)
        let params = NWParameters.tcp

        let conn = NWConnection(host: host, port: port, using: params)
        self.clusterConnection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state {
                Task { @MainActor in
                    self.handleClusterConnected(conn: conn, callsign: callsign)
                }
            }
        }

        conn.start(queue: networkQueue)
    }

    private func handleClusterConnected(conn: NWConnection, callsign: String) {
        // Send Guest Login -> wait -> sh/dx 15 <callsign>
        networkQueue.asyncAfter(deadline: .now() + 0.6) {
            let loginData = "GUEST\r\n".data(using: .isoLatin1) ?? Data()
            conn.send(content: loginData, completion: .contentProcessed({ _ in }))

            self.networkQueue.asyncAfter(deadline: .now() + 0.8) {
                let cmdData = "sh/dx 15 \(callsign)\r\n".data(using: .isoLatin1) ?? Data()
                conn.send(content: cmdData, completion: .contentProcessed({ _ in }))
                self.receiveClusterResponse(conn: conn, callsign: callsign)
            }
        }
    }

    private func receiveClusterResponse(conn: NWConnection, callsign: String) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            if let data, let text = String(data: data, encoding: .isoLatin1) {
                self.clusterReceiveBuffer.append(text)
            }
            if isComplete {
                Task { @MainActor [weak self] in
                    self?.parseClusterBuffer(callsign: callsign)
                    self?.disconnectCluster()
                }
                return
            }
            // Give 2.5 seconds to collect cluster response
            self.networkQueue.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.parseClusterBuffer(callsign: callsign)
                    self?.disconnectCluster()
                }
            }
        }
    }

    private func parseClusterBuffer(callsign: String) {
        let lines = clusterReceiveBuffer.components(separatedBy: .newlines)
        var newSpots: [HamTrackClusterSpot] = []

        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanLine.localizedCaseInsensitiveContains(callsign),
                  (cleanLine.contains("Z") || cleanLine.contains("kHz") || cleanLine.hasPrefix("DX de")) else {
                continue
            }

            // Extract frequency, spotter, remarks
            let parsed = parseDXClusterLine(cleanLine, targetCall: callsign)
            newSpots.append(parsed)
        }

        Task { @MainActor in
            self.clusterSpots = newSpots
        }
    }

    private func parseDXClusterLine(_ line: String, targetCall: String) -> HamTrackClusterSpot {
        // Line schema: "DX de SPOTTER:  14074.0  TARGET  Comment...  1234Z"
        var spotter = ""
        var freq: Double = 0.0
        var comment = line
        var timeStr = ""

        if line.hasPrefix("DX de ") {
            let afterPrefix = line.dropFirst(6)
            if let colonIdx = afterPrefix.firstIndex(of: ":") {
                spotter = String(afterPrefix[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let remainder = afterPrefix[afterPrefix.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                let parts = remainder.split(separator: " ", omittingEmptySubsequences: true)
                if parts.count >= 2 {
                    freq = Double(parts[0]) ?? 0.0
                }
                comment = remainder
            }
        }

        // Look for trailing 4-digit Zulu time (e.g. 1542Z)
        let pattern = #"\b(\d{4})Z\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
           let r = Range(match.range(at: 1), in: line) {
            timeStr = String(line[r]) + "Z"
        }

        return HamTrackClusterSpot(
            id: UUID(),
            rawText: line,
            spotterCall: spotter.isEmpty ? "DX-Cluster" : spotter,
            spottedCall: targetCall,
            frequencyKHz: freq,
            comment: comment,
            timeString: timeStr.isEmpty ? "Recent" : timeStr,
            timestamp: Date()
        )
    }

    private func disconnectCluster() {
        clusterConnection?.cancel()
        clusterConnection = nil
    }

    // MARK: - Cycle Ticker (Every 1 Second)

    private func startCycleTicker() {
        stopCycleTicker()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.updateCycleStatus()
        }
        timer.resume()
        self.cycleTicker = timer
    }

    private func stopCycleTicker() {
        cycleTicker?.cancel()
        cycleTicker = nil
    }

    private func updateCycleStatus() {
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let utcSecond = calendar.component(.second, from: now)

        let offset = utcSecond % 15
        let remaining = 15 - offset
        let progress = Double(offset) / 15.0

        let isEvenSlot = (utcSecond < 15) || (utcSecond >= 30 && utcSecond < 45)
        let currentSlot: CycleSlotParity = isEvenSlot ? .even : .odd
        let slotLabel = currentSlot.rawValue

        // 1. Maintain Active QSO Partner Timeout (45-second sliding window)
        if let current = activePartner {
            let partnerDiff = now.timeIntervalSince(current.lastMatchedTimestamp)
            if partnerDiff > 45.0 {
                // QSO concluded! Archive to completed QSOs
                let completed = HamTrackCompletedQSO(
                    callsign: current.callsign,
                    country: current.country,
                    flag: current.flag,
                    grid: current.grid,
                    frequencyMHz: current.frequencyMHz,
                    band: statistics.primaryBand.isEmpty ? "FT8" : statistics.primaryBand,
                    mode: statistics.primaryMode.isEmpty ? "FT8" : statistics.primaryMode,
                    totalCycles: current.matchedCyclesCount,
                    completedTimestamp: current.lastMatchedTimestamp,
                    distanceKm: current.distanceKmFromTarget,
                    bearingDeg: current.bearingDegFromTarget
                )
                if !recentCompletedQSOs.contains(where: { $0.callsign == completed.callsign && abs($0.completedTimestamp.timeIntervalSince(completed.completedTimestamp)) < 30 }) {
                    recentCompletedQSOs.insert(completed, at: 0)
                    if recentCompletedQSOs.count > 25 { recentCompletedQSOs.removeLast() }
                }
                activePartner = nil
            }
        }

        // Prune stale candidates older than 60s
        partnerCandidates.removeAll(where: { now.timeIntervalSince($0.lastMatchedTimestamp) > 60 })

        // Check if there is an active partner candidate from recent exchanges
        if activePartner == nil {
            if let fresh = partnerCandidates.first(where: { now.timeIntervalSince($0.lastMatchedTimestamp) <= 45 }) {
                activePartner = fresh
            }
        }

        // 2. Identify Target Station's Cadence & Parity
        let targetParity: CycleSlotParity?
        if cycleStatus.evenCount > cycleStatus.oddCount {
            targetParity = .even
        } else if cycleStatus.oddCount > cycleStatus.evenCount {
            targetParity = .odd
        } else if let recent = spots.first(where: { $0.senderCall == activeSessionCallsign }) {
            targetParity = [0, 1, 29, 30, 59].contains(recent.cycleSec) ? .even : .odd
        } else {
            targetParity = nil
        }

        // 3. Timing and Activity State
        var lastSeenAgo: Int? = nil
        var isTransmitting = false
        var isListening = false
        var newState: StationActivityState = .idle(secondsAgo: nil)

        let targetSpot = spots.first(where: { $0.senderCall == activeSessionCallsign })
        if let targetSpot {
            let diff = Int(now.timeIntervalSince(targetSpot.timestamp))
            lastSeenAgo = diff

            let primaryBand = statistics.primaryBand.isEmpty ? targetSpot.band : statistics.primaryBand
            let primaryFreq = statistics.primaryFrequencyMHz > 0 ? statistics.primaryFrequencyMHz : targetSpot.frequencyMHz

            // Within 75 seconds of last spotted transmission, station is in active FT8 sequence
            if diff <= 75 {
                let stationTxParity = targetParity ?? ([0, 1, 29, 30, 59].contains(targetSpot.cycleSec) ? .even : .odd)
                if currentSlot == stationTxParity {
                    // Current slot is the station's transmit slot! Stays true for entire 15 seconds
                    isTransmitting = true
                    isListening = false
                    if let partner = activePartner {
                        newState = .transmittingToPartner(
                            partnerCall: partner.callsign,
                            band: primaryBand,
                            freqMHz: primaryFreq,
                            round: partner.matchedCyclesCount,
                            slotRemaining: remaining
                        )
                    } else {
                        newState = .transmittingCQ(
                            band: primaryBand,
                            freqMHz: primaryFreq,
                            slotRemaining: remaining
                        )
                    }
                } else {
                    // Alternate slot is the station's receive/listening slot!
                    isTransmitting = false
                    isListening = true
                    if let partner = activePartner {
                        newState = .listeningForPartner(
                            partnerCall: partner.callsign,
                            band: primaryBand,
                            freqMHz: primaryFreq,
                            decodeIn: remaining
                        )
                    } else {
                        newState = .listeningForCallers(
                            band: primaryBand,
                            freqMHz: primaryFreq,
                            decodeIn: remaining
                        )
                    }
                }
            } else if diff <= 180 {
                newState = .idle(secondsAgo: diff)
            } else {
                newState = .qrt(lastSeenSecondsAgo: diff)
            }
        }

        cycleStatus.currentUTCSecond = utcSecond
        cycleStatus.slotSecondsRemaining = remaining
        cycleStatus.progress = progress
        cycleStatus.currentSlotParity = currentSlot
        cycleStatus.currentSlotLabel = slotLabel
        cycleStatus.targetCadenceParity = targetParity
        cycleStatus.isTargetTransmittingNow = isTransmitting
        cycleStatus.isTargetListeningNow = isListening
        cycleStatus.activityState = newState
        cycleStatus.lastSeenSecondsAgo = lastSeenAgo
        isTransmittingFlash = isTransmitting
    }

    // MARK: - Statistics Computation

    private func recomputeStatistics() {
        guard !spots.isEmpty else {
            statistics = HamTrackStatistics()
            updateTargetMetadata(targetCallsign)
            return
        }

        var uniqueReceivers = Set<String>()
        var sumSNR = 0
        var maxSNR = -99
        var maxSpotter = ""
        var minSNR = 99
        var minSpotter = ""
        var maxDist = 0.0
        var maxDistSpotter = ""
        var maxDistCountry = ""
        var maxDistFlag = ""
        var bands: [String: Int] = [:]
        var modes: [String: Int] = [:]
        var continents = Set<String>()
        var txGrid = ""
        var liveMQTTCount = 0

        var evenCount = 0
        var oddCount = 0

        for s in spots {
            if s.isRealtimeMQTT { liveMQTTCount += 1 }
            uniqueReceivers.insert(s.receiverCall)
            sumSNR += s.snr

            if s.snr > maxSNR {
                maxSNR = s.snr
                maxSpotter = s.receiverCall
            }
            if s.snr < minSNR {
                minSNR = s.snr
                minSpotter = s.receiverCall
            }

            if let d = s.distanceKm, d > maxDist {
                maxDist = d
                maxDistSpotter = s.receiverCall
                maxDistCountry = s.receiverCountry
                maxDistFlag = s.receiverFlag
            }

            if !s.senderGrid.isEmpty && txGrid.isEmpty {
                txGrid = s.senderGrid
            }

            bands[s.band, default: 0] += 1
            modes[s.mode, default: 0] += 1

            let dxcc = DXCCDatabase.resolve(callsign: s.receiverCall)
            let cont = dxcc.continent.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !cont.isEmpty && cont != "??" && cont != "--" && cont.count == 2 {
                continents.insert(cont)
            }

            if s.cycleType.contains("Even") {
                evenCount += 1
            } else if s.cycleType.contains("Odd") {
                oddCount += 1
            }
        }

        let avg = Double(sumSNR) / Double(spots.count)
        let topBand = bands.max(by: { $0.value < $1.value })?.key ?? ""
        let topMode = modes.max(by: { $0.value < $1.value })?.key ?? ""

        statistics.totalSpots = spots.count
        statistics.liveMQTTSpots = liveMQTTCount
        statistics.uniqueSpottersCount = uniqueReceivers.count
        statistics.averageSNR = avg
        statistics.peakSNR = maxSNR
        statistics.peakSpotter = maxSpotter
        statistics.weakestSNR = minSNR
        statistics.weakestSpotter = minSpotter
        statistics.furthestDistanceKm = maxDist
        statistics.furthestSpotter = maxDistSpotter
        statistics.furthestCountry = maxDistCountry
        statistics.furthestFlag = maxDistFlag
        statistics.activeBands = bands
        statistics.activeModes = modes
        statistics.continents = Array(continents).sorted()
        statistics.targetTransmitterGrid = txGrid
        statistics.primaryBand = topBand
        statistics.primaryMode = topMode

        if let first = spots.first {
            statistics.primaryFrequencyMHz = first.frequencyMHz
        }

        cycleStatus.evenCount = evenCount
        cycleStatus.oddCount = oddCount
        if evenCount > (oddCount * 3 / 2) {
            cycleStatus.detectedCadence = "Even Cycles (:00 / :30)"
            cycleStatus.targetCadenceParity = .even
        } else if oddCount > (evenCount * 3 / 2) {
            cycleStatus.detectedCadence = "Odd Cycles (:15 / :45)"
            cycleStatus.targetCadenceParity = .odd
        } else if (evenCount + oddCount) > 0 {
            cycleStatus.detectedCadence = "Alternating / Mixed"
            cycleStatus.targetCadenceParity = nil
        } else {
            cycleStatus.detectedCadence = "Analyzing..."
            cycleStatus.targetCadenceParity = nil
        }
    }

    // MARK: - Execute Python ham_tracker.py (Diagnostic Mode)

    public func runPythonScript(callsign: String? = nil, duration: Int = 15, detectPartner: Bool = false) {
        let activeCall = (callsign ?? targetCallsign).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !activeCall.isEmpty else { return }
        guard let scriptURL = Bundle.main.url(forResource: "ham_tracker", withExtension: "py") else {
            cliTerminalLog = "[-] Bundled ham_tracker.py is unavailable.\n"
            return
        }

        isRunningCLI = true
        let partnerArg = detectPartner ? " --partner" : ""
        cliTerminalLog = "[*] Launching ham_tracker.py for \(activeCall)\(partnerArg) (duration: \(duration)s)...\n"

        networkQueue.async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            var args = [scriptURL.path, activeCall, "-t", "\(duration)"]
            if detectPartner {
                args.append("--partner")
            }
            process.arguments = args
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8) ?? "No output."
                Task { @MainActor in
                    self.cliTerminalLog.append(output)
                    self.cliTerminalLog.append("\n[*] Process exited with code \(process.terminationStatus)\n")
                    self.isRunningCLI = false
                }
            } catch {
                Task { @MainActor in
                    self.cliTerminalLog.append("\n[-] Failed to execute Python script: \(error.localizedDescription)\n")
                    self.isRunningCLI = false
                }
            }
        }
    }

    // MARK: - Search History Persistence

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: "hamTracker.recentSearches") ?? []
    }

    private func saveRecentSearch(_ call: String) {
        var list = recentSearches.filter { $0 != call }
        list.insert(call, at: 0)
        if list.count > 12 { list = Array(list.prefix(12)) }
        recentSearches = list
        UserDefaults.standard.set(list, forKey: "hamTracker.recentSearches")
    }

    // MARK: - MQTT Wire Helpers

    private func encodeMQTTString(_ str: String) -> Data {
        let utf8 = str.data(using: .utf8) ?? Data()
        var data = Data([UInt8(utf8.count >> 8), UInt8(utf8.count & 0xFF)])
        data.append(utf8)
        return data
    }

    private func encodeRemainingLength(_ length: Int) -> Data {
        var result = Data()
        var val = length
        repeat {
            var encodedByte = UInt8(val & 0x7F)
            val >>= 7
            if val > 0 {
                encodedByte |= 0x80
            }
            result.append(encodedByte)
        } while val > 0
        return result
    }

    private func decodeRemainingLength(from data: Data, offset: inout Int) -> Int? {
        var multiplier = 1
        var value = 0
        var bytesRead = 0

        while offset < data.count {
            let byte = data[offset]
            offset += 1
            bytesRead += 1
            value += Int(byte & 0x7F) * multiplier
            multiplier *= 128
            if (byte & 0x80) == 0 {
                return value
            }
            if bytesRead > 4 { return nil }
        }
        return nil
    }
}
