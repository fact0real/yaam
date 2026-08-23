//
//  IcomNetworkRadio.swift
//  YAAM
//

import Combine
import Darwin
import Foundation

nonisolated enum IcomNetworkModel: String, CaseIterable, Identifiable, Sendable {
    case ic7300MKII = "IC-7300MKII"
    case ic705 = "IC-705"

    var id: String { rawValue }

    var civAddress: UInt8 {
        switch self {
        case .ic7300MKII: return 0xB6
        case .ic705: return 0xA4
        }
    }
}

nonisolated enum IcomNetworkConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case openingStreams
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: return "Offline"
        case .connecting: return "Finding radio"
        case .authenticating: return "Signing in"
        case .openingStreams: return "Opening CI-V and audio"
        case .connected: return "Connected"
        case .failed: return "Connection failed"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isTransitioning: Bool {
        switch self {
        case .connecting, .authenticating, .openingStreams:
            return true
        default:
            return false
        }
    }

    var canDisconnect: Bool {
        isConnected || isTransitioning
    }
}

nonisolated struct IcomNetworkSnapshot: Equatable, Sendable {
    var frequencyHz: UInt64
    var mode: String
    var updatedAt: Date

    var frequencyMHz: String {
        AmateurBandPlan.formattedMHz(Double(frequencyHz) / 1_000_000)
    }

    var band: String {
        AmateurBandPlan.band(forMHz: Double(frequencyHz) / 1_000_000) ?? ""
    }
}

nonisolated struct IcomNetworkSettings: Sendable {
    var host: String
    var controlPort: Int
    var username: String
    var clientName: String
    var model: IcomNetworkModel
}

nonisolated enum IcomNetworkError: LocalizedError, Sendable {
    case invalidSettings
    case socket(String)
    case authentication(String)
    case radioBusy
    case streamUnavailable
    case transmitNotArmed
    case disconnected

    var errorDescription: String? {
        switch self {
        case .invalidSettings:
            return "Enter a valid radio address, control port, username, and password."
        case .socket(let message):
            return message
        case .authentication(let message):
            return message
        case .radioBusy:
            return "The radio is already in use by another network client."
        case .streamUnavailable:
            return "The radio did not provide CI-V and audio streams."
        case .transmitNotArmed:
            return "Transmit is locked. Arm TX before sending FT8 audio."
        case .disconnected:
            return "The Icom network radio is not connected."
        }
    }
}

