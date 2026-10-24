// Stand-ins for what YAAM/Lab599TX500Driver.swift and YAAM/FX4CRDriver.swift use besides their own code, for the
// behaviour tests of the CAT drivers (Tests/CATChunkStopRegression.swift, Tests/CATChunkPacingRegression.swift).
// The SerialPortService stand-in has the real class's shape (YAAM/SerialPortService.swift) but opens nothing:
// openPort always fails, and every write is recorded in SerialLog with the time it was made and handed to CATRadio,
// a model of the radio's keyer that the pacing test switches on. Only the members the two drivers use are declared.
// Nothing here
// opens a port, a socket or a device. They replace the real types only in these test programs; nothing in the app
// refers to this file. (Tests/Support/TransmitGateStubs.swift cannot be used here: it has its own driver stand-ins.)
import Foundation

/// What the drivers wrote to the (stand-in) serial port, with the time of each write.
nonisolated struct SerialWrite: Sendable {
    let time: Date
    let text: String
}

nonisolated enum SerialLog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var writes: [SerialWrite] = []

    static func add(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        writes.append(SerialWrite(time: Date(), text: text))
    }

    /// Everything written since the last drain, in order.
    static func drain() -> [SerialWrite] {
        lock.lock(); defer { lock.unlock() }
        let w = writes
        writes = []
        return w
    }
}

nonisolated public final class SerialPortService: @unchecked Sendable {
    public static let shared = SerialPortService()
    nonisolated(unsafe) static var allowsOpen = false
    nonisolated(unsafe) static var rtsResult = true
    nonisolated(unsafe) static var writeReply: (@Sendable (String) -> String?)?
    nonisolated(unsafe) static var writeDataReply: (@Sendable (Data) -> Data?)?
    private var onReceive: (@Sendable (Data) -> Void)?

    public init() {}
    public var isOpen: Bool { Self.allowsOpen }

    public static func availablePorts(includeBluetooth: Bool = true) -> [String] { [] }
    public static func isBluetoothPort(_ path: String) -> Bool { path.lowercased().contains("bluetooth") }
    public static func isUSBPort(_ path: String) -> Bool { path.lowercased().contains("usbserial") }

    /// Always fails, so a stray connect() never starts the drivers' polling.
    public func openPort(path: String, baudRate: Int = 1200, stopBits: Int = 1,
                         onReceive: (@Sendable (Data) -> Void)? = nil) -> Bool {
        self.onReceive = onReceive
        SerialLog.add("OPEN")
        return Self.allowsOpen
    }
    public func closePort() {}

    @discardableResult public func setDTR(active: Bool) -> Bool { SerialLog.add("DTR \(active)"); return true }
    @discardableResult public func setRTS(active: Bool) -> Bool { SerialLog.add("RTS \(active)"); return Self.rtsResult }

    @discardableResult
    public func writeData(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        SerialLog.add(text)
        CATRadio.receive(text, at: Date())
        if let reply = Self.writeReply?(text) { onReceive?(Data(reply.utf8)) }
        if let reply = Self.writeDataReply?(data) { onReceive?(reply) }
        return true
    }
}

/// A model of the keyer of a radio that takes Kenwood KS and KY commands, behind the stand-in port. It is off
/// (.none) unless a test switches it on. Each KY text it accepts is "keyed" for keyingSeconds(text, wpm), which the
/// test supplies (its own Morse clock), starting `latency` after the text arrives and after the text before it.
/// The radio's behaviour with a second KY while it keys is not documented, so there are two models:
///   .queue   accepts every KY and keys the texts one after the other;
///   .refuse  drops a KY that arrives while the one before is still being keyed (busy).
/// Both drop a text longer than the KY buffer (24 characters). "KY ;" (no text) and RX end the keying at once.
nonisolated enum CATRadio {
    enum Model: Sendable { case none, queue, refuse }

    struct Keyed: Sendable {
        let text: String
        let arrival: Date
        let start: Date
        var end: Date
    }

    struct Refused: Sendable {
        let text: String
        let arrival: Date
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var model: Model = .none
    nonisolated(unsafe) private static var latency: TimeInterval = 0.08
    nonisolated(unsafe) private static var keyingSeconds: @Sendable (String, Int) -> TimeInterval = { _, _ in 0 }
    nonisolated(unsafe) private static var wpm = 24
    nonisolated(unsafe) private static var keyed: [Keyed] = []
    nonisolated(unsafe) private static var refused: [Refused] = []

    static func use(_ m: Model, latency l: TimeInterval = 0.08, keyingSeconds k: @escaping @Sendable (String, Int) -> TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        model = m; latency = l; keyingSeconds = k; keyed = []; refused = []
    }

    /// What was accepted and what was refused since the last drain.
    static func drain() -> (keyed: [Keyed], refused: [Refused]) {
        lock.lock(); defer { lock.unlock() }
        let r = (keyed, refused)
        keyed = []; refused = []
        return r
    }

    /// When the last accepted text ends (now or earlier if nothing is being keyed).
    static func busyUntil() -> Date {
        lock.lock(); defer { lock.unlock() }
        return keyed.last?.end ?? .distantPast
    }

    static func receive(_ write: String, at t: Date) {
        lock.lock(); defer { lock.unlock() }
        guard model != .none else { return }
        for command in write.split(separator: ";", omittingEmptySubsequences: true).map(String.init) {
            if command.hasPrefix("KS"), let speed = Int(command.dropFirst(2)) {
                wpm = speed
            } else if command.hasPrefix("KY") {
                let text = String(command.dropFirst(command.hasPrefix("KY ") ? 3 : 2))
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    stopKeying(at: t)
                } else {
                    key(text, at: t)
                }
            } else if command == "RX" {
                stopKeying(at: t)
            }
        }
    }

    private static func key(_ text: String, at t: Date) {
        let lastEnd = keyed.last?.end ?? .distantPast
        if text.count > 24 || (model == .refuse && t < lastEnd) {
            refused.append(Refused(text: text, arrival: t))
            return
        }
        let start = max(t.addingTimeInterval(latency), lastEnd)
        keyed.append(Keyed(text: text, arrival: t, start: start, end: start.addingTimeInterval(keyingSeconds(text, wpm))))
    }

    private static func stopKeying(at t: Date) {
        for i in keyed.indices where keyed[i].end > t { keyed[i].end = max(keyed[i].start, t) }
    }
}

// AmateurBandPlan (OperatorModels.swift) pulls in half of the app; the drivers only name the band with it.
nonisolated enum AmateurBandPlan {
    static func band(forMHz mhz: Double) -> String? { nil }
}

// SerialControlPin is declared in SerialKeyerDriver.swift, which needs the rest of the keyer.
public enum SerialControlPin { case dtr, rts }
