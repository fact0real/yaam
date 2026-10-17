import Foundation

// Behaviour test of the WinKeyer driver against K1EL's datasheet ("WinKeyer3 IC Interface & Operation Manual",
// Rev 1.3, 3/19/2019; page numbers are the printed ones). It runs the real YAAM/WinKeyerDriver.swift against a
// stand-in SerialPortService declared below, which records every byte the driver writes and hands back bytes as a
// WinKeyer would send them. An analyser built from the datasheet's command list (each command and the number of
// parameter bytes that follow it) reads the recorded bytes the way a WinKeyer does: 0x00-0x1F a command and its
// parameters, 0x20-0x7F text that it keys in Morse.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/WinKeyerDatasheetRegression.swift YAAM/WinKeyerDriver.swift -o wkdatasheet && ./wkdatasheet
// Nothing opens a port or a device, and nothing is keyed.

/// Stand-in: records the bytes the driver writes, and passes bytes back to it as the WinKeyer's answers.
final class SerialPortService {
    static let shared = SerialPortService()
    static var written: [UInt8] = []
    static var echoAdmin = true
    static var openedStopBits = 0
    private var onReceive: (@Sendable (Data) -> Void)?
    init() {}
    static func availablePorts(includeBluetooth: Bool = true) -> [String] { [] }
    func openPort(path: String, baudRate: Int = 1200, stopBits: Int = 1,
                  onReceive: (@Sendable (Data) -> Void)? = nil) -> Bool {
        self.onReceive = onReceive
        Self.openedStopBits = stopBits
        return true
    }
    func closePort() {}
    @discardableResult func writeData(_ data: Data) -> Bool {
        let bytes = Array(data)
        Self.written += bytes
        if Self.echoAdmin, bytes.count == 3, bytes[0] == 0, bytes[1] == 4 { onReceive?(Data([bytes[2]])) }
        return true
    }
    /// The WinKeyer sends these bytes to the host.
    func winKeyerSends(_ bytes: [UInt8]) { onReceive?(Data(bytes)) }
}

// MARK: - The analyser, from the datasheet

/// Host commands (pp. 5-16): command byte -> (name, parameter bytes that follow it, printed page).
let datasheetCommands: [UInt8: (name: String, params: Int, page: Int)] = [
    0x00: ("Admin", 1, 5), 0x01: ("Sidetone Control", 1, 7), 0x02: ("Set WPM Speed", 1, 8),
    0x03: ("Set Weighting", 1, 8), 0x04: ("Set PTT Lead/Tail", 2, 8), 0x05: ("Setup Speed Pot", 3, 9),
    0x06: ("Set Pause State", 1, 9), 0x07: ("Get Speed Pot", 0, 9), 0x08: ("Backspace", 0, 9),
    0x09: ("Set PinConfig", 1, 9), 0x0A: ("Clear Buffer", 0, 10), 0x0B: ("Key Immediate", 1, 10),
    0x0C: ("Set HSCW", 1, 10), 0x0D: ("Set Farns WPM", 1, 10), 0x0E: ("Set WinKeyer Mode", 1, 11),
    0x0F: ("Load Defaults", 15, 12), 0x10: ("Set 1st Extension", 1, 12), 0x11: ("Set Key Comp", 1, 13),
    0x12: ("Set Paddle Switchpoint", 1, 13), 0x13: ("Null Command", 0, 13), 0x14: ("Software Paddle", 1, 13),
    0x15: ("Request WinKeyer Status", 0, 14), 0x16: ("Pointer Command", 1, 14), 0x17: ("Set Dit/Dah Ratio", 1, 14),
    0x18: ("PTT On/Off", 1, 15), 0x19: ("Key Buffered", 1, 15), 0x1A: ("Wait for nn Seconds", 1, 15),
    0x1B: ("Merge Letters", 2, 15), 0x1C: ("Buffered Speed Change", 1, 16), 0x1D: ("HSCW Speed Change", 1, 16),
    0x1E: ("Cancel Buffered Speed Change", 0, 16), 0x1F: ("Buffered NOP", 0, 16),
]
/// Admin sub-commands that take more bytes after <00><nn> (pp. 5-7).
let adminExtraBytes: [UInt8: Int] = [4: 1, 13: 256, 14: 1, 15: 1, 19: 2, 22: 1, 25: 1]
/// The datasheet's value range of each parameter.
let datasheetRanges: [UInt8: [ClosedRange<Int>]] = [
    0x02: [5...99], 0x03: [10...90], 0x04: [0...250, 0...250], 0x0D: [10...99], 0x11: [0...250], 0x17: [33...66],
]