/// Direct Icom LAN client for the control, CI-V, and LPCM16 audio channels used
/// by RS-BA1-compatible radios. UI state is published on the main thread while
/// all packet work stays on a dedicated serial queue.
nonisolated final class IcomNetworkRadio: ObservableObject, @unchecked Sendable {
    @MainActor @Published private(set) var state: IcomNetworkConnectionState = .disconnected
    @MainActor @Published private(set) var snapshot: IcomNetworkSnapshot?
    @MainActor @Published private(set) var lastMessage = "Direct Icom LAN is offline"
    @MainActor @Published private(set) var radioName = ""
    @MainActor @Published private(set) var isTransmitting = false
    @MainActor @Published private(set) var receivedAudioPackets = 0
    @MainActor @Published private(set) var lastAudioAt: Date?
    @MainActor @Published var transmitArmed = false {
        didSet {
            if !transmitArmed, isTransmitting { setPTT(false) }
        }
    }
    @MainActor private var publishedGeneration = UUID()

    @MainActor
    func setAudioSampleHandler(_ handler: (@Sendable ([Float], Date) -> Void)?) {
        queue.async { [weak self] in
            self?._audioSampleHandler = handler
        }
    }

    private enum StreamKind { case control, civ, audio }

    private struct TransmitPacketCache {
        private let capacity = 2_048
        private var packets: [UInt16: Data] = [:]
        private var order: [UInt16] = []

        mutating func insert(_ packet: Data, sequence: UInt16) {
            if packets[sequence] == nil { order.append(sequence) }
            packets[sequence] = packet
            guard order.count > capacity else { return }
            let overflow = order.count - capacity
            for expired in order.prefix(overflow) { packets.removeValue(forKey: expired) }
            order.removeFirst(overflow)
        }

        func packet(for sequence: UInt16) -> Data? {
            packets[sequence]
        }
    }

    private struct RadioCapability {
        var identity: Data
        var name: String
        var civAddress: UInt8
        var supportsTX: Bool
    }

    private let queue = DispatchQueue(label: "app.yaam.icom-network", qos: .userInitiated)
    private var generation = UUID()
    private var settings: IcomNetworkSettings?
    private var password = ""
    private var controlSocket: IcomUDPSocket?
    private var civSocket: IcomUDPSocket?
    private var audioSocket: IcomUDPSocket?
    private var controlRemoteID: UInt32 = 0
    private var civRemoteID: UInt32 = 0
    private var audioRemoteID: UInt32 = 0
    private var controlSequence: UInt16 = 0
    private var civSequence: UInt16 = 0
    private var audioSequence: UInt16 = 0
    private var controlPingSequence: UInt16 = 0
    private var civPingSequence: UInt16 = 0
    private var audioPingSequence: UInt16 = 0
    private var controlTransmitCache = TransmitPacketCache()
    private var civTransmitCache = TransmitPacketCache()
    private var audioTransmitCache = TransmitPacketCache()
    private var civDataSequence: UInt16 = 0
    private var audioDataSequence: UInt16 = 0
    private var authSequence: UInt16 = 0
    private var tokenRequest: UInt16 = 0
    private var token: UInt32 = 0
    private var selectedCapability: RadioCapability?
    private var loginSent = false
    private var streamRequested = false
    private var civReady = false
    private var audioReady = false
    private var startedAt = Date.distantPast
    private var lastControlPacketAt = Date.distantPast
    private var keepaliveTimer: DispatchSourceTimer?
    private var tokenTimer: DispatchSourceTimer?
    private var pttWatchdog: DispatchWorkItem?
    private var _audioSampleHandler: (@Sendable ([Float], Date) -> Void)?
    private var isStopping = false

    deinit {
        keepaliveTimer?.cancel()
        tokenTimer?.cancel()
        pttWatchdog?.cancel()
        controlSocket?.close()
        civSocket?.close()
        audioSocket?.close()
    }

    @MainActor
    func connect(settings proposed: IcomNetworkSettings, password proposedPassword: String) {
        let clean = IcomNetworkSettings(
            host: proposed.host.trimmingCharacters(in: .whitespacesAndNewlines),
            controlPort: proposed.controlPort,
            username: Self.limitedUTF8(
                proposed.username.trimmingCharacters(in: .whitespacesAndNewlines),
                maximumBytes: 16
            ),
            clientName: Self.limitedUTF8(
                proposed.clientName.trimmingCharacters(in: .whitespacesAndNewlines),
                maximumBytes: 16
            ),
            model: proposed.model
        )
        let cleanPassword = Self.limitedUTF8(proposedPassword, maximumBytes: 16)
        guard !clean.host.isEmpty,
              (1...65_535).contains(clean.controlPort),
              !clean.username.isEmpty,
              !cleanPassword.isEmpty else {
            state = .failed(IcomNetworkError.invalidSettings.localizedDescription)
            lastMessage = IcomNetworkError.invalidSettings.localizedDescription
            return
        }

        let id = UUID()
        publishedGeneration = id
        pttWatchdog?.cancel()
        pttWatchdog = nil
        isTransmitting = false
        transmitArmed = false
        state = .connecting
        lastMessage = "Opening \(clean.host):\(clean.controlPort)..."

        queue.async { [weak self] in
            guard let self else { return }
            self.stopNetworkState()
            self.generation = id
            self.settings = clean
            self.password = cleanPassword
            self.startedAt = Date()
            do {
                let socket = try IcomUDPSocket(queue: self.queue) { [weak self] data in
                    self?.receive(data, on: .control, generation: id)
                } onError: { [weak self] message in
                    self?.fail(message, generation: id)
                }
                try socket.connect(host: clean.host, port: UInt16(clean.controlPort))
                self.controlSocket = socket
                self.sendControl(type: 0x03, tracked: false, sequence: 0, on: .control)
                self.startKeepalive(generation: id)
            } catch {
                self.fail("Unable to open Icom LAN control: \(error.localizedDescription)", generation: id)
            }
        }
    }

    @MainActor
    func disconnect() {
        let id = UUID()
        publishedGeneration = id
        pttWatchdog?.cancel()
        pttWatchdog = nil
        queue.async { [weak self] in
            guard let self else { return }
            self.generation = id
            self.isStopping = true
            self.sendPTT(false)
            self.sendControl(type: 0x05, tracked: false, sequence: 0, on: .civ)
            self.sendControl(type: 0x05, tracked: false, sequence: 0, on: .audio)
            self.sendControl(type: 0x05, tracked: false, sequence: 0, on: .control)
            self.stopNetworkState()
            self.settings = nil
            self.isStopping = false
        }
        isTransmitting = false
        transmitArmed = false
        state = .disconnected
        lastMessage = "Direct Icom LAN disconnected"
    }

    @MainActor
    func refresh() {
        queue.async { [weak self] in
            self?.sendCIV(command: [0x03])
            self?.sendCIV(command: [0x04])
        }
    }

    @MainActor
    func setFrequencyHz(_ frequencyHz: UInt64) {
        guard frequencyHz > 0 else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.sendCIV(command: [0x05] + Self.frequencyBCD(frequencyHz))
            self.queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.sendCIV(command: [0x03]) }
        }
    }

    @MainActor
    func setUSBDataMode() {
        queue.async { [weak self] in
            guard let self else { return }
            self.sendCIV(command: [0x06, 0x01])
            self.sendCIV(command: [0x1A, 0x06, 0x01, 0x01])
        }
    }

    @MainActor
    func setPTT(_ enabled: Bool, maximumDuration: TimeInterval = 16) {
        if enabled {
            guard transmitArmed, state.isConnected else {
                lastMessage = IcomNetworkError.transmitNotArmed.localizedDescription
                return
            }
        }

        pttWatchdog?.cancel()
        pttWatchdog = nil
        isTransmitting = enabled
        queue.async { [weak self] in self?.sendPTT(enabled) }
        lastMessage = enabled ? "PTT active on \(radioName)" : "PTT released"

        guard enabled else { return }
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.isTransmitting else { return }
            self.queue.async { [weak self] in self?.sendPTT(false) }
            DispatchQueue.main.async {
                self.isTransmitting = false
                self.transmitArmed = false
                self.lastMessage = "PTT released by the safety timer"
            }
        }
        pttWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, maximumDuration), execute: watchdog)
    }

    /// Streams mono float audio as 48 kHz LPCM16 in real time. Each 20 ms frame
    /// is split at Icom's 1,364-byte payload limit before the next frame is due.
    @MainActor
    func transmit(samples: [Float], gain: Float) async throws {
        guard state.isConnected else { throw IcomNetworkError.disconnected }
        guard transmitArmed else { throw IcomNetworkError.transmitNotArmed }
        let boundedGain = max(0.02, min(1, gain))
        let framesPerPacket = 960
        var index = 0
        while index < samples.count {
            try Task.checkCancellation()
            guard state.isConnected, transmitArmed else { throw IcomNetworkError.disconnected }
            let end = min(samples.count, index + framesPerPacket)
            let frame = Array(samples[index..<end])
            await withCheckedContinuation { continuation in
                queue.async { [weak self] in
                    self?.sendAudio(frame, gain: boundedGain)
                    continuation.resume()
                }
            }
            index = end
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func startKeepalive(generation id: UUID) {
        keepaliveTimer?.cancel()
        var ticks = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100), leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            guard let self, self.generation == id else { return }
            ticks += 1
            if self.controlRemoteID == 0 {
                if ticks.isMultiple(of: 5) { self.sendControl(type: 0x03, tracked: false, sequence: 0, on: .control) }
                if Date().timeIntervalSince(self.startedAt) > 20 {
                    self.fail("The radio did not answer on the Icom control port.", generation: id)
                }
                return
            }
            self.sendControl(type: 0x00, tracked: true, sequence: 0, on: .control)
            if self.civSocket != nil { self.sendControl(type: 0x00, tracked: true, sequence: 0, on: .civ) }
            if self.audioSocket != nil { self.sendControl(type: 0x00, tracked: true, sequence: 0, on: .audio) }
            if ticks.isMultiple(of: 5) {
                self.sendPing(on: .control)
                if self.civReady { self.sendPing(on: .civ) }
                if self.audioReady { self.sendPing(on: .audio) }
            }
            if ticks.isMultiple(of: 10), self.civReady {
                self.sendCIV(command: [0x03])
            }
        }
        timer.resume()
        keepaliveTimer = timer
    }

    private func startTokenRenewal(generation id: UUID) {
        tokenTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in
            guard let self, self.generation == id else { return }
            self.sendToken(requestType: 0x05)
        }
        timer.resume()
        tokenTimer = timer
    }

    private func receive(_ data: Data, on stream: StreamKind, generation id: UUID) {
        guard generation == id, data.count >= 16 else { return }
        let declaredLength = Int(data.uint32LE(at: 0))
        guard declaredLength == data.count else { return }
        lastControlPacketAt = Date()
        let type = data.uint16LE(at: 4)
        let senderID = data.uint32LE(at: 8)

        if type == 0x01 {
            handleRetransmitRequest(data, on: stream)
            return
        }
        if data.count == 21, type == 0x07 {
            if data[16] == 0 { sendPingReply(data, on: stream) }
            return
        }
        if data.count == 16 {
            if type == 0x04 {
                setRemoteID(senderID, for: stream)
                sendControl(type: 0x06, tracked: false, sequence: 1, on: stream)
            } else if type == 0x06 {
                setRemoteID(senderID, for: stream)
                switch stream {
                case .control:
                    if !loginSent { sendLogin() }
                case .civ:
                    civReady = true
                    sendOpenCIV()
                    publishConnectedIfReady()
                case .audio:
                    audioReady = true
                    publishConnectedIfReady()
                }
            }
            return
        }

        switch stream {
        case .control:
            receiveControlPayload(data)
        case .civ:
            receiveCIVPayload(data)
        case .audio:
            receiveAudioPayload(data)
        }
    }

    private func receiveControlPayload(_ data: Data) {
        switch data.count {
        case 96:
            let error = data.uint32LE(at: 48)
            if error != 0 {
                fail("Icom rejected the username or password.", generation: generation)
                return
            }
            guard data.uint16LE(at: 26) == tokenRequest else { return }
            token = data.uint32LE(at: 28)
            publish(state: .openingStreams, message: "Authenticated; requesting radio streams...")
            sendToken(requestType: 0x02)
            startTokenRenewal(generation: generation)
        case 80:
            let error = data.uint32LE(at: 48)
            if error == UInt32.max {
                fail("The radio refused the requested stream. It may be busy.", generation: generation)
                return
            }
            if data[64] == 1 {
                fail("The radio closed the remote stream.", generation: generation)
                return
            }
            let civPort = data.uint16BE(at: 66)
            let audioPort = data.uint16BE(at: 70)
            guard civPort > 0, audioPort > 0 else {
                fail(IcomNetworkError.streamUnavailable.localizedDescription, generation: generation)
                return
            }
            openRemoteStreams(civPort: civPort, audioPort: audioPort)
        case 64:
            if data[21] == 0x05, data[20] == 0x02, data.uint32LE(at: 48) == 0 {
                startTokenRenewal(generation: generation)
            }
        default:
            if data.count >= 66, (data.count - 66).isMultiple(of: 102) {
                receiveCapabilities(data)
            } else if data.count == 144, !streamRequested {
                requestSelectedRadioIfPossible()
            }
        }
    }

    private func receiveCapabilities(_ data: Data) {
        guard let wanted = settings?.model else { return }
        var candidates: [RadioCapability] = []
        var offset = 66
        while offset + 102 <= data.count {
            let block = Data(data[offset..<(offset + 102)])
            candidates.append(RadioCapability(
                identity: Data(block[0..<16]),
                name: block.nullTerminatedString(in: 16..<48),
                civAddress: block[82],
                supportsTX: block.uint16BE(at: 85) > 1
            ))
            offset += 102
        }
        guard !candidates.isEmpty else { return }
        selectedCapability = candidates.first(where: { $0.civAddress == wanted.civAddress }) ?? candidates[0]
        requestSelectedRadioIfPossible()
    }

    private func requestSelectedRadioIfPossible() {
        guard !streamRequested, let capability = selectedCapability, let settings else { return }
        do {
            let civ = try IcomUDPSocket(queue: queue) { [weak self] data in
                guard let self else { return }
                self.receive(data, on: .civ, generation: self.generation)
            } onError: { [weak self] message in
                guard let self else { return }
                self.fail(message, generation: self.generation)
            }
            let audio = try IcomUDPSocket(queue: queue) { [weak self] data in
                guard let self else { return }
                self.receive(data, on: .audio, generation: self.generation)
            } onError: { [weak self] message in
                guard let self else { return }
                self.fail(message, generation: self.generation)
            }
            civSocket = civ
            audioSocket = audio

            var packet = basePacket(size: 144, on: .control)
            packet.writeUInt32BE(128, at: 16)
            packet[20] = 0x01
            packet[21] = 0x03
            packet.writeUInt16BE(authSequence, at: 22)
            authSequence &+= 1
            packet.writeUInt16LE(tokenRequest, at: 26)
            packet.writeUInt32LE(token, at: 28)
            packet.replaceSubrange(32..<48, with: capability.identity.prefix(16))
            packet.writeCString(capability.name, at: 64, maximum: 32)
            packet.writeBytes(Self.obfuscated(settings.username), at: 96, maximum: 16)
            packet[112] = 1
            packet[113] = capability.supportsTX ? 1 : 0
            packet[114] = 0x04
            packet[115] = capability.supportsTX ? 0x04 : 0
            packet.writeUInt32BE(48_000, at: 116)
            packet.writeUInt32BE(capability.supportsTX ? 48_000 : 0, at: 120)
            packet.writeUInt32BE(UInt32(civ.localPort), at: 124)
            packet.writeUInt32BE(UInt32(audio.localPort), at: 128)
            packet.writeUInt32BE(120, at: 132)
            packet[136] = 1
            streamRequested = true
            sendTracked(packet, on: .control)
            publish(state: .openingStreams, message: "Opening \(capability.name) CI-V and audio...")
        } catch {
            fail("Unable to reserve Icom stream ports: \(error.localizedDescription)", generation: generation)
        }
    }

    private func openRemoteStreams(civPort: UInt16, audioPort: UInt16) {
        guard let settings, let civSocket, let audioSocket else { return }
        do {
            try civSocket.connect(host: settings.host, port: civPort)
            try audioSocket.connect(host: settings.host, port: audioPort)
            sendControl(type: 0x03, tracked: false, sequence: 0, on: .civ)
            sendControl(type: 0x03, tracked: false, sequence: 0, on: .audio)
        } catch {
            fail("Unable to open Icom CI-V/audio channels: \(error.localizedDescription)", generation: generation)
        }
    }

    private func publishConnectedIfReady() {
        guard civReady, audioReady else { return }
        let name = selectedCapability?.name.isEmpty == false ? selectedCapability?.name ?? "Icom" : settings?.model.rawValue ?? "Icom"
        DispatchQueue.main.async {
            self.radioName = name
            self.state = .connected
            self.lastMessage = "\(name) LAN, CI-V, RX audio, and TX audio are ready"
        }
        sendCIV(command: [0x03])
        sendCIV(command: [0x04])
    }

    private func sendLogin() {
        guard let settings else { return }
        loginSent = true
        tokenRequest = UInt16.random(in: 1...UInt16.max)
        var packet = basePacket(size: 128, on: .control)
        packet.writeUInt32BE(112, at: 16)
        packet[20] = 0x01
        packet[21] = 0x00
        packet.writeUInt16BE(authSequence, at: 22)
        authSequence &+= 1
        packet.writeUInt16LE(tokenRequest, at: 26)
        packet.writeBytes(Self.obfuscated(settings.username), at: 64, maximum: 16)
        packet.writeBytes(Self.obfuscated(password), at: 80, maximum: 16)
        packet.writeCString(settings.clientName.isEmpty ? "YAAM" : settings.clientName, at: 96, maximum: 16)
        sendTracked(packet, on: .control)
        publish(state: .authenticating, message: "Signing in to \(settings.model.rawValue)...")
    }

    private func sendToken(requestType: UInt8) {
        var packet = basePacket(size: 64, on: .control)
        packet.writeUInt32BE(48, at: 16)
        packet[20] = 0x01
        packet[21] = requestType
        packet.writeUInt16BE(authSequence, at: 22)
        authSequence &+= 1
        packet.writeUInt16LE(tokenRequest, at: 26)
        packet.writeUInt32LE(token, at: 28)
        packet.writeUInt16BE(0x0798, at: 36)
        sendTracked(packet, on: .control)
    }

    private func sendOpenCIV() {
        var packet = basePacket(size: 22, on: .civ)
        packet.writeUInt16LE(0x01C0, at: 16)
        packet.writeUInt16BE(civDataSequence, at: 19)
        packet[21] = 0x04
        civDataSequence &+= 1
        sendTracked(packet, on: .civ)
    }

    private func sendCIV(command: [UInt8]) {
        guard civReady, let model = settings?.model else { return }
        var payload = Data([0xFE, 0xFE, model.civAddress, 0xE0])
        payload.append(contentsOf: command)
        payload.append(0xFD)
        var packet = basePacket(size: 21, on: .civ)
        packet[16] = 0xC1
        packet.writeUInt16LE(UInt16(payload.count), at: 17)
        packet.writeUInt16BE(civDataSequence, at: 19)
        civDataSequence &+= 1
        packet.append(payload)
        packet.writeUInt32LE(UInt32(packet.count), at: 0)
        sendTracked(packet, on: .civ)
    }

    private func sendPTT(_ enabled: Bool) {
        sendCIV(command: [0x1C, 0x00, enabled ? 0x01 : 0x00])
    }

    private func receiveCIVPayload(_ data: Data) {
        guard data.count > 21 else { return }
        let payload = Data(data.dropFirst(21))
        guard let start = payload.range(of: Data([0xFE, 0xFE]))?.lowerBound,
              let end = payload[start...].firstIndex(of: 0xFD) else { return }
        let frame = Data(payload[start...end])
        guard frame.count >= 6 else { return }
        let command = frame[4]
        if (command == 0x00 || command == 0x03), frame.count >= 11 {
            let frequency = Self.frequencyFromBCD(Array(frame[5..<10]))
            DispatchQueue.main.async {
                let old = self.snapshot
                self.snapshot = IcomNetworkSnapshot(
                    frequencyHz: frequency,
                    mode: old?.mode ?? "USB-D",
                    updatedAt: Date()
                )
            }
        } else if command == 0x04, frame.count >= 7 {
            let mode = Self.modeName(frame[5])
            DispatchQueue.main.async {
                let old = self.snapshot
                self.snapshot = IcomNetworkSnapshot(
                    frequencyHz: old?.frequencyHz ?? 0,
                    mode: mode,
                    updatedAt: Date()
                )
            }
        }
    }

    private func receiveAudioPayload(_ data: Data) {
        guard data.count > 24 else { return }
        let byteCount = min(Int(data.uint16BE(at: 22)), data.count - 24)
        guard byteCount >= 2 else { return }
        let payload = data[24..<(24 + byteCount)]
        var samples: [Float] = []
        samples.reserveCapacity(byteCount / 2)
        var index = payload.startIndex
        while index + 1 < payload.endIndex {
            let raw = UInt16(payload[index]) | (UInt16(payload[index + 1]) << 8)
            samples.append(Float(Int16(bitPattern: raw)) / 32_768)
            index += 2
        }
        let receivedAt = Date()
        _audioSampleHandler?(samples, receivedAt)
        DispatchQueue.main.async {
            self.receivedAudioPackets += 1
            self.lastAudioAt = receivedAt
        }
    }

    private func sendAudio(_ samples: [Float], gain: Float) {
        guard audioReady, !samples.isEmpty else { return }
        var payload = Data(capacity: samples.count * 2)
        for sample in samples {
            let scaled = max(-1, min(1, sample * gain))
            let value = UInt16(bitPattern: Int16((scaled * 32_767).rounded()))
            payload.append(UInt8(value & 0xFF))
            payload.append(UInt8((value >> 8) & 0xFF))
        }
        var offset = 0
        while offset < payload.count {
            let end = min(payload.count, offset + 1_364)
            let part = payload[offset..<end]
            var packet = basePacket(size: 24, on: .audio)
            packet.writeUInt16LE(part.count == 160 ? 0x9781 : 0x0080, at: 16)
            packet.writeUInt16BE(audioDataSequence, at: 18)
            packet.writeUInt16BE(UInt16(part.count), at: 22)
            audioDataSequence &+= 1
            packet.append(part)
            packet.writeUInt32LE(UInt32(packet.count), at: 0)
            sendTracked(packet, on: .audio)
            offset = end
        }
    }

    private func sendControl(type: UInt16, tracked: Bool, sequence: UInt16, on stream: StreamKind) {
        guard socket(for: stream) != nil else { return }
        var packet = basePacket(size: 16, on: stream)
        packet.writeUInt16LE(type, at: 4)
        packet.writeUInt16LE(sequence, at: 6)
        tracked ? sendTracked(packet, on: stream) : socket(for: stream)?.send(packet)
    }

    private func sendPing(on stream: StreamKind) {
        var packet = basePacket(size: 21, on: stream)
        packet.writeUInt16LE(0x07, at: 4)
        packet.writeUInt16LE(nextPingSequence(for: stream), at: 6)
        packet[16] = 0
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let values = calendar.dateComponents(in: TimeZone.current, from: now)
        let milliseconds = UInt32(
            (((values.hour ?? 0) * 3600 + (values.minute ?? 0) * 60 + (values.second ?? 0)) * 1000)
                + ((values.nanosecond ?? 0) / 1_000_000)
        )
        packet.writeUInt32LE(milliseconds, at: 17)
        socket(for: stream)?.send(packet)
    }

    private func sendPingReply(_ received: Data, on stream: StreamKind) {
        var packet = basePacket(size: 21, on: stream)
        packet.writeUInt16LE(0x07, at: 4)
        packet.writeUInt16LE(received.uint16LE(at: 6), at: 6)
        packet[16] = 1
        packet.replaceSubrange(17..<21, with: received[17..<21])
        socket(for: stream)?.send(packet)
    }

    private func handleRetransmitRequest(_ request: Data, on stream: StreamKind) {
        if request.count == 16 {
            retransmit(sequence: request.uint16LE(at: 6), on: stream)
            return
        }

        var offset = 16
        while offset + 3 < request.count {
            let start = request.uint16LE(at: offset)
            let end = request.uint16LE(at: offset + 2)
            let count = min(Int(end &- start) + 1, 10)
            var sequence = start
            for _ in 0..<count {
                retransmit(sequence: sequence, on: stream)
                sequence &+= 1
            }
            offset += 4
        }
    }

    private func retransmit(sequence: UInt16, on stream: StreamKind) {
        let packet = cachedPacket(sequence: sequence, on: stream) ?? {
            var idle = basePacket(size: 16, on: stream)
            idle.writeUInt16LE(0, at: 4)
            idle.writeUInt16LE(sequence, at: 6)
            return idle
        }()
        // Icom clients repeat retransmits so one more dropped UDP datagram does
        // not leave the radio's short jitter buffer permanently incomplete.
        socket(for: stream)?.send(packet)
        socket(for: stream)?.send(packet)
    }

    private func sendTracked(_ original: Data, on stream: StreamKind) {
        var packet = original
        let sequence = nextSequence(for: stream)
        packet.writeUInt16LE(sequence, at: 6)
        cache(packet: packet, sequence: sequence, on: stream)
        socket(for: stream)?.send(packet)
    }

    private func cache(packet: Data, sequence: UInt16, on stream: StreamKind) {
        switch stream {
        case .control: controlTransmitCache.insert(packet, sequence: sequence)
        case .civ: civTransmitCache.insert(packet, sequence: sequence)
        case .audio: audioTransmitCache.insert(packet, sequence: sequence)
        }
    }

    private func cachedPacket(sequence: UInt16, on stream: StreamKind) -> Data? {
        switch stream {
        case .control: return controlTransmitCache.packet(for: sequence)
        case .civ: return civTransmitCache.packet(for: sequence)
        case .audio: return audioTransmitCache.packet(for: sequence)
        }
    }

    private func basePacket(size: Int, on stream: StreamKind) -> Data {
        var packet = Data(repeating: 0, count: size)
        packet.writeUInt32LE(UInt32(size), at: 0)
        packet.writeUInt32LE(socket(for: stream)?.clientID ?? 0, at: 8)
        packet.writeUInt32LE(remoteID(for: stream), at: 12)
        return packet
    }

    private func nextSequence(for stream: StreamKind) -> UInt16 {
        switch stream {
        case .control:
            defer { controlSequence &+= 1 }
            return controlSequence
        case .civ:
            defer { civSequence &+= 1 }
            return civSequence
        case .audio:
            defer { audioSequence &+= 1 }
            return audioSequence
        }
    }

    private func nextPingSequence(for stream: StreamKind) -> UInt16 {
        switch stream {
        case .control:
            defer { controlPingSequence &+= 1 }
            return controlPingSequence
        case .civ:
            defer { civPingSequence &+= 1 }
            return civPingSequence
        case .audio:
            defer { audioPingSequence &+= 1 }
            return audioPingSequence
        }
    }

    private func socket(for stream: StreamKind) -> IcomUDPSocket? {
        switch stream {
        case .control: return controlSocket
        case .civ: return civSocket
        case .audio: return audioSocket
        }
    }

    private func remoteID(for stream: StreamKind) -> UInt32 {
        switch stream {
        case .control: return controlRemoteID
        case .civ: return civRemoteID
        case .audio: return audioRemoteID
        }
    }

    private func setRemoteID(_ value: UInt32, for stream: StreamKind) {
        switch stream {
        case .control: controlRemoteID = value
        case .civ: civRemoteID = value
        case .audio: audioRemoteID = value
        }
    }

    private func publish(state newState: IcomNetworkConnectionState, message: String) {
        DispatchQueue.main.async {
            self.state = newState
            self.lastMessage = message
        }
    }

    private func fail(_ message: String, generation id: UUID) {
        guard generation == id, !isStopping else { return }
        stopNetworkState()
        DispatchQueue.main.async {
            guard self.publishedGeneration == id else { return }
            self.pttWatchdog?.cancel()
            self.pttWatchdog = nil
            self.state = .failed(message)
            self.lastMessage = message
            self.isTransmitting = false
            self.transmitArmed = false
        }
    }

    private func stopNetworkState() {
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        tokenTimer?.cancel()
        tokenTimer = nil
        pttWatchdog?.cancel()
        pttWatchdog = nil
        controlSocket?.close()
        civSocket?.close()
        audioSocket?.close()
        controlSocket = nil
        civSocket = nil
        audioSocket = nil
        controlRemoteID = 0
        civRemoteID = 0
        audioRemoteID = 0
        controlSequence = 0
        civSequence = 0
        audioSequence = 0
        controlPingSequence = 0
        civPingSequence = 0
        audioPingSequence = 0
        controlTransmitCache = TransmitPacketCache()
        civTransmitCache = TransmitPacketCache()
        audioTransmitCache = TransmitPacketCache()
        civDataSequence = 0
        audioDataSequence = 0
        authSequence = 0
        selectedCapability = nil
        loginSent = false
        streamRequested = false
        civReady = false
        audioReady = false
        password = ""
    }

    private static func frequencyBCD(_ frequencyHz: UInt64) -> [UInt8] {
        var remaining = frequencyHz
        return (0..<5).map { _ in
            let low = UInt8(remaining % 10)
            remaining /= 10
            let high = UInt8(remaining % 10)
            remaining /= 10
            return low | (high << 4)
        }
    }

    private static func frequencyFromBCD(_ bytes: [UInt8]) -> UInt64 {
        var multiplier: UInt64 = 1
        var result: UInt64 = 0
        for byte in bytes {
            result += UInt64(byte & 0x0F) * multiplier
            multiplier *= 10
            result += UInt64((byte >> 4) & 0x0F) * multiplier
            multiplier *= 10
        }
        return result
    }

    static func protocolSelfTest() -> Bool {
        civCodecSelfTest()
            && credentialBoundsSelfTest()
            && udpTransportSelfTest()
    }

    static func civCodecSelfTest() -> Bool {
        let frequencies: [UInt64] = [1_840_000, 7_074_000, 14_074_000, 50_313_000]
        return frequencies.allSatisfy { frequencyFromBCD(frequencyBCD($0)) == $0 }
    }

    static func credentialBoundsSelfTest() -> Bool {
        let boundedCredential = limitedUTF8("0123456789abcde\u{00E9}", maximumBytes: 16)
        return boundedCredential.utf8.count <= 16
            && !boundedCredential.isEmpty
    }

    /// Exercises the connected-UDP write path against a closed local endpoint.
    /// No credentials, radio commands, or network traffic leave this Mac.
    static func udpTransportSelfTest() -> Bool {
        (try? runUDPTransportSelfTest()) != nil
    }

    static func runUDPTransportSelfTest() throws {
        let testQueue = DispatchQueue(label: "YAAM.IcomNetworkRadio.UDPTransportSelfTest")
        let socket = try IcomUDPSocket(
            queue: testQueue,
            onData: { _ in },
            onError: { _ in }
        )
        try socket.connect(host: "127.0.0.1", port: 65_535)
        let probe = Data(repeating: 0, count: 16)
        for _ in 0..<6 {
            socket.send(probe)
            usleep(5_000)
        }
        socket.close()
        testQueue.sync {}
    }

    private static func limitedUTF8(_ value: String, maximumBytes: Int) -> String {
        guard maximumBytes > 0 else { return "" }
        var result = ""
        var byteCount = 0
        for character in value {
            let fragment = String(character)
            let fragmentCount = fragment.utf8.count
            guard byteCount + fragmentCount <= maximumBytes else { break }
            result.append(character)
            byteCount += fragmentCount
        }
        return result
    }

    private static func modeName(_ value: UInt8) -> String {
        switch value {
        case 0x00: return "LSB"
        case 0x01: return "USB"
        case 0x02: return "AM"
        case 0x03: return "CW"
        case 0x04: return "RTTY"
        case 0x05: return "FM"
        case 0x07: return "CW-R"
        case 0x08: return "RTTY-R"
        case 0x17: return "DV"
        default: return String(format: "Mode 0x%02X", value)
        }
    }

    private static func obfuscated(_ value: String) -> [UInt8] {
        let table: [UInt8] = Array(repeating: 0, count: 32) + [
            0x47, 0x5D, 0x4C, 0x42, 0x66, 0x20, 0x23, 0x46, 0x4E, 0x57, 0x45, 0x3D, 0x67, 0x76, 0x60, 0x41,
            0x62, 0x39, 0x59, 0x2D, 0x68, 0x7E, 0x7C, 0x65, 0x7D, 0x49, 0x29, 0x72, 0x73, 0x78, 0x21, 0x6E,
            0x5A, 0x5E, 0x4A, 0x3E, 0x71, 0x2C, 0x2A, 0x54, 0x3C, 0x3A, 0x63, 0x4F, 0x43, 0x75, 0x27, 0x79,
            0x5B, 0x35, 0x70, 0x48, 0x6B, 0x56, 0x6F, 0x34, 0x32, 0x6C, 0x30, 0x61, 0x6D, 0x7B, 0x2F, 0x4B, 0x64,
            0x38, 0x2B, 0x2E, 0x50, 0x40, 0x3F, 0x55, 0x33, 0x37, 0x25, 0x77, 0x24, 0x26, 0x74, 0x6A, 0x28, 0x53,
            0x4D, 0x69, 0x22, 0x5C, 0x44, 0x31, 0x36, 0x58, 0x3B, 0x7A, 0x51, 0x5F, 0x52
        ]
        return value.utf8.prefix(16).enumerated().map { index, byte in
            var position = Int(byte) + index
            if position > 126 { position = 32 + position % 127 }
            return table[position]
        }
    }
}

