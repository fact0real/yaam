//
//  IcomNetworkServer.swift
//  YAAM
//
//  Created by factoreal on 9/13/26.
//

import Darwin
import Foundation

// MARK: - Client Session Representation
nonisolated struct IcomClientSession: Identifiable, Sendable {
    let id: UInt32
    let remoteHost: String
    let controlPort: UInt16
    var civPort: UInt16
    var audioPort: UInt16
    var clientName: String
    var connectedAt: Date
    var lastKeepaliveAt: Date
    var pingRTTMs: Double
    var packetsReceived: UInt64
    var packetsSent: UInt64
    var isStreaming: Bool = false
    var sampleRate: Int = 48000
    var codec: UInt8 = 1
}

// MARK: - Icom LAN Protocol Server
nonisolated final class IcomNetworkServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.yaam.icom-server", qos: .userInteractive)

    // Configuration
    var controlPort: UInt16 = 50001
    var civPort: UInt16 = 50002
    var audioPort: UInt16 = 50003
    var username: String = "yaam"
    var password: String = "yaam"
    var radioModel: IcomNetworkModel = .ic705
    var radioName: String = "IC-705-NTE"

    // Callbacks to emulator engine
    var getFrequency: (@Sendable () -> UInt64)?
    var setFrequency: (@Sendable (UInt64) -> Void)?
    var getMode: (@Sendable () -> String)?
    var setMode: (@Sendable (String) -> Void)?
    var getVFO: (@Sendable () -> String)?
    var setVFO: (@Sendable (String) -> Void)?
    var getPTT: (@Sendable () -> Bool)?
    var setPTT: (@Sendable (Bool) -> Void)?
    var getSMeterBCD: (@Sendable () -> [UInt8])?
    var getPowerMeterBCD: (@Sendable () -> [UInt8])?
    var getSWRMeterBCD: (@Sendable () -> [UInt8])?
    var getALCMeterBCD: (@Sendable () -> [UInt8])?
    var setRFPowerWatts: (@Sendable (Double) -> Void)?
    var onClientTXAudioReceived: (@Sendable ([Float]) -> Void)?
    var onClientSessionChanged: (@Sendable ([IcomClientSession]) -> Void)?
    var onLogMessage: (@Sendable (String) -> Void)?

    // BSD Sockets
    private var controlSocketFd: Int32 = -1
    private var civSocketFd: Int32 = -1
    private var audioSocketFd: Int32 = -1

    private var controlReadSource: DispatchSourceRead?
    private var civReadSource: DispatchSourceRead?
    private var audioReadSource: DispatchSourceRead?

    // Active Session State
    private(set) var isRunning = false
    private let serverID: UInt32 = 0x5941414D // "YAAM" in ASCII
    private var currentSession: IcomClientSession?
    private var clientRemoteControlAddr: sockaddr_in?
    private var clientRemoteCivAddr: sockaddr_in?
    private var clientRemoteAudioAddr: sockaddr_in?
    private var clientSampleRate: UInt32 = 48000

    // Thread-safe multi-client endpoints
    private var endpointsLock = os_unfair_lock_s()
    private var _clientCivEndpoints: [UInt32: sockaddr_in] = [:]
    private var _clientAudioEndpoints: [UInt32: sockaddr_in] = [:]

    private var clientCivEndpointsList: [(UInt32, sockaddr_in)] {
        os_unfair_lock_lock(&endpointsLock)
        defer { os_unfair_lock_unlock(&endpointsLock) }
        return _clientCivEndpoints.map { ($0.key, $0.value) }
    }

    private var clientAudioEndpointsList: [(UInt32, sockaddr_in)] {
        os_unfair_lock_lock(&endpointsLock)
        defer { os_unfair_lock_unlock(&endpointsLock) }
        return _clientAudioEndpoints.map { ($0.key, $0.value) }
    }

    private func registerCivEndpoint(clientID: UInt32, addr: sockaddr_in) {
        os_unfair_lock_lock(&endpointsLock)
        _clientCivEndpoints[clientID] = addr
        os_unfair_lock_unlock(&endpointsLock)
    }

    private func registerAudioEndpoint(clientID: UInt32, addr: sockaddr_in) {
        os_unfair_lock_lock(&endpointsLock)
        _clientAudioEndpoints[clientID] = addr
        os_unfair_lock_unlock(&endpointsLock)
    }

    private func clearEndpoints() {
        os_unfair_lock_lock(&endpointsLock)
        _clientCivEndpoints.removeAll()
        _clientAudioEndpoints.removeAll()
        os_unfair_lock_unlock(&endpointsLock)
    }

    // Sequence numbers
    private var controlSequence: UInt16 = 1
    private var civSequence: UInt16 = 1
    private var audioSequence: UInt16 = 1
    private var civDataSequence: UInt16 = 0
    private var audioDataSequence: UInt16 = 0

    // Auth state
    private var currentAuthID = Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC])
    private var currentToken: UInt32 = 0x12345678
    private var lastClientTokenRequest: UInt16 = 0
    private var isCIVChannelOpen = false
    private var isAudioChannelOpen = false
    private var lastClientCIVAddress: UInt8 = 0xE0
    private var lastUsedRadioAddress: UInt8? = nil
    private var lastSessionNotificationTime = Date.distantPast
    private var lastStreamReplyTime = Date.distantPast

    private func notifySessionChanged(_ session: IcomClientSession, force: Bool = false) {
        let now = Date()
        if !force && now.timeIntervalSince(lastSessionNotificationTime) < 0.25 {
            return
        }
        lastSessionNotificationTime = now
        onClientSessionChanged?([session])
    }

    deinit {
        stop()
    }

    func start() throws {
        queue.sync {
            guard !isRunning else { return }
            do {
                controlSocketFd = try bindUDPSocket(port: controlPort)
                civSocketFd = try bindUDPSocket(port: civPort)
                audioSocketFd = try bindUDPSocket(port: audioPort)

                setupSocketReadSources()
                isRunning = true
                onLogMessage?("[IcomServer] Started on UDP Control:\(controlPort), CI-V:\(civPort), Audio:\(audioPort)")
            } catch {
                cleanupSockets()
                onLogMessage?("[IcomServer] Failed to bind: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        queue.sync {
            guard isRunning else { return }
            isRunning = false
            cleanupSockets()
            currentSession = nil
            clientRemoteControlAddr = nil
            clientRemoteCivAddr = nil
            clientRemoteAudioAddr = nil
            clearEndpoints()
            isCIVChannelOpen = false
            isAudioChannelOpen = false
            onClientSessionChanged?([])
            onLogMessage?("[IcomServer] Stopped")
        }
    }

    private func bindUDPSocket(port: UInt16) throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw NSError(domain: "IcomNetworkServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create UDP socket: \(String(cString: strerror(errno)))"])
        }

        var opt: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &opt, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindRes == 0 else {
            let msg = String(cString: strerror(errno))
            Darwin.close(fd)
            throw NSError(domain: "IcomNetworkServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind UDP port \(port): \(msg)"])
        }

        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        return fd
    }

    private func setupSocketReadSources() {
        // Control Socket
        let ctrlSource = DispatchSource.makeReadSource(fileDescriptor: controlSocketFd, queue: queue)
        ctrlSource.setEventHandler { [weak self] in self?.readControlData() }
        ctrlSource.resume()
        controlReadSource = ctrlSource

        // CI-V Socket
        let civSource = DispatchSource.makeReadSource(fileDescriptor: civSocketFd, queue: queue)
        civSource.setEventHandler { [weak self] in self?.readCIVData() }
        civSource.resume()
        civReadSource = civSource

        // Audio Socket
        let audioSource = DispatchSource.makeReadSource(fileDescriptor: audioSocketFd, queue: queue)
        audioSource.setEventHandler { [weak self] in self?.readAudioData() }
        audioSource.resume()
        audioReadSource = audioSource
    }

    private func cleanupSockets() {
        controlReadSource?.cancel()
        controlReadSource = nil
        civReadSource?.cancel()
        civReadSource = nil
        audioReadSource?.cancel()
        audioReadSource = nil

        if controlSocketFd >= 0 { Darwin.close(controlSocketFd); controlSocketFd = -1 }
        if civSocketFd >= 0 { Darwin.close(civSocketFd); civSocketFd = -1 }
        if audioSocketFd >= 0 { Darwin.close(audioSocketFd); audioSocketFd = -1 }
    }

    // MARK: - Control Channel Packet Processing
    private func readControlData() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var clientAddr = sockaddr_in()

        while true {
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.recvfrom(controlSocketFd, &buffer, buffer.count, 0, $0, &addrLen)
                }
            }

            guard count >= 16 else { break }
            let data = Data(buffer.prefix(count))
            handleControlPacket(data, from: clientAddr)
        }
    }

    private func handleControlPacket(_ data: Data, from clientAddr: sockaddr_in) {
        let clientPort = UInt16(bigEndian: clientAddr.sin_port)
        guard clientPort != controlPort && clientPort != civPort && clientPort != audioPort else { return }

        let type = data.uint16LE(at: 4)
        let clientID = data.uint32LE(at: 8)
        clientRemoteControlAddr = clientAddr

        var clientIPBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var sinAddr = clientAddr.sin_addr
        _ = inet_ntop(AF_INET, &sinAddr, &clientIPBuf, socklen_t(INET_ADDRSTRLEN))
        let clientIP = String(cString: clientIPBuf)

        var sessionChanged = false

        if currentSession == nil || currentSession?.id != clientID {
            let newSession = IcomClientSession(
                id: clientID,
                remoteHost: clientIP,
                controlPort: clientPort,
                civPort: 0,
                audioPort: 0,
                clientName: "Connecting...",
                connectedAt: Date(),
                lastKeepaliveAt: Date(),
                pingRTTMs: 1.0,
                packetsReceived: 1,
                packetsSent: 0
            )
            currentSession = newSession
            sessionChanged = true
            onLogMessage?("[IcomServer] New client handshake from \(clientIP):\(clientPort) (ID: 0x\(String(format: "%08X", clientID)))")
        } else {
            currentSession?.packetsReceived += 1
            currentSession?.lastKeepaliveAt = Date()
        }

        // Handle Packet Types
        switch type {
        case 0x03: // Open Channel Request / Discovery Probe
            sendControlReply(type: 0x04, to: clientAddr, clientID: clientID)
            sendControlReply(type: 0x06, to: clientAddr, clientID: clientID)
            onLogMessage?("[IcomServer] Responded Type 0x04 & 0x06 to discovery probe from \(clientIP)")

        case 0x06: // Handshake Confirm
            onLogMessage?("[IcomServer] Client confirmed control handshake")
            sendControlReply(type: 0x06, to: clientAddr, clientID: clientID)

        case 0x07: // Ping Request
            if data.count == 21 {
                handlePing(data, onFd: controlSocketFd, to: clientAddr)
            }

        case 0x00: // Keepalive or Login or Stream request
            if data.count == 128 {
                handleLogin(data, from: clientAddr, clientID: clientID)
            } else if data.count == 144 {
                handleStreamRequest(data, from: clientAddr, clientID: clientID)
            } else if data.count == 64 {
                // Token renewal / Auth packet
                handleTokenRenewal(data, from: clientAddr, clientID: clientID)
            } else if data.count == 16 {
                // Pkt0 idle keepalive
                currentSession?.lastKeepaliveAt = Date()
            }

        case 0x05: // Disconnect / Close Session
            onLogMessage?("[IcomServer] Client disconnected: \(clientIP)")
            currentSession = nil
            onClientSessionChanged?([])

        default:
            break
        }

        // Only notify UI if a new session was actually created
        if sessionChanged, let session = currentSession {
            onClientSessionChanged?([session])
        }
    }

    private func handleLogin(_ data: Data, from clientAddr: sockaddr_in, clientID: UInt32) {
        let clientName = data.nullTerminatedString(in: 96..<112)
        currentSession?.clientName = clientName.isEmpty ? "wfview/Icom" : clientName
        onLogMessage?("[IcomServer] Login request from client '\(currentSession?.clientName ?? "Client")'")

        // Extract client's token request sequence
        let clientTokenRequest = data.uint16LE(at: 26)
        self.lastClientTokenRequest = clientTokenRequest

        // Build 96-byte Login Reply
        var reply = Data(repeating: 0, count: 96)
        reply.writeUInt32LE(96, at: 0)
        reply.writeUInt16LE(0x00, at: 4)
        reply.writeUInt16LE(nextControlSequence(), at: 6)
        reply.writeUInt32LE(serverID, at: 8)
        reply.writeUInt32LE(clientID, at: 12)

        reply.writeUInt32BE(80, at: 16)
        reply[20] = 0x01
        reply[21] = 0x00
        reply.writeUInt16BE(0x0030, at: 22)
        reply.writeUInt16LE(clientTokenRequest, at: 26)
        reply.writeUInt32LE(currentToken, at: 28)
        reply.writeUInt32LE(0, at: 48) // Error code = 0 (Success)

        sendUDPPacket(reply, on: controlSocketFd, to: clientAddr)
        currentSession?.packetsSent += 1

        // Send Radio Capabilities & Availability
        sendRadioCapabilities(to: clientAddr, clientID: clientID)
        sendRadioAvailability(to: clientAddr, clientID: clientID)

        if let session = currentSession {
            notifySessionChanged(session)
        }
    }

    private func sendRadioCapabilities(to clientAddr: sockaddr_in, clientID: UInt32) {
        // Length = 66 (header) + 102 (capability) = 168 bytes
        let totalSize = 168
        var packet = Data(repeating: 0, count: totalSize)
        packet.writeUInt32LE(UInt32(totalSize), at: 0)
        packet.writeUInt16LE(0x00, at: 4)
        packet.writeUInt16LE(nextControlSequence(), at: 6)
        packet.writeUInt32LE(serverID, at: 8)
        packet.writeUInt32LE(clientID, at: 12)
        packet.writeUInt32BE(152, at: 16) // payloadsize = 168 - 16 = 152 BE
        packet[20] = 0x02 // requestreply = 0x02
        packet[21] = 0x02 // requesttype = 0x02
        packet.writeUInt16LE(lastClientTokenRequest, at: 26)
        packet.writeUInt32LE(currentToken, at: 28)
        packet.writeUInt16BE(1, at: 64) // numradios = 1 BE

        let offset = 66
        // Capability Block (102 bytes):
        let identityData = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        packet.replaceSubrange(offset..<(offset + 16), with: identityData)
        packet.writeCString(radioName, at: offset + 16, maximum: 32)
        packet.writeCString("ICOM_VAUDIO", at: offset + 48, maximum: 32)
        packet.writeUInt16BE(0x073f, at: offset + 80) // Ethernet connection type
        packet[offset + 82] = radioModel.civAddress
        packet.writeUInt16BE(0x8b01, at: offset + 83) // All RX sample rates
        packet.writeUInt16BE(0x0200, at: offset + 85) // TX sample rate
        packet.writeUInt32BE(115200, at: offset + 90) // Baud rate

        sendUDPPacket(packet, on: controlSocketFd, to: clientAddr)
        currentSession?.packetsSent += 1
    }

    private func sendRadioAvailability(to clientAddr: sockaddr_in, clientID: UInt32) {
        var packet = Data(repeating: 0, count: 144)
        packet.writeUInt32LE(144, at: 0)
        packet.writeUInt16LE(0x00, at: 4)
        packet.writeUInt16LE(nextControlSequence(), at: 6)
        packet.writeUInt32LE(serverID, at: 8)
        packet.writeUInt32LE(clientID, at: 12)
        packet.writeUInt32BE(128, at: 16) // payloadsize = 144 - 16 = 128 BE
        packet[20] = 0x03 // requestreply = 0x03
        packet[21] = 0x00 // requesttype = 0x00
        packet.writeUInt16LE(lastClientTokenRequest, at: 26)
        packet.writeUInt32LE(currentToken, at: 28)

        let identityData = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        packet.replaceSubrange(32..<48, with: identityData)
        packet.writeCString(radioName, at: 64, maximum: 32)
        packet.writeUInt32LE(0, at: 96) // Busy flag = 0 (Free / Available)

        packet.writeUInt32LE(UInt32(civPort), at: 124)
        packet.writeUInt32LE(UInt32(audioPort), at: 128)

        sendUDPPacket(packet, on: controlSocketFd, to: clientAddr)
        currentSession?.packetsSent += 1
    }

    private func extractSafePort(at offset: Int, in data: Data, fallback: UInt16) -> UInt16 {
        guard offset + 4 <= data.count else { return fallback }
        let leVal = data.uint32LE(at: offset)
        let beVal = data.uint32BE(at: offset)

        if leVal >= 1024 && leVal <= 65535 {
            return UInt16(leVal)
        }
        if beVal >= 1024 && beVal <= 65535 {
            return UInt16(beVal)
        }
        let u16le = data.uint16LE(at: offset)
        if u16le >= 1024 {
            return u16le
        }
        let u16be = data.uint16BE(at: offset)
        if u16be >= 1024 {
            return u16be
        }
        let masked = UInt16(leVal & 0xFFFF)
        return (masked >= 1024) ? masked : fallback
    }

    private func handleStreamRequest(_ data: Data, from clientAddr: sockaddr_in, clientID: UInt32) {
        let clientCIVPort = extractSafePort(at: 124, in: data, fallback: 0)
        let clientAudioPort = extractSafePort(at: 128, in: data, fallback: 0)

        if clientCIVPort != 0 && clientCIVPort != civPort && clientCIVPort != controlPort && clientCIVPort != audioPort {
            currentSession?.civPort = clientCIVPort
            var clientCivAddr = clientAddr
            clientCivAddr.sin_port = clientCIVPort.bigEndian
            clientRemoteCivAddr = clientCivAddr
            registerCivEndpoint(clientID: clientID, addr: clientCivAddr)
            isCIVChannelOpen = true
        }

        if clientAudioPort != 0 && clientAudioPort != audioPort && clientAudioPort != controlPort && clientAudioPort != civPort {
            currentSession?.audioPort = clientAudioPort
            var clientAudioAddr = clientAddr
            clientAudioAddr.sin_port = clientAudioPort.bigEndian
            clientRemoteAudioAddr = clientAudioAddr
            registerAudioEndpoint(clientID: clientID, addr: clientAudioAddr)
            isAudioChannelOpen = true
        }

        if data.count >= 120 {
            let beRate = data.uint32BE(at: 116)
            let leRate = data.uint32LE(at: 116)
            if [8000, 12000, 16000, 24000, 48000].contains(beRate) {
                clientSampleRate = beRate
            } else if [8000, 12000, 16000, 24000, 48000].contains(leRate) {
                clientSampleRate = leRate
            }
        }
        let rxCodec = (data.count > 114) ? data[114] : 1
        currentSession?.sampleRate = Int(clientSampleRate)
        currentSession?.codec = rxCodec
        onLogMessage?("[IcomServer] Stream request: rxCodec=\(rxCodec), sampleRate=\(clientSampleRate), CIVPort=\(clientCIVPort), AudioPort=\(clientAudioPort)")

        let clientInnerSeq = data.uint16LE(at: 22)
        let clientTokReq = data.uint16LE(at: 26)
        if clientTokReq != 0 {
            lastClientTokenRequest = clientTokReq
        }
        let clientGuid: Data
        if data.count >= 48 {
            clientGuid = data.subdata(in: 32..<48)
        } else {
            clientGuid = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10])
        }

        // 1. Send 80-byte Status packet FIRST (as per Icom LAN protocol & wfview icomServer::sendStatus)
        var statusPkt = Data(repeating: 0, count: 80)
        statusPkt.writeUInt32LE(80, at: 0)
        statusPkt.writeUInt16LE(0x00, at: 4)
        statusPkt.writeUInt16LE(nextControlSequence(), at: 6)
        statusPkt.writeUInt32LE(serverID, at: 8)
        statusPkt.writeUInt32LE(clientID, at: 12)
        statusPkt.writeUInt32BE(64, at: 16) // payloadsize = 80 - 16 = 64 BE
        statusPkt[20] = 0x02 // requestreply = 0x02
        statusPkt[21] = 0x03 // requesttype = 0x03
        statusPkt.writeUInt16LE(clientInnerSeq, at: 22)
        statusPkt.writeUInt16LE(clientTokReq, at: 26)
        statusPkt.writeUInt32LE(currentToken, at: 28)
        statusPkt.replaceSubrange(32..<48, with: clientGuid)
        statusPkt.writeUInt32LE(0, at: 48) // Error code = 0 (Success)
        statusPkt[64] = 0 // disc = 0 (Connected)
        statusPkt.writeUInt16BE(civPort, at: 66) // Radio CIV Port (BE)
        statusPkt.writeUInt16BE(audioPort, at: 70) // Radio Audio Port (BE)

        let wasStreaming = currentSession?.isStreaming ?? false
        let now = Date()

        if wasStreaming {
            // Guard against rapid stream request re-transmissions
            guard now.timeIntervalSince(lastStreamReplyTime) >= 0.25 else {
                return
            }
            lastStreamReplyTime = now

            // When already streaming, only re-send status confirmation.
            // DO NOT send connInfoPkt again because SDR-Control re-triggers sendRequestStream upon receiving connInfo!
            sendUDPPacket(statusPkt, on: controlSocketFd, to: clientAddr)
            currentSession?.packetsSent += 1
            return
        }

        lastStreamReplyTime = now
        currentSession?.isStreaming = true

        sendUDPPacket(statusPkt, on: controlSocketFd, to: clientAddr)
        currentSession?.packetsSent += 1

        // 2. Send 144-byte ConnectionInfo packet SECOND (as per icomServer::sendConnectionInfo)
        var connInfoPkt = Data(repeating: 0, count: 144)
        connInfoPkt.writeUInt32LE(144, at: 0)
        connInfoPkt.writeUInt16LE(0x00, at: 4)
        connInfoPkt.writeUInt16LE(nextControlSequence(), at: 6)
        connInfoPkt.writeUInt32LE(serverID, at: 8)
        connInfoPkt.writeUInt32LE(clientID, at: 12)
        connInfoPkt.writeUInt32BE(128, at: 16) // payloadsize = 144 - 16 = 128 BE
        connInfoPkt[20] = 0x03 // requestreply = 0x03
        connInfoPkt[21] = 0x00 // requesttype = 0x00
        connInfoPkt.writeUInt16LE(clientTokReq, at: 26)
        connInfoPkt.writeUInt32LE(currentToken, at: 28)
        connInfoPkt.replaceSubrange(32..<48, with: clientGuid)

        // Radio name at offset 64
        connInfoPkt.writeCString(radioName, at: 64, maximum: 32)
        // Busy = 1 at offset 96 (streaming to this client)
        connInfoPkt.writeUInt32LE(1, at: 96)
        // Client computer name at offset 100
        let clientComputer = currentSession?.clientName ?? "Client"
        connInfoPkt.writeCString(clientComputer, at: 100, maximum: 16)
        // Radio ports at offset 124 & 128
        connInfoPkt.writeUInt32LE(UInt32(civPort), at: 124)
        connInfoPkt.writeUInt32LE(UInt32(audioPort), at: 128)
        // Client IP at offset 132
        var ipBytes = clientAddr.sin_addr.s_addr
        withUnsafeBytes(of: &ipBytes) { raw in
            connInfoPkt.replaceSubrange(132..<136, with: raw.prefix(4))
        }

        sendUDPPacket(connInfoPkt, on: controlSocketFd, to: clientAddr)
        currentSession?.packetsSent += 1

        onLogMessage?("[IcomServer] Stream approved: CI-V:\(civPort), Audio:\(audioPort)")
        if let session = currentSession {
            notifySessionChanged(session, force: true)
        }
    }

    private func handleTokenRenewal(_ data: Data, from clientAddr: sockaddr_in, clientID: UInt32) {
        var reply = Data(repeating: 0, count: 64)
        reply.writeUInt32LE(64, at: 0)
        reply.writeUInt16LE(0x00, at: 4)
        reply.writeUInt16LE(nextControlSequence(), at: 6)
        reply.writeUInt32LE(serverID, at: 8)
        reply.writeUInt32LE(clientID, at: 12)

        reply[16] = 0x00
        reply[17] = 0x00
        reply[18] = 0x00
        reply[19] = 0x30
        reply[20] = 0x02
        let magic: UInt8 = (data.count > 21) ? data[21] : 0x05
        reply[21] = magic

        // Echo client's inner sequence numbers if present
        if data.count >= 26 {
            reply[22] = data[22]
            reply[23] = data[23]
            reply[24] = data[24]
            reply[25] = data[25]
        }

        let clientTokReq = data.uint16LE(at: 26)
        if clientTokReq != 0 {
            lastClientTokenRequest = clientTokReq
        }
        reply.writeUInt16LE(clientTokReq, at: 26)
        reply.writeUInt32LE(currentToken, at: 28)

        if data.count >= 48 {
            reply.replaceSubrange(32..<48, with: data[32..<48])
        }

        reply.writeUInt32LE(0, at: 48) // OK
        sendUDPPacket(reply, on: controlSocketFd, to: clientAddr)
        currentSession?.packetsSent += 1
    }

    // MARK: - CI-V Channel Packet Processing
    private func readCIVData() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var clientAddr = sockaddr_in()

        while true {
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.recvfrom(civSocketFd, &buffer, buffer.count, 0, $0, &addrLen)
                }
            }

            guard count >= 16 else { break }
            let data = Data(buffer.prefix(count))
            handleCIVPacket(data, from: clientAddr)
        }
    }

    private func handleCIVPacket(_ data: Data, from clientAddr: sockaddr_in) {
        let clientPort = UInt16(bigEndian: clientAddr.sin_port)
        guard clientPort != civPort && clientPort != audioPort && clientPort != controlPort else { return }

        let type = data.uint16LE(at: 4)
        let clientID = data.uint32LE(at: 8)
        clientRemoteCivAddr = clientAddr
        registerCivEndpoint(clientID: clientID, addr: clientAddr)
        isCIVChannelOpen = true
        currentSession?.civPort = clientPort

        if type == 0x03 {
            sendControlReply(type: 0x04, on: civSocketFd, to: clientAddr, clientID: clientID)
            sendControlReply(type: 0x06, on: civSocketFd, to: clientAddr, clientID: clientID)
            return
        } else if type == 0x06 {
            isCIVChannelOpen = true
            sendControlReply(type: 0x06, on: civSocketFd, to: clientAddr, clientID: clientID)
            return
        } else if type == 0x07 {
            handlePing(data, onFd: civSocketFd, to: clientAddr)
            return
        }

        // CI-V frame check
        if data.count > 21, data[16] == 0xC1 {
            let payload = Data(data.dropFirst(21))
            handleCIVPayload(payload, from: clientAddr, clientID: clientID)
        } else if data.count == 22, data[16] == 0xC0 {
            // Channel open acknowledge
            isCIVChannelOpen = true
            var ack = data
            ack.writeUInt32LE(serverID, at: 8)
            ack.writeUInt32LE(clientID, at: 12)
            sendUDPPacket(ack, on: civSocketFd, to: clientAddr)
        } else if type == 0x00, data.count == 16 {
            // CI-V pkt0 idle keepalive
            currentSession?.lastKeepaliveAt = Date()
        }
    }

    private func handleCIVPayload(_ payload: Data, from clientAddr: sockaddr_in, clientID: UInt32) {
        var searchOffset = payload.startIndex
        while searchOffset < payload.endIndex {
            guard let startRange = payload[searchOffset...].range(of: Data([0xFE, 0xFE])) else { break }
            guard let end = payload[startRange.lowerBound...].firstIndex(of: 0xFD) else { break }
            let frame = Array(payload[startRange.lowerBound...end])
            searchOffset = end + 1
            guard frame.count >= 5 else { continue }
            processSingleCIVFrame(frame, from: clientAddr, clientID: clientID)
        }
    }

    private func processSingleCIVFrame(_ frame: [UInt8], from clientAddr: sockaddr_in, clientID: UInt32) {
        let toAddr = frame[2]
        let fromAddr = frame[3]
        let command = frame[4]
        // In an emulator, adapt to whichever address the client uses (0x00 broadcast or model address)
        guard toAddr != fromAddr else { return }
        if fromAddr != 0x00 && fromAddr != radioModel.civAddress {
            lastClientCIVAddress = fromAddr
        }
        if toAddr != 0x00 && toAddr != 0xE0 && toAddr != fromAddr {
            lastUsedRadioAddress = toAddr
        }
        let radioAddr = (toAddr == 0x00) ? (lastUsedRadioAddress ?? radioModel.civAddress) : toAddr

        // Extract payload bytes strictly between command (index 4) and terminator 0xFD
        let payload: [UInt8]
        if frame.count > 6 && frame[frame.count - 1] == 0xFD {
            payload = Array(frame[5 ..< (frame.count - 1)])
        } else if frame.count == 6 && frame[5] == 0xFD {
            payload = []
        } else if frame.count > 5 {
            payload = Array(frame[5...])
        } else {
            payload = []
        }

        var replyFrame: [UInt8] = []

        switch command {
        case 0x00: // Transceive Frequency Broadcast from client
            if payload.count >= 6 && payload[0] <= 0x01 {
                let freq = Self.frequencyFromBCD(Array(payload[1..<6]))
                setFrequency?(freq)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            } else if payload.count >= 5 {
                let freq = Self.frequencyFromBCD(Array(payload.prefix(5)))
                setFrequency?(freq)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            }

        case 0x01: // Transceive Mode Broadcast from client
            if !payload.isEmpty {
                let code = payload[0]
                var modeName = Self.modeName(code)
                if payload.count >= 3 && payload[2] > 0 { // Data mode byte
                    if modeName == "USB" { modeName = "USB-D" }
                    else if modeName == "LSB" { modeName = "LSB-D" }
                }
                setMode?(modeName)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            }

        case 0x03: // Read Operating Frequency
            let freq = getFrequency?() ?? 14_074_000
            let bcd = Self.frequencyBCD(freq)
            replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x03] + bcd + [0xFD]

        case 0x05: // Set Operating Frequency
            if payload.count >= 6 && payload[0] <= 0x01 {
                let freq = Self.frequencyFromBCD(Array(payload[1..<6]))
                setFrequency?(freq)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            } else if payload.count >= 5 {
                let freq = Self.frequencyFromBCD(Array(payload.prefix(5)))
                setFrequency?(freq)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            }

        case 0x04: // Read Operating Mode
            let mode = getMode?() ?? "USB-D"
            let modeCode: UInt8 = Self.modeCode(from: mode)
            let filter: UInt8 = 0x01
            replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x04, modeCode, filter, 0xFD]

        case 0x06: // Set Operating Mode
            if !payload.isEmpty {
                let code = payload[0]
                var modeName = Self.modeName(code)
                if payload.count >= 3 && payload[2] > 0 { // Data mode byte
                    if modeName == "USB" { modeName = "USB-D" }
                    else if modeName == "LSB" { modeName = "LSB-D" }
                }
                setMode?(modeName)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            }

        case 0x0F: // Split and Duplex state
            if payload.isEmpty {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x0F, 0x00, 0xFD] // Split OFF
            } else if payload.count == 1 {
                // Set split state (00 = OFF, 01 = ON)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            } else {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x0F, 0x00, 0xFD]
            }

        case 0x14: // Read / Set Levels (AF Gain, RF Gain, SQL, RF Power, Mic Gain, Notch, PBT)
            if payload.count == 1 {
                let subCmd = payload[0]
                switch subCmd {
                case 0x01: // AF Gain (volume) ~ 50%
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x14, 0x01, 0x01, 0x28, 0xFD]
                case 0x02: // RF Gain ~ 100%
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x14, 0x02, 0x02, 0x55, 0xFD]
                case 0x03: // SQL (Squelch) ~ 0
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x14, 0x03, 0x00, 0x00, 0xFD]
                case 0x07: // Manual Notch Level (center = 0x01, 0x28)
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x14, 0x07, 0x01, 0x28, 0xFD]
                case 0x08: // Twin PBT 1 / Filter (center = 0x01, 0x28)
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x14, 0x08, 0x01, 0x28, 0xFD]
                case 0x0A: // RF Power Setting ~ 100%
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x14, 0x0A, 0x02, 0x55, 0xFD]
                case 0x0B: // Mic Gain ~ 50%
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x14, 0x0B, 0x01, 0x28, 0xFD]
                default:
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x14, subCmd, 0x01, 0x28, 0xFD]
                }
            } else if payload.count >= 3 {
                let subCmd = payload[0]
                if subCmd == 0x0A {
                    let bcd0 = Double((payload[1] >> 4) * 10 + (payload[1] & 0x0F))
                    let bcd1 = Double((payload[2] >> 4) * 10 + (payload[2] & 0x0F))
                    let level = bcd0 * 100.0 + bcd1
                    let watts = min(100.0, max(0.0, (level / 255.0) * 100.0))
                    setRFPowerWatts?(watts)
                }
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            } else {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            }

        case 0x15: // Meter Readings (high frequency polling - no logging)
            if !payload.isEmpty {
                let subCmd = payload[0]
                let bcd: [UInt8]
                switch subCmd {
                case 0x02: bcd = getSMeterBCD?() ?? [0x00, 0x80] // S-Meter
                case 0x11: bcd = getPowerMeterBCD?() ?? [0x00, 0x00] // Po
                case 0x12: bcd = getSWRMeterBCD?() ?? [0x00, 0x10] // SWR
                case 0x13: bcd = getALCMeterBCD?() ?? [0x00, 0x00] // ALC
                case 0x15: bcd = [0x00, 0x00] // COMP
                case 0x16: bcd = [0x01, 0x38] // VD (13.8 V)
                case 0x17: bcd = [0x00, 0x50] // Id (0.5 A)
                default: bcd = [0x00, 0x00]
                }
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x15, subCmd] + bcd + [0xFD]
            }

        case 0x16: // Preamp, AGC, NB, NR, Notch, IP+
            if payload.count == 1 {
                let subCmd = payload[0]
                switch subCmd {
                case 0x02: // Preamp: 01 = P.AMP 1
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x16, 0x02, 0x01, 0xFD]
                case 0x12: // AGC: 01 = FAST, 02 = MID, 03 = SLOW
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x16, 0x12, 0x01, 0xFD]
                case 0x22: // Noise Blanker: 00 = OFF
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x16, 0x22, 0x00, 0xFD]
                case 0x40: // Noise Reduction: 00 = OFF
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x16, 0x40, 0x00, 0xFD]
                case 0x48: // Auto Notch: 00 = OFF
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x16, 0x48, 0x00, 0xFD]
                case 0x56: // IP+ (Interception Point Plus): 00 = OFF
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x16, 0x56, 0x00, 0xFD]
                default:
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x16, subCmd, 0x00, 0xFD]
                }
            } else {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            }

        case 0x07: // Select VFO A / B
            if !payload.isEmpty {
                let vfoCode = payload[0]
                if vfoCode == 0x00 {
                    setVFO?("VFO A")
                } else if vfoCode == 0x01 {
                    setVFO?("VFO B")
                } else if vfoCode == 0xD0 {
                    // Exchange VFO A / B
                    let current = getVFO?() ?? "VFO A"
                    setVFO?(current == "VFO A" ? "VFO B" : "VFO A")
                }
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            } else {
                let current = getVFO?() ?? "VFO A"
                let vfoByte: UInt8 = (current == "VFO B") ? 0x01 : 0x00
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x07, vfoByte, 0xFD]
            }

        case 0x08: // Select Memory Mode
            replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]

        case 0x19: // Transceiver ID
            replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x19, 0x00, radioAddr, 0xFD]

        case 0x1A: // Extended commands (05 = Settings, 06 = Data mode & Filter, 03 = Filter shape)
            if payload.count >= 1 && payload[0] == 0x05 {
                // Command 1A 05: Radio settings & modulation queries
                if payload.count >= 3 {
                    let s1 = payload[1]
                    let s2 = payload[2]
                    if s1 == 0x00 && s2 == 0x85 {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1A, 0x05, 0x00, 0x85, 0x05, 0xFD]
                    } else if s1 == 0x00 && s2 == 0x84 {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1A, 0x05, 0x00, 0x84, 0x00, 0xFD]
                    } else if s1 == 0x00 && s2 == 0x86 {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1A, 0x05, 0x00, 0x86, 0x00, 0xFD]
                    } else if s1 == 0x00 && s2 == 0x87 {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1A, 0x05, 0x00, 0x87, 0x00, 0xFD]
                    } else if s1 == 0x00 && s2 == 0x91 {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1A, 0x05, 0x00, 0x91, radioAddr, 0xFD]
                    } else if s1 == 0x00 && s2 == 0x92 {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1A, 0x05, 0x00, 0x92, 0x01, 0xFD]
                    } else if s1 == 0x00 && s2 == 0x93 {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1A, 0x05, 0x00, 0x93, 0x00, 0xFD]
                    } else {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1A, 0x05, s1, s2, 0x00, 0xFD]
                    }
                } else {
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
                }
            } else if payload.count >= 1 && payload[0] == 0x06 {
                // Command 1A 06: Data Mode and Filter query / set
                if payload.count == 1 {
                    let currentMode = getMode?() ?? "USB-D"
                    let isData = currentMode.contains("-D") || currentMode == "DIGI"
                    let dataModeByte: UInt8 = isData ? 0x01 : 0x00
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1A, 0x06, dataModeByte, 0x01, 0xFD]
                } else if payload.count >= 2 {
                    let dataModeByte = payload[1]
                    var currentMode = getMode?() ?? "USB"
                    if dataModeByte > 0 {
                        if currentMode == "USB" { currentMode = "USB-D" }
                    } else {
                        if currentMode == "USB-D" { currentMode = "USB" }
                    }
                    setMode?(currentMode)
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
                }
            } else if payload.count >= 1 && payload[0] == 0x03 {
                // Command 1A 03: IF Filter shape or selection (FIL1 = 0x01)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1A, 0x03, 0x01, 0xFD]
            } else {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
            }

        case 0x1C: // Transceiver Control (PTT, Tuner, Antenna)
            if payload.count >= 2 && payload[0] == 0x00 {
                let isTX = payload[1] == 0x01
                setPTT?(isTX)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            } else if payload.count == 1 && payload[0] == 0x00 {
                let isTX = getPTT?() ?? false
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1C, 0x00, isTX ? 0x01 : 0x00, 0xFD]
            } else if payload.count == 1 && payload[0] == 0x01 {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1C, 0x01, 0x01, 0xFD]
            } else if payload.count == 1 && payload[0] == 0x02 {
                // Antenna 1 / Tuner status
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x1C, 0x02, 0x00, 0xFD]
            } else {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
            }

        case 0x25: // Selected VFO / MAIN receiver frequency (Query & Set)
            if payload.isEmpty {
                let freq = getFrequency?() ?? 14_074_000
                let bcd = Self.frequencyBCD(freq)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x25] + bcd + [0xFD]
            } else if payload.count == 1 {
                let sub = payload[0]
                let freq = getFrequency?() ?? 14_074_000
                let bcd = Self.frequencyBCD(freq)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x25, sub] + bcd + [0xFD]
            } else if payload.count >= 6 {
                // Set with receiver sub-cmd: 25 00/01 <5-byte BCD>
                let freq = Self.frequencyFromBCD(Array(payload[1..<6]))
                setFrequency?(freq)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            } else if payload.count == 5 {
                // Set direct: 25 <5-byte BCD>
                let freq = Self.frequencyFromBCD(payload)
                setFrequency?(freq)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            } else {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
            }

        case 0x26: // Selected VFO / MAIN receiver operating mode (Query & Set)
            let currentMode = getMode?() ?? "USB-D"
            let isData = currentMode.contains("-D") || currentMode == "DIGI" || currentMode == "PKTUSB"
            let modeCode = Self.modeCode(from: currentMode)
            let dataByte: UInt8 = isData ? 0x01 : 0x00
            let filter: UInt8 = 0x01

            if payload.isEmpty {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x26, 0x00, modeCode, dataByte, filter, 0xFD]
            } else if payload.count == 1 {
                let sub = payload[0]
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x26, sub, modeCode, dataByte, filter, 0xFD]
            } else if payload.count >= 2 {
                let modeByte: UInt8
                let inDataByte: UInt8
                if payload[0] <= 0x01 && payload.count >= 3 {
                    modeByte = payload[1]
                    inDataByte = payload[2]
                } else {
                    modeByte = payload[0]
                    inDataByte = (payload.count >= 2) ? payload[1] : 0x00
                }
                var modeName = Self.modeName(modeByte)
                if inDataByte > 0 {
                    if modeName == "USB" { modeName = "USB-D" }
                    else if modeName == "LSB" { modeName = "LSB-D" }
                }
                setMode?(modeName)
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
            } else {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
            }

        case 0x27: // Icom Scope & Spectrum Commands (SDR-Control / wfview)
            if !payload.isEmpty {
                let scopeSub = payload[0]
                switch scopeSub {
                case 0x10: // Scope waveform data request / output enable
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD] // ACK
                case 0x11: // Scope ON/OFF
                    if payload.count == 1 {
                        // Query: reply Scope is ON (01)
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x27, 0x11, 0x01, 0xFD]
                    } else {
                        // Set: ACK
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
                    }
                case 0x14: // Scope Edge query (dynamic based on tuned frequency)
                    let currentFreq = getFrequency?() ?? 14_074_000
                    let span: UInt64 = 100_000 // ±100 kHz span around center
                    let lower = (currentFreq >= span) ? (currentFreq - span) : 100_000
                    let upper = currentFreq + span
                    let lowerBCD = Self.frequencyBCD(lower)
                    let upperBCD = Self.frequencyBCD(upper)
                    let edgeNum = (payload.count >= 2) ? payload[1] : 0x01
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x27, 0x14, edgeNum] + lowerBCD + upperBCD + [0xFD]
                case 0x15: // Scope Span query (Span ±10 kHz)
                    if payload.count == 1 {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x27, 0x15, 0x00, 0xFD]
                    } else {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
                    }
                case 0x16: // Scope Speed query (01 = FAST)
                    if payload.count == 1 {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x27, 0x16, 0x01, 0xFD]
                    } else {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
                    }
                case 0x17: // Scope Mode query (00 = Center Mode)
                    if payload.count == 1 {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x27, 0x17, 0x00, 0xFD]
                    } else {
                        replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
                    }
                case 0x19: // Scope Reference Level query (0 dB)
                    let subVal = (payload.count > 1) ? payload[1] : 0x00
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0x27, 0x19, subVal, 0x00, 0x00, 0xFD]
                default:
                    replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
                }
            } else {
                replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
            }

        default:
            // Standard ACK for any unhandled command
            replyFrame = [0xFE, 0xFE, fromAddr, radioAddr, 0xFB, 0xFD]
        }

        if !replyFrame.isEmpty {
            sendCIVFrame(replyFrame, to: clientAddr, clientID: clientID)
        }
    }

    private func sendCIVFrame(_ frame: [UInt8], to clientAddr: sockaddr_in, clientID: UInt32) {
        var packet = Data(repeating: 0, count: 21)
        let totalSize = 21 + frame.count
        packet.writeUInt32LE(UInt32(totalSize), at: 0)
        packet.writeUInt16LE(0x00, at: 4)
        packet.writeUInt16LE(nextCIVSequence(), at: 6)
        packet.writeUInt32LE(serverID, at: 8)
        packet.writeUInt32LE(clientID, at: 12)

        packet[16] = 0xC1
        packet.writeUInt16LE(UInt16(frame.count), at: 17)
        packet.writeUInt16BE(civDataSequence, at: 19)
        civDataSequence &+= 1
        packet.append(contentsOf: frame)

        sendUDPPacket(packet, on: civSocketFd, to: clientAddr)
        currentSession?.packetsSent += 1
    }

    // MARK: - CI-V Transceive Broadcasts (Radio -> Connected Software)
    func broadcastFrequency(_ freq: UInt64) {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            var targets: [(UInt32, sockaddr_in)] = self.clientCivEndpointsList
            if targets.isEmpty, let fallback = self.clientRemoteCivAddr {
                targets.append((self.currentSession?.id ?? 0, fallback))
            }
            guard !targets.isEmpty else { return }

            let radioAddrs = Array(Set([self.radioModel.civAddress, self.lastUsedRadioAddress].compactMap { $0 }))
            let bcd = Self.frequencyBCD(freq)
            let targetAddr = self.lastClientCIVAddress

            for (cID, target) in targets {
                for radioAddr in radioAddrs {
                    // 1. Unsolicited Transceive Broadcast Frame (Cmd 0x00) to 0x00
                    let transceiveFrame: [UInt8] = [0xFE, 0xFE, 0x00, radioAddr, 0x00] + bcd + [0xFD]
                    self.sendCIVFrame(transceiveFrame, to: target, clientID: cID)

                    // 2. Transceive Frame targeted to client controller
                    let targetedTransceive: [UInt8] = [0xFE, 0xFE, targetAddr, radioAddr, 0x00] + bcd + [0xFD]
                    self.sendCIVFrame(targetedTransceive, to: target, clientID: cID)

                    // 3. Controller Targeted Read Response Frame (Cmd 0x03)
                    let targetedFrame: [UInt8] = [0xFE, 0xFE, targetAddr, radioAddr, 0x03] + bcd + [0xFD]
                    self.sendCIVFrame(targetedFrame, to: target, clientID: cID)

                    if targetAddr != 0xE0 {
                        let e0Transceive: [UInt8] = [0xFE, 0xFE, 0xE0, radioAddr, 0x00] + bcd + [0xFD]
                        self.sendCIVFrame(e0Transceive, to: target, clientID: cID)
                        let e0Frame: [UInt8] = [0xFE, 0xFE, 0xE0, radioAddr, 0x03] + bcd + [0xFD]
                        self.sendCIVFrame(e0Frame, to: target, clientID: cID)
                    }

                    // 4. Dynamic Scope Edge notification (Cmd 0x27 0x14)
                    let span: UInt64 = 100_000
                    let lower = (freq >= span) ? (freq - span) : 100_000
                    let upper = freq + span
                    let lowerBCD = Self.frequencyBCD(lower)
                    let upperBCD = Self.frequencyBCD(upper)
                    let scopeEdge: [UInt8] = [0xFE, 0xFE, targetAddr, radioAddr, 0x27, 0x14, 0x01] + lowerBCD + upperBCD + [0xFD]
                    self.sendCIVFrame(scopeEdge, to: target, clientID: cID)
                    if targetAddr != 0xE0 {
                        let scopeEdgeE0: [UInt8] = [0xFE, 0xFE, 0xE0, radioAddr, 0x27, 0x14, 0x01] + lowerBCD + upperBCD + [0xFD]
                        self.sendCIVFrame(scopeEdgeE0, to: target, clientID: cID)
                    }

                    // 5. Selected VFO Frequency Broadcast (Cmd 0x25 0x00)
                    let vfoFrame: [UInt8] = [0xFE, 0xFE, targetAddr, radioAddr, 0x25, 0x00] + bcd + [0xFD]
                    self.sendCIVFrame(vfoFrame, to: target, clientID: cID)
                    let vfoUnsolicited: [UInt8] = [0xFE, 0xFE, 0x00, radioAddr, 0x25, 0x00] + bcd + [0xFD]
                    self.sendCIVFrame(vfoUnsolicited, to: target, clientID: cID)
                    if targetAddr != 0xE0 {
                        let vfoFrameE0: [UInt8] = [0xFE, 0xFE, 0xE0, radioAddr, 0x25, 0x00] + bcd + [0xFD]
                        self.sendCIVFrame(vfoFrameE0, to: target, clientID: cID)
                    }
                }
            }
        }
    }

    func broadcastMode(_ mode: String) {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            var targets: [(UInt32, sockaddr_in)] = self.clientCivEndpointsList
            if targets.isEmpty, let fallback = self.clientRemoteCivAddr {
                targets.append((self.currentSession?.id ?? 0, fallback))
            }
            guard !targets.isEmpty else { return }

            let radioAddrs = Array(Set([self.radioModel.civAddress, self.lastUsedRadioAddress].compactMap { $0 }))
            let modeCode = Self.modeCode(from: mode)
            let isData = mode.contains("-D") || mode == "DIGI" || mode == "PKTUSB"
            let dataByte: UInt8 = isData ? 0x01 : 0x00
            let filter: UInt8 = 0x01
            let targetAddr = self.lastClientCIVAddress

            for (cID, target) in targets {
                for radioAddr in radioAddrs {
                    // 1. Unsolicited Transceive Mode Frame (Cmd 0x01) to 0x00
                    let transceiveFrame: [UInt8] = [0xFE, 0xFE, 0x00, radioAddr, 0x01, modeCode, filter, 0xFD]
                    self.sendCIVFrame(transceiveFrame, to: target, clientID: cID)

                    // 2. Targeted Operating Mode Frame (Cmd 0x04)
                    let targetedFrame: [UInt8] = [0xFE, 0xFE, targetAddr, radioAddr, 0x04, modeCode, filter, 0xFD]
                    self.sendCIVFrame(targetedFrame, to: target, clientID: cID)

                    if targetAddr != 0xE0 {
                        let e0Frame: [UInt8] = [0xFE, 0xFE, 0xE0, radioAddr, 0x04, modeCode, filter, 0xFD]
                        self.sendCIVFrame(e0Frame, to: target, clientID: cID)
                    }

                    // 3. Selected VFO Mode Frame (Cmd 0x26 0x00)
                    let vfoModeFrame: [UInt8] = [0xFE, 0xFE, targetAddr, radioAddr, 0x26, 0x00, modeCode, dataByte, filter, 0xFD]
                    self.sendCIVFrame(vfoModeFrame, to: target, clientID: cID)
                    let vfoModeUnsolicited: [UInt8] = [0xFE, 0xFE, 0x00, radioAddr, 0x26, 0x00, modeCode, dataByte, filter, 0xFD]
                    self.sendCIVFrame(vfoModeUnsolicited, to: target, clientID: cID)
                    if targetAddr != 0xE0 {
                        let vfoModeE0: [UInt8] = [0xFE, 0xFE, 0xE0, radioAddr, 0x26, 0x00, modeCode, dataByte, filter, 0xFD]
                        self.sendCIVFrame(vfoModeE0, to: target, clientID: cID)
                    }

                    // 4. Data Mode Frame (Cmd 0x1A 0x06)
                    let dataModeFrame: [UInt8] = [0xFE, 0xFE, targetAddr, radioAddr, 0x1A, 0x06, dataByte, 0x01, 0xFD]
                    self.sendCIVFrame(dataModeFrame, to: target, clientID: cID)
                    if targetAddr != 0xE0 {
                        let dataModeE0: [UInt8] = [0xFE, 0xFE, 0xE0, radioAddr, 0x1A, 0x06, dataByte, 0x01, 0xFD]
                        self.sendCIVFrame(dataModeE0, to: target, clientID: cID)
                    }
                }
            }
        }
    }

    func broadcastPTT(_ isTX: Bool) {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            var targets: [(UInt32, sockaddr_in)] = self.clientCivEndpointsList
            if targets.isEmpty, let fallback = self.clientRemoteCivAddr {
                targets.append((self.currentSession?.id ?? 0, fallback))
            }
            guard !targets.isEmpty else { return }

            let radioAddrs = Array(Set([self.radioModel.civAddress, self.lastUsedRadioAddress].compactMap { $0 }))
            let targetAddr = self.lastClientCIVAddress

            for (cID, target) in targets {
                for radioAddr in radioAddrs {
                    let pttFrame: [UInt8] = [0xFE, 0xFE, targetAddr, radioAddr, 0x1C, 0x00, isTX ? 0x01 : 0x00, 0xFD]
                    self.sendCIVFrame(pttFrame, to: target, clientID: cID)
                    if targetAddr != 0xE0 {
                        let pttFrameE0: [UInt8] = [0xFE, 0xFE, 0xE0, radioAddr, 0x1C, 0x00, isTX ? 0x01 : 0x00, 0xFD]
                        self.sendCIVFrame(pttFrameE0, to: target, clientID: cID)
                    }
                }
            }
        }
    }

    // MARK: - Audio Channel Packet Processing
    private func readAudioData() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var clientAddr = sockaddr_in()

        while true {
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.recvfrom(audioSocketFd, &buffer, buffer.count, 0, $0, &addrLen)
                }
            }

            guard count >= 16 else { break }
            let data = Data(buffer.prefix(count))
            handleAudioPacket(data, from: clientAddr)
        }
    }

    private func handleAudioPacket(_ data: Data, from clientAddr: sockaddr_in) {
        let clientPort = UInt16(bigEndian: clientAddr.sin_port)
        guard clientPort != audioPort && clientPort != civPort && clientPort != controlPort else { return }

        let type = data.uint16LE(at: 4)
        let clientID = data.uint32LE(at: 8)
        clientRemoteAudioAddr = clientAddr
        registerAudioEndpoint(clientID: clientID, addr: clientAddr)
        isAudioChannelOpen = true
        currentSession?.audioPort = clientPort

        if type == 0x03 {
            sendControlReply(type: 0x04, on: audioSocketFd, to: clientAddr, clientID: clientID)
            sendControlReply(type: 0x06, on: audioSocketFd, to: clientAddr, clientID: clientID)
            return
        } else if type == 0x06 {
            isAudioChannelOpen = true
            sendControlReply(type: 0x06, on: audioSocketFd, to: clientAddr, clientID: clientID)
            return
        } else if type == 0x07 {
            isAudioChannelOpen = true
            handlePing(data, onFd: audioSocketFd, to: clientAddr)
            return
        } else if type == 0x00, data.count == 16 {
            // Audio pkt0 idle keepalive
            currentSession?.lastKeepaliveAt = Date()
            return
        }

        // Incoming Client TX Audio Data Frame
        if data.count > 24, data[16] == 0x80 {
            isAudioChannelOpen = true
            let byteCount = min(Int(data.uint16BE(at: 22)), data.count - 24)
            guard byteCount >= 2 else { return }
            let payload = data[24..<(24 + byteCount)]

            var samples: [Float] = []
            samples.reserveCapacity(byteCount / 2)
            var offset = payload.startIndex
            while offset + 2 <= payload.endIndex {
                let sampleInt = Int16(bitPattern: payload.uint16LE(at: offset))
                samples.append(Float(sampleInt) / 32768.0)
                offset += 2
            }
            onClientTXAudioReceived?(samples)
        }
    }

    // MARK: - Server Audio Transmission (Stream 48kHz PCM to Client)
    func sendAudioFrame(_ samples: [Float]) {
        guard isRunning else { return }

        var targets: [(UInt32, sockaddr_in)] = clientAudioEndpointsList
        if targets.isEmpty, let fallback = clientRemoteAudioAddr {
            targets.append((currentSession?.id ?? 0, fallback))
        }
        guard !targets.isEmpty else { return }

        let targetRate = clientSampleRate
        let outputSamples: [Float]
        if targetRate > 0 && targetRate != 48000 {
            let step = 48000.0 / Double(targetRate)
            let outCount = Int(Double(samples.count) / step)
            var resampled = [Float](repeating: 0.0, count: outCount)
            for i in 0..<outCount {
                let srcIdx = min(Int(Double(i) * step), samples.count - 1)
                resampled[i] = samples[srcIdx]
            }
            outputSamples = resampled
        } else {
            outputSamples = samples
        }

        var sanitized = [Int16](repeating: 0, count: outputSamples.count)
        for i in 0..<outputSamples.count {
            let s = outputSamples[i]
            if s.isNaN || s.isInfinite {
                sanitized[i] = 0
            } else {
                let clamped = max(-1.0, min(1.0, s))
                sanitized[i] = Int16(clamped * 32767.0)
            }
        }

        let byteCount = sanitized.count * 2
        var packet = Data(repeating: 0, count: 24 + byteCount)
        packet.writeUInt32LE(UInt32(24 + byteCount), at: 0)
        packet.writeUInt16LE(0x00, at: 4)
        packet.writeUInt16LE(nextAudioSequence(), at: 6)
        packet.writeUInt32LE(serverID, at: 8)

        packet[16] = 0x80
        packet[17] = 0x00
        packet.writeUInt16BE(audioDataSequence, at: 18)
        audioDataSequence &+= 1
        packet[20] = 0x00
        packet[21] = 0x00
        packet.writeUInt16BE(UInt16(byteCount), at: 22)

        sanitized.withUnsafeBytes { ptr in
            packet.replaceSubrange(24..<(24 + byteCount), with: ptr)
        }

        for (cID, target) in targets {
            let targetPort = UInt16(bigEndian: target.sin_port)
            guard targetPort != audioPort && targetPort != civPort && targetPort != controlPort else { continue }
            var clientPkt = packet
            clientPkt.writeUInt32LE(cID, at: 12)
            sendUDPPacket(clientPkt, on: audioSocketFd, to: target)
        }
    }

    // MARK: - Ping & Control Helpers
    private func handlePing(_ data: Data, onFd fd: Int32, to clientAddr: sockaddr_in) {
        let clientID = data.uint32LE(at: 8)
        var reply = data
        reply.writeUInt32LE(serverID, at: 8)
        reply.writeUInt32LE(clientID, at: 12)
        if reply.count > 16 {
            reply[16] = 1 // Ping reply
        }
        sendUDPPacket(reply, on: fd, to: clientAddr)
    }

    private func sendControlReply(type: UInt16, on fd: Int32? = nil, to clientAddr: sockaddr_in, clientID: UInt32) {
        var packet = Data(repeating: 0, count: 16)
        packet.writeUInt32LE(16, at: 0)
        packet.writeUInt16LE(type, at: 4)
        let seq: UInt16
        if let targetFd = fd, targetFd == civSocketFd {
            seq = nextCIVSequence()
        } else if let targetFd = fd, targetFd == audioSocketFd {
            seq = nextAudioSequence()
        } else {
            seq = nextControlSequence()
        }
        packet.writeUInt16LE(seq, at: 6)
        packet.writeUInt32LE(serverID, at: 8)
        packet.writeUInt32LE(clientID, at: 12)

        let targetFd = fd ?? controlSocketFd
        sendUDPPacket(packet, on: targetFd, to: clientAddr)
    }

    private func sendUDPPacket(_ data: Data, on fd: Int32, to destAddr: sockaddr_in) {
        let destPort = UInt16(bigEndian: destAddr.sin_port)
        guard destPort != controlPort && destPort != civPort && destPort != audioPort else { return }

        var addr = destAddr
        _ = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                data.withUnsafeBytes { bytes in
                    Darwin.sendto(fd, bytes.baseAddress, bytes.count, 0, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func nextControlSequence() -> UInt16 {
        defer { controlSequence &+= 1 }
        return controlSequence
    }

    private func nextCIVSequence() -> UInt16 {
        defer { civSequence &+= 1 }
        return civSequence
    }

    private func nextAudioSequence() -> UInt16 {
        defer { audioSequence &+= 1 }
        return audioSequence
    }

    // MARK: - BCD Helpers
    static func frequencyBCD(_ frequencyHz: UInt64) -> [UInt8] {
        var remaining = frequencyHz
        return (0..<5).map { _ in
            let low = UInt8(remaining % 10)
            remaining /= 10
            let high = UInt8(remaining % 10)
            remaining /= 10
            return low | (high << 4)
        }
    }

    static func frequencyFromBCD(_ bytes: [UInt8]) -> UInt64 {
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

    static func modeCode(from name: String) -> UInt8 {
        switch name.uppercased() {
        case "LSB": return 0x00
        case "USB", "USB-D": return 0x01
        case "AM": return 0x02
        case "CW": return 0x03
        case "RTTY": return 0x04
        case "FM": return 0x05
        case "CW-R": return 0x07
        default: return 0x01
        }
    }

    static func modeName(_ code: UInt8) -> String {
        switch code {
        case 0x00: return "LSB"
        case 0x01: return "USB"
        case 0x02: return "AM"
        case 0x03: return "CW"
        case 0x04: return "RTTY"
        case 0x05: return "FM"
        case 0x07: return "CW-R"
        default: return "USB"
        }
    }
}

// MARK: - Extensions for Data Parsing
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

    func uint32BE(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
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
        guard range.upperBound <= count else { return "" }
        let bytes = self[range].prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}
