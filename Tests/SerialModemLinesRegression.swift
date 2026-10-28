// Run with Tests/run-serial-modem-line-regressions.sh. Only local PTYs are opened.
import Darwin
import Foundation

nonisolated private final class ModemWrites: @unchecked Sendable {
    struct Entry: Equatable { let active: Bool; let mask: Int32 }
    private let lock = NSLock()
    private var entries: [Entry] = []
    func append(active: Bool, mask: Int32) {
        lock.lock(); defer { lock.unlock() }
        entries.append(Entry(active: active, mask: mask))
    }
    func take() -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        defer { entries = [] }
        return entries
    }
}

@main struct SerialModemLinesRegression {
    static func exercise(_ test: (String) -> Void) {
        var master: Int32 = -1, slave: Int32 = -1
        precondition(openpty(&master, &slave, nil, nil, nil) == 0)
        let path = String(cString: ttyname(slave))
        close(slave)
        defer { close(master) }
        test(path)
    }

    static func main() {
        // Inspect the actual production gate before its ioctl, with independent expected masks.
        for allowed: Set<SerialPortService.ModemLine> in [[], [.dtr], [.rts], [.dtr, .rts]] {
            exercise { path in
                let writes = ModemWrites()
                let port = SerialPortService(modemLines: allowed) { _, active, mask in
                    writes.append(active: active, mask: mask); return 0
                }
                precondition(port.openPort(path: path, baudRate: 9600))
                precondition(writes.take().isEmpty, "Opening a port must not explicitly change modem pins")
                for active in [true, false] {
                    precondition(port.setDTR(active: active) == allowed.contains(.dtr))
                    precondition(port.setRTS(active: active) == allowed.contains(.rts))
                    var expected: [ModemWrites.Entry] = []
                    if allowed.contains(.dtr) { expected.append(.init(active: active, mask: Int32(TIOCM_DTR))) }
                    if allowed.contains(.rts) { expected.append(.init(active: active, mask: Int32(TIOCM_RTS))) }
                    precondition(writes.take() == expected, "Denied assertions AND releases must never reach ioctl")
                }
                port.closePort()
                let expectedMask = (allowed.contains(.dtr) ? Int32(TIOCM_DTR) : 0) | (allowed.contains(.rts) ? Int32(TIOCM_RTS) : 0)
                let closed = writes.take()
                precondition(closed == (expectedMask == 0 ? [] : [.init(active: false, mask: expectedMask)]))
                precondition(!port.setDTR(active: true) && !port.setRTS(active: true))
                port.closePort()
                precondition(writes.take().isEmpty, "Repeated close must not write pins")
            }
        }
        print("PASS real serial service: default denial, independent DTR/RTS permissions, exact ioctl masks and scoped close")

        let writes = ModemWrites()
        let permitted = SerialPortService(modemLines: [.dtr, .rts]) { _, active, mask in
            writes.append(active: active, mask: mask); return 0
        }
        exercise { path in
            precondition(permitted.openPort(path: path))
            precondition(permitted.setDTR(active: true))
            _ = writes.take()
            permitted.closePort()
            precondition(writes.take() == [.init(active: false, mask: Int32(TIOCM_DTR))], "Unused RTS is untouched")
        }
        exercise { path in
            precondition(permitted.openPort(path: path))
            permitted.closePort()
            precondition(writes.take().isEmpty, "A new session must not inherit managed pins")
        }
        precondition(!permitted.openPort(path: "/dev/yaam-nonexistent-fixture"))
        precondition(writes.take().isEmpty, "Failed open must not manipulate pins")

        exercise { path in
            let failure = SerialPortService(modemLines: [.rts]) { _, active, mask in
                writes.append(active: active, mask: mask); return -1
            }
            precondition(failure.openPort(path: path))
            precondition(!failure.setRTS(active: true) && failure.lastError != nil)
            failure.closePort()
            precondition(writes.take() == [.init(active: true, mask: Int32(TIOCM_RTS)), .init(active: false, mask: Int32(TIOCM_RTS))])
            precondition(failure.lastError?.contains("release failed") == true)
        }
        print("PASS unused pins, session reset, failed open, honest ioctl failure and bounded release retry")
    }
}