/// One connected UDP socket. Binding before connecting lets YAAM advertise its
/// local CI-V/audio ports in the Icom stream request without a port race.
nonisolated private final class IcomUDPSocket: @unchecked Sendable {
    let localPort: UInt16
    private(set) var clientID: UInt32 = 0

    private let queue: DispatchQueue
    private let onData: @Sendable (Data) -> Void
    private let onError: @Sendable (String) -> Void
    private let descriptor: Int32
    private var source: DispatchSourceRead?
    private var isConnected = false
    private let lock = NSLock()
    private var isClosed = false

    init(
        queue: DispatchQueue,
        onData: @escaping @Sendable (Data) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) throws {
        self.queue = queue
        self.onData = onData
        self.onError = onError
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw IcomNetworkError.socket("Unable to create UDP socket: \(String(cString: strerror(errno)))")
        }

        // A connected UDP socket can receive EPIPE after an ICMP rejection on
        // macOS. Keep that transport error local instead of terminating YAAM.
        var noSignal: Int32 = 1
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fd)
            throw IcomNetworkError.socket("Unable to protect UDP socket writes: \(message)")
        }
        descriptor = fd

        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bindResult = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw IcomNetworkError.socket("Unable to bind UDP socket: \(String(cString: strerror(errno)))")
        }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        localPort = UInt16(bigEndian: bound.sin_port)
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
    }

    deinit {
        close()
    }

    func connect(host: String, port: UInt16) throws {
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let address = result else {
            throw IcomNetworkError.socket("Unable to resolve \(host): \(String(cString: gai_strerror(status)))")
        }
        defer { freeaddrinfo(result) }
        guard Darwin.connect(descriptor, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0 else {
            throw IcomNetworkError.socket("Unable to connect UDP socket: \(String(cString: strerror(errno)))")
        }
        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        let addressValue = UInt32(bigEndian: local.sin_addr.s_addr)
        clientID = (((addressValue >> 8) & 0xFF) << 24)
            | ((addressValue & 0xFF) << 16)
            | UInt32(localPort)

        if source == nil {
            let fileDescriptor = descriptor
            let readSource = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            readSource.setEventHandler { [weak self] in self?.readAvailable() }
            readSource.setCancelHandler { Darwin.close(fileDescriptor) }

            lock.lock()
            guard !isClosed else {
                lock.unlock()
                readSource.resume()
                readSource.cancel()
                throw IcomNetworkError.disconnected
            }
            isConnected = true
            source = readSource
            readSource.resume()
            lock.unlock()
        }
    }

    func send(_ data: Data) {
        lock.lock()
        guard isConnected, !isClosed, !data.isEmpty else {
            lock.unlock()
            return
        }
        let result = data.withUnsafeBytes { bytes in
            Darwin.send(descriptor, bytes.baseAddress, bytes.count, 0)
        }
        let sendError = errno
        let shouldReport = result < 0
            && sendError != EWOULDBLOCK
            && sendError != EAGAIN
            && !isClosed
        lock.unlock()
        if shouldReport {
            onError("Icom UDP send failed: \(String(cString: strerror(sendError)))")
        }
    }

    func close() {
        lock.lock()
        guard !isClosed else { lock.unlock(); return }
        isClosed = true
        isConnected = false
        let readSource = source
        source = nil
        lock.unlock()
        if let readSource {
            readSource.cancel()
        } else {
            Darwin.close(descriptor)
        }
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 65_535)
        while true {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count > 0 {
                onData(Data(buffer.prefix(count)))
            } else if count == 0 {
                return
            } else {
                if errno != EWOULDBLOCK && errno != EAGAIN {
                    onError("Icom UDP receive failed: \(String(cString: strerror(errno)))")
                }
                return
            }
        }
    }
}

nonisolated private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint16BE(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    mutating func writeUInt16LE(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    mutating func writeUInt16BE(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8((value >> 8) & 0xFF)
        self[offset + 1] = UInt8(value & 0xFF)
    }

    mutating func writeUInt32LE(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xFF)
        self[offset + 1] = UInt8((value >> 8) & 0xFF)
        self[offset + 2] = UInt8((value >> 16) & 0xFF)
        self[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    mutating func writeUInt32BE(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8((value >> 24) & 0xFF)
        self[offset + 1] = UInt8((value >> 16) & 0xFF)
        self[offset + 2] = UInt8((value >> 8) & 0xFF)
        self[offset + 3] = UInt8(value & 0xFF)
    }

    mutating func writeBytes(_ bytes: [UInt8], at offset: Int, maximum: Int) {
        for (index, byte) in bytes.prefix(maximum).enumerated() { self[offset + index] = byte }
    }

    mutating func writeCString(_ value: String, at offset: Int, maximum: Int) {
        writeBytes(Array(value.utf8), at: offset, maximum: maximum)
    }

    func nullTerminatedString(in range: Range<Int>) -> String {
        let bytes = self[range].prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}
