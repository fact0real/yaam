//
//  HamlibRigctldServer.swift
//  YAAM
//
//  Created by factoreal on 9/13/26.
//

import Darwin
import Foundation

// MARK: - Hamlib Rigctld TCP Server
nonisolated final class HamlibRigctldServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.yaam.hamlib-rigctld", qos: .userInitiated)
    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clientConnections: [Int32: RigctldClientSession] = [:]
    private let lock = NSLock()

    // Callbacks to emulator engine
    var getFrequency: (@Sendable () -> UInt64)?
    var setFrequency: (@Sendable (UInt64) -> Void)?
    var getMode: (@Sendable () -> (mode: String, passband: Int))?
    var setMode: (@Sendable (String, Int) -> Void)?
    var getPTT: (@Sendable () -> Bool)?
    var setPTT: (@Sendable (Bool) -> Void)?
    var getSMeterDB: (@Sendable () -> Double)?
    var onClientCountChanged: (@Sendable (Int) -> Void)?
    var onLogMessage: (@Sendable (String) -> Void)?

    private(set) var isRunning: Bool = false
    private(set) var boundPort: UInt16 = 4532

    deinit {
        stop()
    }

    func start(port: UInt16 = 4532) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw NSError(domain: "HamlibRigctldServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create TCP socket: \(String(cString: strerror(errno)))"])
        }

        var opt: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        // The emulator accepts PTT commands and has no authentication. Keep it on this Mac.
        addr.sin_addr = in_addr(s_addr: in_addr_t(INADDR_LOOPBACK).bigEndian)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let msg = String(cString: strerror(errno))
            Darwin.close(fd)
            throw NSError(domain: "HamlibRigctldServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind port \(port): \(msg)"])
        }

        guard Darwin.listen(fd, 8) == 0 else {
            let msg = String(cString: strerror(errno))
            Darwin.close(fd)
            throw NSError(domain: "HamlibRigctldServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to listen on TCP socket: \(msg)"])
        }

        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }

        serverSocket = fd
        boundPort = port
        isRunning = true

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptIncoming()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        acceptSource = source

        onLogMessage?("[rigctld] Server listening on TCP port \(port)")
    }

    func stop() {
        lock.lock()
        guard isRunning else { lock.unlock(); return }
        isRunning = false

        acceptSource?.cancel()
        acceptSource = nil

        for (_, client) in clientConnections {
            client.close()
        }
        clientConnections.removeAll()
        lock.unlock()

        onClientCountChanged?(0)
        onLogMessage?("[rigctld] Server stopped")
    }

    private func acceptIncoming() {
        while true {
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(serverSocket, $0, &len)
                }
            }

            guard clientFd >= 0 else { break }

            var opt: Int32 = 1
            setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))
            let flags = fcntl(clientFd, F_GETFL)
            if flags >= 0 { _ = fcntl(clientFd, F_SETFL, flags | O_NONBLOCK) }

            var clientIP = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sinAddr = clientAddr.sin_addr
            _ = inet_ntop(AF_INET, &sinAddr, &clientIP, socklen_t(INET_ADDRSTRLEN))
            let ipString = String(cString: clientIP)
            let clientPort = UInt16(bigEndian: clientAddr.sin_port)

            let session = RigctldClientSession(
                fd: clientFd,
                remoteIP: ipString,
                remotePort: clientPort,
                queue: queue,
                onCommand: { [weak self] cmd in
                    self?.handleCommand(cmd) ?? "RPRT -1\n"
                },
                onClose: { [weak self] fd in
                    self?.removeClient(fd: fd)
                }
            )

            lock.lock()
            clientConnections[clientFd] = session
            let count = clientConnections.count
            lock.unlock()

            onClientCountChanged?(count)
            onLogMessage?("[rigctld] Client connected from \(ipString):\(clientPort)")
            session.start()
        }
    }

    private func removeClient(fd: Int32) {
        lock.lock()
        clientConnections.removeValue(forKey: fd)
        let count = clientConnections.count
        lock.unlock()
        onClientCountChanged?(count)
        onLogMessage?("[rigctld] Client disconnected (fd \(fd))")
    }

    // MARK: - Hamlib Command Processing
    private func handleCommand(_ rawCommand: String) -> String {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let verb = tokens.first else { return "RPRT -1\n" }

        switch verb {
        case "f", "\\get_freq":
            let freq = getFrequency?() ?? 14_074_000
            return "\(freq)\n"

        case "F", "\\set_freq":
            if tokens.count >= 2, let f = UInt64(tokens[1]) {
                setFrequency?(f)
                return "RPRT 0\n"
            }
            return "RPRT -1\n"

        case "m", "\\get_mode":
            let info = getMode?() ?? ("PKTUSB", 3000)
            return "\(info.0)\n\(info.1)\n"

        case "M", "\\set_mode":
            if tokens.count >= 2 {
                let mode = tokens[1]
                let width = tokens.count >= 3 ? (Int(tokens[2]) ?? 3000) : 3000
                setMode?(mode, width)
                return "RPRT 0\n"
            }
            return "RPRT -1\n"

        case "t", "\\get_ptt":
            let ptt = getPTT?() ?? false
            return "\(ptt ? 1 : 0)\n"

        case "T", "\\set_ptt":
            if tokens.count >= 2, tokens[1] == "0" || tokens[1] == "1" {
                let val = tokens[1] == "1"
                setPTT?(val)
                return "RPRT 0\n"
            }
            return "RPRT -1\n"

        case "v", "\\get_vfo":
            return "VFOA\n"

        case "V", "\\set_vfo":
            return "RPRT 0\n"

        case "s", "\\get_split_vfo":
            return "0\nVFOA\n"

        case "S", "\\set_split_vfo":
            return "RPRT 0\n"

        case "i", "\\get_split_freq":
            let freq = getFrequency?() ?? 14_074_000
            return "\(freq)\n"

        case "I", "\\set_split_freq":
            return "RPRT 0\n"

        case "l", "\\get_level":
            if tokens.count >= 2, tokens[1].uppercased() == "STRENGTH" {
                let db = getSMeterDB?() ?? 0.0
                return "\(Int(round(db)))\n"
            }
            return "0\n"

        case "\\get_powerstat":
            return "1\n" // Rig is powered ON

        case "\\chk_vfo":
            return "CHKVFO 0\n"

        case "\\dump_caps", "\\dump_state":
            return dumpRigState()

        case "q", "\\quit":
            return ""

        default:
            return "RPRT -1\n"
        }
    }

    private func dumpRigState() -> String {
        """
        0
        2
        1
        0.000000 0.000000 0x0
        0 0 0 0 0 0 0
        0 0 0 0 0 0 0
        0x1ff
        0x1ff
        0 0
        0 0
        0
        0
        0
        0
        0
        0
        100000 60000000 0x2ef -1 -1 0x1 0x3
        0 0 0 0 0 0 0
        100000 60000000 0x2ef 5000 100000 0x1 0x3
        0 0 0 0 0 0 0
        0 0
        0 0
        0x2ef 3000
        0x2ef 2400
        0x2ef 1800
        0 0
        0
        0
        0
        0
        0
        0
        RPRT 0

        """
    }
}