enum Read: Equatable, CustomStringConvertible {
    case command([UInt8])
    case text(Character)
    case incomplete([UInt8])
    case notHostByte(UInt8)

    var description: String {
        switch self {
        case .command(let b):
            let name = datasheetCommands[b[0]]?.name ?? "?"
            return "<" + b.map { String(format: "%02X", $0) }.joined(separator: " ") + "> \(name)"
        case .text(let c): return "TEXT '\(c)'"
        case .incomplete(let b): return "INCOMPLETE <" + b.map { String(format: "%02X", $0) }.joined(separator: " ") + ">"
        case .notHostByte(let b): return String(format: "BYTE %02X", b)
        }
    }
}

/// Reads host bytes as a WinKeyer does.
func analyse(_ bytes: [UInt8]) -> [Read] {
    var out: [Read] = []
    var i = 0
    while i < bytes.count {
        let b = bytes[i]
        if b < 0x20 {
            var need = datasheetCommands[b]!.params
            if b == 0x00, i + 1 < bytes.count { need += adminExtraBytes[bytes[i + 1]] ?? 0 }
            if b == 0x16, i + 1 < bytes.count, bytes[i + 1] == 0x03 { need += 1 }     // <16><03><number of nulls>
            if i + need >= bytes.count {
                out.append(.incomplete(Array(bytes[i...])))
                return out
            }
            out.append(.command(Array(bytes[i...(i + need)])))
            i += need + 1
        } else if b <= 0x7F {
            out.append(.text(Character(UnicodeScalar(b))))
            i += 1
        } else {
            out.append(.notHostByte(b))
            i += 1
        }
    }
    return out
}

func texts(_ reads: [Read]) -> String {
    String(reads.compactMap { if case .text(let c) = $0 { return c } else { return nil } })
}

func commands(_ reads: [Read]) -> [[UInt8]] {
    reads.compactMap { if case .command(let b) = $0 { return b } else { return nil } }
}

/// The values outside the datasheet's ranges.
func outOfRange(_ reads: [Read]) -> [String] {
    commands(reads).flatMap { cmd -> [String] in
        guard let ranges = datasheetRanges[cmd[0]] else { return [] }
        return zip(cmd.dropFirst(), ranges).compactMap { value, range in
            range.contains(Int(value)) ? nil : String(format: "%02X: %d not in \(range)", cmd[0], value)
        }
    }
}

// MARK: - Checks

private var failures = 0

private func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("PASS \(name)")
    } else {
        let more = detail()
        print("FAIL \(name)\(more.isEmpty ? "" : "   [\(more)]")")
        failures += 1
    }
}

