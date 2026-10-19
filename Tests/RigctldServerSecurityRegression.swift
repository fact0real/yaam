// swiftc -parse-as-library Tests/RigctldServerSecurityRegression.swift YAAM/HamlibRigctldServer.swift -o /tmp/yaam-rigctld-security
// Loopback/socket-pair stand-ins only. No radio or audio engine is constructed.
import Darwin
import Foundation

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
    func set(_ value: Int) { lock.lock(); storage = value; lock.unlock() }
    func increment() { lock.lock(); storage += 1; lock.unlock() }
}

@main struct RigctldServerSecurityRegression {
    static func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { usleep(1000) }
        precondition(condition(), "Timed out")
    }
    static func configure(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }
    static func connect(_ port: UInt16) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        precondition(fd >= 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = in_addr_t(INADDR_LOOPBACK).bigEndian
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        precondition(result == 0)
        configure(fd)
        return fd
    }
    static func send(_ bytes: Data, to fd: Int32) {
        let result = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        precondition(result == bytes.count)
    }
    static func send(_ text: String, to fd: Int32) { send(Data(text.utf8), to: fd) }
    static func read(_ fd: Int32, count: Int) -> Data {
        var result = Data()
        let deadline = Date().addingTimeInterval(3)
        while result.count < count && Date() < deadline {
            var bytes = [UInt8](repeating: 0, count: min(4096, count - result.count))
            let n = recv(fd, &bytes, bytes.count, 0)
            if n > 0 { result.append(bytes, count: n) }
            else if n == 0 { break }
            else { precondition([EAGAIN, EWOULDBLOCK, EINTR].contains(errno)); usleep(1000) }
        }
        return result
    }
    static func expectClosed(_ fd: Int32) {
        wait {
            var byte: UInt8 = 0
            let n = recv(fd, &byte, 1, 0)
            return n == 0 || (n < 0 && errno == ECONNRESET)
        }
    }
    static func main() throws {
        let clients = Counter(), pttCommands = Counter()
        let server = HamlibRigctldServer(limits: .init(maximumClients: 2, maximumLineBytes: 64, maximumPendingResponseBytes: 4096, maximumCommandsPerSecond: 8))
        server.getFrequency = { 14_074_000 }
        server.setPTT = { _ in pttCommands.increment() }
        server.onClientCountChanged = { clients.set($0) }
        try server.start(port: 0)
        precondition(server.isRunning && server.boundPort > 0)
        let first = connect(server.boundPort), second = connect(server.boundPort)
        defer { Darwin.close(first); Darwin.close(second); server.stop() }
        wait { clients.value == 2 }
        let excess = connect(server.boundPort)
        expectClosed(excess); Darwin.close(excess)
        precondition(clients.value == 2)
        send("f\r\nf\nf\n", to: first)
        precondition(String(data: read(first, count: 27), encoding: .utf8) == String(repeating: "14074000\n", count: 3))
        send("f" + String(repeating: " ", count: 63) + "\n", to: first)
        precondition(read(first, count: 9) == Data("14074000\n".utf8))
        send(String(repeating: "x", count: 32), to: second)
        send(String(repeating: "x", count: 33) + "\nT 1\n", to: second)
        expectClosed(second)
        wait { clients.value == 1 }
        precondition(pttCommands.value == 0, "Oversized line must not dispatch subsequent PTT")
        let malformed = connect(server.boundPort)
        wait { clients.value == 2 }
        send(Data([0xFF, 0x0A]) + Data("T 1\n".utf8), to: malformed)
        expectClosed(malformed); Darwin.close(malformed)
        wait { clients.value == 1 }
        precondition(pttCommands.value == 0)
        let flood = connect(server.boundPort)
        wait { clients.value == 2 }
        send(String(repeating: "f\n", count: 9) + "T 1\n", to: flood)
        expectClosed(flood); Darwin.close(flood)
        wait { clients.value == 1 }
        precondition(pttCommands.value == 0, "Command floods must not dispatch the remaining PTT")
        // Stop/start repeatedly with a live client, proving sessions release descriptors.
        for _ in 0..<15 {
            let restartPort = server.boundPort
            server.stop()
            expectClosed(first)
            try server.start(port: restartPort)
            let fd = connect(server.boundPort)
            send("f\n", to: fd)
            precondition(read(fd, count: 9) == Data("14074000\n".utf8))
            Darwin.close(fd)
        }
        server.stop()
        precondition(!server.isRunning && clients.value == 0)
        try socketPairChecks()
        print("rigctld limits, malformed/fragmented input, PTT exclusion, restart, partial writes and slow-reader checks passed")
    }

    static func socketPairChecks() throws {
        for slowReader in [false, true] {
            var pair: [Int32] = [-1, -1]
            precondition(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
            configure(pair[0]); configure(pair[1])
            var small: Int32 = 1024
            setsockopt(pair[0], SOL_SOCKET, SO_SNDBUF, &small, socklen_t(MemoryLayout<Int32>.size))
            let queue = DispatchQueue(label: "rigctld-security-test")
            let key = DispatchSpecificKey<UInt8>()
            queue.setSpecific(key: key, value: 1)
            let closed = Counter()
            let payload = String(repeating: "0123456789abcdef", count: 8192)
            var session: RigctldClientSession!
            queue.sync {
                session = RigctldClientSession(fd: pair[0], remoteIP: "local-test", remotePort: 0,
                    queue: queue, queueKey: key,
                    limits: .init(maximumClients: 1, maximumLineBytes: 64, maximumPendingResponseBytes: slowReader ? 4096 : 262144),
                    onCommand: { _ in slowReader ? String(repeating: "x", count: 2048) : payload },
                    onClose: { _ in closed.increment() })
                session.start()
            }
            if slowReader {
                send(String(repeating: "f\n", count: 64), to: pair[1])
                wait { closed.value == 1 }
            } else {
                send("f\n", to: pair[1])
                precondition(read(pair[1], count: payload.utf8.count) == Data(payload.utf8), "Partial writes must preserve every byte")
            }
            queue.sync { session.close(); session.close() }
            wait { closed.value == 1 }
            Darwin.close(pair[1])
            queue.sync { session = nil }
        }
    }
}