// MARK: - Individual Client TCP Session
nonisolated final class RigctldClientSession: @unchecked Sendable {
    let fd: Int32
    let remoteIP: String
    let remotePort: UInt16
    private let queue: DispatchQueue
    private let onCommand: (String) -> String
    private let onClose: (Int32) -> Void
    private var source: DispatchSourceRead?
    private var receiveBuffer = Data()
    private var isClosed = false
    private let lock = NSLock()

    init(
        fd: Int32,
        remoteIP: String,
        remotePort: UInt16,
        queue: DispatchQueue,
        onCommand: @escaping (String) -> String,
        onClose: @escaping (Int32) -> Void
    ) {
        self.fd = fd
        self.remoteIP = remoteIP
        self.remotePort = remotePort
        self.queue = queue
        self.onCommand = onCommand
        self.onClose = onClose
    }

    func start() {
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.readData()
        }
        readSource.setCancelHandler { [weak self] in
            guard let self else { return }
            Darwin.close(self.fd)
            self.onClose(self.fd)
        }
        source = readSource
        readSource.resume()
    }

    func close() {
        lock.lock()
        guard !isClosed else { lock.unlock(); return }
        isClosed = true
        source?.cancel()
        source = nil
        lock.unlock()
    }

    private func readData() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = Darwin.recv(fd, &buffer, buffer.count, 0)
        guard bytesRead > 0 else {
            close()
            return
        }

        receiveBuffer.append(buffer, count: bytesRead)

        // Process line-by-line (\n or \r\n)
        while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = receiveBuffer.subdata(in: 0..<newlineIndex)
            receiveBuffer.removeSubrange(0...newlineIndex)

            if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                let response = onCommand(line)
                if !response.isEmpty {
                    send(response)
                }
            }
        }
    }

    private func send(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        data.withUnsafeBytes { ptr in
            _ = Darwin.send(fd, ptr.baseAddress, ptr.count, 0)
        }
    }
}