@MainActor private func run(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// What the driver reports to the keyer.
nonisolated final class Reports: @unchecked Sendable {
    var breakIns = 0
    var ends = 0
    var echoes: [String] = []
}

@main
struct WinKeyerDatasheetRegression {
    static func main() {
        let driver = WinKeyerDriver.shared
        let reports = Reports()
        driver.onPaddleBreakIn = { reports.breakIns += 1 }
        driver.onTransmissionComplete = { reports.ends += 1 }
        driver.onCharacterEchoed = { reports.echoes.append($0) }
        // The settings the app starts with (set here, so the test does not depend on saved preferences).
        driver.wpm = 24
        driver.mode = .iambicB
        driver.sidetoneHz = 600
        driver.weight = 50
        driver.pttLeadInMs = 20
        driver.pttTailMs = 30
        driver.keyingCompensationMs = 0
        driver.farnsworthWpm = 0
        driver.ditDahRatio = 50
        driver.paddleSwap = false
        driver.autoSpace = false

        connect(driver)
        setters(driver)
        answers(driver, reports)
        statusBytes(driver, reports)
        flowControl(driver)

        if failures > 0 {
            print("WinKeyer datasheet regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("WinKeyer datasheet regression passed")
    }

    // MARK: Host Open and syncAllSettings

    static func connect(_ driver: WinKeyerDriver) {
        SerialPortService.written = []
        driver.connect(port: "stand-in")
        // A WK3 at rev 31.03 answers Host Open with 31 (p. 5) at once; the host waits for it before other commands.
        SerialPortService.shared.winKeyerSends([31])
        run(0.5)                      // syncAllSettings runs 150 ms after Host Open
        let reads = analyse(SerialPortService.written)
        let shown = reads.map(\.description).joined(separator: " ")
        check("connect: the driver opens the stand-in port", driver.isConnected)
        check("connect: serial framing uses two stop bits", SerialPortService.openedStopBits == 2)
        check("connect: the first command is Admin Host Open <00><02> (p. 5)", commands(reads).first == [0x00, 0x02], shown)
        check("connect: no byte of Host Open + syncAllSettings is read as text, so nothing is keyed",
              texts(reads).isEmpty, "keyed: \"\(texts(reads))\" | " + shown)
        check("connect: every command is complete and none is the reserved Admin 8 or Setup Speed Pot",
              !reads.contains(where: { if case .incomplete = $0 { return true } else { return false } })
              && !commands(reads).contains([0x00, 0x08]) && !commands(reads).contains(where: { $0[0] == 0x05 }), shown)
        check("connect: the settings are, in order, speed 02, mode 0E, sidetone 01, weight 03, PTT 04 (two bytes), "
              + "key comp 11, ratio 17",
              commands(reads) == [[0x00, 0x02], [0x02, 24], [0x0E, 0x04], [0x01, 0x07], [0x03, 50], [0x04, 2, 3],
                                  [0x11, 0], [0x17, 50]], shown)
        check("connect: every value is within the datasheet's range", outOfRange(reads).isEmpty,
              outOfRange(reads).joined(separator: ", "))
    }

    // MARK: Each setter: the datasheet's command and parameter count

    static func setters(_ driver: WinKeyerDriver) {
        func one(_ name: String, expect: [UInt8], _ action: () -> Void) {
            SerialPortService.written = []
            action()
            let reads = analyse(SerialPortService.written)
            check("\(name): \(Read.command(expect).description), nothing keyed",
                  reads == [.command(expect)], reads.map(\.description).joined(separator: " "))
        }
        one("setSpeed(30) (p. 8)", expect: [0x02, 30]) { driver.setSpeed(30) }
        driver.paddleSwap = false; driver.autoSpace = false
        one("setMode(iambic B) (p. 11: key mode 00, serial echo bit 2)", expect: [0x0E, 0x04]) { driver.setMode(.iambicB) }
        one("setMode(iambic A) (p. 11: key mode 01 in bits 5-4)", expect: [0x0E, 0x14]) { driver.setMode(.iambicA) }
        one("setMode(ultimatic) (p. 11: key mode 10)", expect: [0x0E, 0x24]) { driver.setMode(.ultimatic) }
        one("setMode(bug) (p. 11: key mode 11)", expect: [0x0E, 0x34]) { driver.setMode(.bug) }
        driver.paddleSwap = true
        one("setMode with paddle swap (p. 11: bit 3)", expect: [0x0E, 0x0C]) { driver.setMode(.iambicB) }
        driver.paddleSwap = false; driver.autoSpace = true
        one("setMode with autospace (p. 11: bit 1)", expect: [0x0E, 0x06]) { driver.setMode(.iambicB) }
        driver.autoSpace = false
        one("setSidetone(800) (p. 7, table 7: N = 5)", expect: [0x01, 0x05]) { driver.setSidetone(800) }
        one("setSidetone(500) (p. 7, table 7: N = 8)", expect: [0x01, 0x08]) { driver.setSidetone(500) }
        one("setWeight(55) (p. 8)", expect: [0x03, 55]) { driver.setWeight(55) }
        one("setPTTDelays(50 ms, 120 ms) (p. 8: two bytes, 10 ms steps)", expect: [0x04, 5, 12]) {
            driver.setPTTDelays(leadInMs: 50, tailMs: 120)
        }
        one("setKeyingCompensation(10) (p. 13)", expect: [0x11, 10]) { driver.setKeyingCompensation(10) }
        one("setFarnsworth(18) (p. 10)", expect: [0x0D, 18]) { driver.setFarnsworth(18) }
        one("setFarnsworth(1) stays within the documented range", expect: [0x0D, 10]) { driver.setFarnsworth(1) }
        one("setDitDahRatio(50) (pp. 14-15)", expect: [0x17, 50]) { driver.setDitDahRatio(50) }
        one("setDitDahRatio(20) is kept within 33-66 (p. 14)", expect: [0x17, 33]) { driver.setDitDahRatio(20) }
        one("setDitDahRatio(80) is kept within 33-66 (p. 14)", expect: [0x17, 66]) { driver.setDitDahRatio(80) }
        driver.setDitDahRatio(50)
        SerialPortService.written = []
        driver.sendMorseText("cq")
        run(0.05)
        check("control: text sent on purpose is read as text", texts(analyse(SerialPortService.written)) == "CQ",
              analyse(SerialPortService.written).map(\.description).joined(separator: " "))
        // A tab, line feed or carriage return (a pasted text, a macro field) is a WinKeyer command, not text (pp. 5-17).
        SerialPortService.written = []
        driver.sendMorseText("op\tJosep\nqth\rx")
        run(0.05)
        let controlReads = analyse(SerialPortService.written)
        check("text with a tab, line feed and carriage return: no byte is read as a command",
              commands(controlReads).allSatisfy { $0 == [0x0A] || ($0.count == 3 && $0.prefix(2) == [0, 4]) },
              controlReads.map(\.description).joined(separator: " "))
        check("text with a tab, line feed and carriage return: each goes out as a space",
              texts(controlReads) == "OP JOSEP QTH X", texts(controlReads).debugDescription)
    }

    // MARK: Revision code and echo

    static func answers(_ driver: WinKeyerDriver, _ reports: Reports) {
        // Host Open was answered with 31 in connect(); an unsolicited status byte follows.
        driver.isTransmitting = false
        SerialPortService.shared.winKeyerSends([0xC0])
        run(0.1)
        check("version: the revision code 31 is shown in decimal (p. 5)", driver.wkVersion == "K1EL WinKeyer v31",
              driver.wkVersion)
        check("version: and is not read as hex digits", !driver.wkVersion.contains("."), driver.wkVersion)
        check("version: the revision code is not reported as an echoed letter", reports.echoes.isEmpty,
              "\(reports.echoes)")
        reports.echoes = []
        SerialPortService.shared.winKeyerSends([0x32, 0x43, 0x51, 0x20])
        run(0.1)
        check("echo: ASCII bytes after the revision are echoed letters (p. 3; p. 11, bit 2)",
              reports.echoes == ["2", "C", "Q", " "], "\(reports.echoes)")
        check("echo: the echoed '2' does not change the version", driver.wkVersion == "K1EL WinKeyer v31", driver.wkVersion)
        check("echo: the last echoed letter is shown", driver.lastEchoedChar == " ", driver.lastEchoedChar.debugDescription)
        reports.echoes = []
        SerialPortService.shared.winKeyerSends([0x85, 0x9F])
        run(0.1)
        check("speed pot bytes 10xxxxxx (p. 9) are not echoed letters", reports.echoes.isEmpty, "\(reports.echoes)")
    }

    // MARK: Status bytes 110xxxxx (p. 14)

    static func statusBytes(_ driver: WinKeyerDriver, _ reports: Reports) {
        driver.abort(reportEnd: false)
        func feed(_ byte: UInt8) -> (breakIns: Int, ends: Int, echoes: [String]) {
            reports.breakIns = 0; reports.ends = 0; reports.echoes = []
            SerialPortService.shared.winKeyerSends([byte])
            run(0.05)
            return (reports.breakIns, reports.ends, reports.echoes)
        }
        driver.isTransmitting = true
        var r = feed(0xC5)
        check("status 0xC5 (BUSY + XOFF, buffer over 2/3 full): not a paddle touch, the CW goes on",
              r.breakIns == 0 && r.ends == 0 && driver.isTransmitting, "\(r)")
        r = feed(0xC1)
        check("status 0xC1 (XOFF): not a paddle touch", r.breakIns == 0, "\(r)")
        driver.isTransmitting = true
        r = feed(0xCC)
        check("status 0xCC (KEYDOWN + BUSY): not a paddle touch", r.breakIns == 0 && r.ends == 0, "\(r)")
        r = feed(0xC8)
        check("status 0xC8 (KEYDOWN, tune) is busy, not a paddle touch or a completed message",
              r.breakIns == 0 && r.ends == 0 && driver.isTransmitting, "\(r)")
        driver.isTransmitting = true
        r = feed(0xD4)
        check("status 0xD4 (WAIT + BUSY) is a status byte: busy, no echo, no paddle touch, no end",
              r.breakIns == 0 && r.ends == 0 && r.echoes.isEmpty && driver.isTransmitting, "\(r)")
        r = feed(0xD0)
        // The datasheet does not list the events behind WAIT (p. 14); reading BUSY alone for the end is this patch's choice.
        check("status 0xD0 (WAIT) does not finish a message prematurely",
              r.ends == 0 && r.echoes.isEmpty && driver.isTransmitting, "\(r)")
        driver.isTransmitting = true
        r = feed(0xC6)
        check("status 0xC6 (BREAKIN + BUSY): the paddle break-in is reported", r.breakIns == 1 && r.ends == 0, "\(r)")
        r = feed(0xC2)
        check("status 0xC2 (BREAKIN): the paddle break-in is reported", r.breakIns == 1, "\(r)")
        driver.isTransmitting = true
        r = feed(0xC0)
        check("status 0xC0 (idle): the end is reported, nothing else", r.ends == 1 && r.breakIns == 0 && !driver.isTransmitting,
              "\(r)")
        SerialPortService.written = []
        driver.disconnect()
        check("disconnect: Clear Buffer <0A> (p. 10), then Admin Host Close <00><03> (p. 5)",
              analyse(SerialPortService.written) == [.command([0x0A]), .command([0x00, 0x03])],
              analyse(SerialPortService.written).map(\.description).joined(separator: " "))
        // A WinKeyer already in host mode may not answer a second Host Open: once the settings are sent, a letter is
        // an echo, not the revision code.
        driver.connect(port: "stand-in")
        run(2.2)
        r = feed(0x43)
        check("no answer to Host Open: the connection is closed and text is refused",
              !driver.isConnected && !driver.isTransmitting && r.echoes.isEmpty,
              "echoes \(r.echoes), version \(driver.wkVersion)")
        driver.disconnect()
    }

    static func flowControl(_ driver: WinKeyerDriver) {
        driver.connect(port: "stand-in")
        SerialPortService.shared.winKeyerSends([31])
        run(0.05)
        SerialPortService.written = []
        SerialPortService.echoAdmin = false
        driver.sendMorseText(String(repeating: "E", count: 117))
        let marker = SerialPortService.written.last!
        SerialPortService.shared.winKeyerSends([0xC0, 0x45])
        run(0.05)
        check("a stale idle/echo before the clear barrier cannot finish or start a replacement",
              driver.isTransmitting && texts(analyse(SerialPortService.written)).isEmpty)
        SerialPortService.shared.winKeyerSends([marker])
        run(0.05)
        check("a confirmed clear starts at most 32 unacknowledged characters",
              texts(analyse(SerialPortService.written)).count == 32)
        SerialPortService.shared.winKeyerSends([0xC5] + Array(repeating: 0x45, count: 16))
        run(0.05)
        check("XOFF pauses further text without treating it as a paddle touch",
              texts(analyse(SerialPortService.written)).count == 32 && driver.isTransmitting)
        SerialPortService.shared.winKeyerSends([0xC4])
        run(0.05)
        var echoed = 16
        var bounded = true
        while echoed < 117 {
            let sent = texts(analyse(SerialPortService.written)).count
            let count = min(32, sent - echoed)
            guard count > 0 else { bounded = false; break }
            SerialPortService.shared.winKeyerSends(Array(repeating: 0x45, count: count))
            echoed += count
            run(0.02)
            bounded = bounded && texts(analyse(SerialPortService.written)).count - echoed <= 32
        }
        check("a long message drains completely while respecting the echo window", bounded && echoed == 117)
        SerialPortService.shared.winKeyerSends([0xC0])
        run(0.02)
        check("completion follows the final character acknowledgements and idle", !driver.isTransmitting)
        SerialPortService.echoAdmin = true
        SerialPortService.written = []
        driver.sendMorseText(String(repeating: "E", count: 117))
        run(0.02)
        driver.abort(reportEnd: false)
        let stopped = SerialPortService.written
        SerialPortService.shared.winKeyerSends([0xC0] + Array(repeating: 0x45, count: 32))
        run(0.02)
        check("STOP drops pending text and late acknowledgements cannot restart it",
              SerialPortService.written == stopped && !driver.isTransmitting)
        driver.sendMorseText("E E E")
        run(0.02)
        SerialPortService.shared.winKeyerSends([0xC4, 0x45, 0x45, 0x45, 0xC0])
        run(0.02)
        check("letter echoes release preceding spaces even on devices that omit space echoes", !driver.isTransmitting)
        driver.disconnect()
    }
}
