//
//  SerialPortService.swift
//  YAAM
//
//  Native Darwin POSIX Serial Port Driver for macOS
//  Supports USB-to-UART bridges (FTDI, Silicon Labs CP210x, CH340, Prolific, CDC-ACM)
//  Used for K1EL WinKeyer, microHAM, and direct serial CAT controllers.
//

import Darwin
import Foundation

nonisolated public final class SerialPortService: @unchecked Sendable {
    public enum ModemLine: Sendable, Hashable { case dtr, rts }

    public static let shared = SerialPortService()

    private var fileDescriptor: Int32 = -1
    private let ioLock = NSRecursiveLock()
    private static let ownershipLock = NSLock()
    private static var ownedPorts = Set<String>()
    private var ownedPath: String?
    private var generation: UInt64 = 0
    private var errorText: String?
    public var lastError: String? { ioLock.lock(); defer { ioLock.unlock() }; return errorText }
    private var isReading: Bool = false
    private let readQueue = DispatchQueue(label: "com.yaam.serialport.read", qos: .userInitiated)
    private var readCallback: (@Sendable (Data) -> Void)?
    // Immutable driver capability. Ordinary CAT and WinKeyer byte streams need neither line.
    private let allowedModemLines: Set<ModemLine>
    private let modemLineWriter: @Sendable (Int32, Bool, Int32) -> Int32
    private var managedModemBits: Int32 = 0

    public init(modemLines: Set<ModemLine> = []) {
        allowedModemLines = modemLines
        modemLineWriter = { fd, active, mask in
            Self.writeModemLines(fd: fd, active: active, mask: mask)
        }
    }

    // Test seam for observing the actual permission boundary without changing physical modem pins.
    init(modemLines: Set<ModemLine>, modemLineWriter: @escaping @Sendable (Int32, Bool, Int32) -> Int32) {
        allowedModemLines = modemLines
        self.modemLineWriter = modemLineWriter
    }

    private static func writeModemLines(fd: Int32, active: Bool, mask: Int32) -> Int32 {
        var bits = mask
        return active ? ioctl(fd, TIOCMBIS, &bits) : ioctl(fd, TIOCMBIC, &bits)
    }

    deinit {
        closePort()
    }

    // MARK: - Port Discovery

    public static func availablePorts(includeBluetooth: Bool = true) -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else {
            return []
        }
        return files
            .filter { name in
                guard name.hasPrefix("cu.") else { return false }
                if name.contains("wlan") || name.contains("debug-console") { return false }
                if !includeBluetooth && name.contains("Bluetooth") { return false }
                return true
            }
            .map { "/dev/\($0)" }
            .sorted()
    }

    public static func isBluetoothPort(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("bluetooth") || lower.contains("bt") || lower.contains("rfcomm")
    }

    public static func isUSBPort(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("usbserial") || lower.contains("usbmodem") || lower.contains("wchusb") || lower.contains("slab")
    }

    public var isOpen: Bool {
        ioLock.lock(); defer { ioLock.unlock() }
        return fileDescriptor >= 0
    }

    // MARK: - Open & Configure Port

    public func openPort(
        path: String,
        baudRate: Int = 1200,
        stopBits: Int = 1,
        onReceive: (@Sendable (Data) -> Void)? = nil
    ) -> Bool {
        ioLock.lock(); defer { ioLock.unlock() }
        closePort()
        errorText = nil

        self.readCallback = onReceive

        // cu/tty aliases for the same UART must not have two owners inside YAAM.
        let identity = URL(fileURLWithPath: path).resolvingSymlinksInPath().path.replacingOccurrences(of: "/dev/tty.", with: "/dev/cu.")
        Self.ownershipLock.lock()
        let available = Self.ownedPorts.insert(identity).inserted
        Self.ownershipLock.unlock()
        guard available else { errorText = "This serial port is already in use by another YAAM tool."; return false }
        ownedPath = identity
        // Open in non-blocking read-write mode
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            errorText = "Unable to open serial port: \(String(cString: strerror(errno)))."
            closePort()
            return false
        }
        self.fileDescriptor = fd
        guard ioctl(fd, TIOCEXCL) == 0 else {
            errorText = "Unable to obtain exclusive serial access."
            closePort()
            return false
        }

        // Configure termios
        var settings = termios()
        guard tcgetattr(fd, &settings) == 0 else {
            errorText = "Unable to configure serial port."
            closePort()
            return false
        }

        // Set raw mode
        cfmakeraw(&settings)

        // Set Baud Rate
        let speed: speed_t
        switch baudRate {
        case 1200: speed = speed_t(B1200)
        case 2400: speed = speed_t(B2400)
        case 4800: speed = speed_t(B4800)
        case 9600: speed = speed_t(B9600)
        case 19200: speed = speed_t(B19200)
        case 38400: speed = speed_t(B38400)
        case 57600: speed = speed_t(B57600)
        case 115200: speed = speed_t(B115200)
        default: speed = speed_t(B1200)
        }
        cfsetspeed(&settings, speed)

        // 8 Data Bits, Configurable Stop Bits (1 or 2), No Parity
        settings.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
        if stopBits == 2 {
            settings.c_cflag |= tcflag_t(CSTOPB)
        } else {
            settings.c_cflag &= ~tcflag_t(CSTOPB)
        }
        settings.c_cflag &= ~tcflag_t(PARENB | CRTSCTS)
        settings.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)

        // VMIN and VTIME for non-blocking read
        settings.c_cc.16 = 0 // VMIN
        settings.c_cc.17 = 1 // VTIME (100ms timeout)

        guard tcsetattr(fd, TCSANOW, &settings) == 0 else {
            errorText = "Unable to configure serial port."
            closePort()
            return false
        }

        // Clear existing input/output buffers
        tcflush(fd, TCIOFLUSH)

        startReading()
        return true
    }

    public func closePort() {
        ioLock.lock(); defer { ioLock.unlock() }
        generation &+= 1
        isReading = false
        if fileDescriptor >= 0 {
            // Bounded drain of already accepted bytes; never block indefinitely in tcdrain.
            let deadline = ProcessInfo.processInfo.systemUptime + 0.2
            while ProcessInfo.processInfo.systemUptime < deadline {
                var pending: Int32 = 0
                let result = ioctl(fileDescriptor, TIOCOUTQ, &pending)
                if result == 0 && pending == 0 { break }
                if result < 0 && errno != EINTR { errorText = "Serial output drain could not be verified."; break }
                usleep(1_000)
            }
            var pending: Int32 = 0
            if ioctl(fileDescriptor, TIOCOUTQ, &pending) == 0 && pending > 0 {
                errorText = "Serial output did not drain before disconnect; verify receive on the radio."
            }
            // Release only lines this driver actually controlled in this session. A CAT-only
            // connection must not change unrelated pins, even during cleanup or a failed open.
            if managedModemBits != 0, modemLineWriter(fileDescriptor, false, managedModemBits) != 0 {
                errorText = "Serial modem-line release failed; verify receive on the radio."
            }
            close(fileDescriptor)
            fileDescriptor = -1
        }
        managedModemBits = 0
        readCallback = nil
        if let ownedPath {
            Self.ownershipLock.lock()
            Self.ownedPorts.remove(ownedPath)
            Self.ownershipLock.unlock()
            self.ownedPath = nil
        }
    }

    // MARK: - Hardware Modem Control Lines (DTR & RTS)

    @discardableResult
    public func setDTR(active: Bool) -> Bool {
        setModemLine(.dtr, active: active)
    }

    @discardableResult
    public func setRTS(active: Bool) -> Bool {
        setModemLine(.rts, active: active)
    }

    private func setModemLine(_ line: ModemLine, active: Bool) -> Bool {
        ioLock.lock(); defer { ioLock.unlock() }
        guard allowedModemLines.contains(line) else {
            errorText = "This serial driver has not declared permission to control \(line == .dtr ? "DTR" : "RTS")."
            return false
        }
        guard fileDescriptor >= 0 else { return false }
        let bit = Int32(line == .dtr ? TIOCM_DTR : TIOCM_RTS)
        // An unsuccessful assertion can still leave physical state uncertain; retry release on close.
        managedModemBits |= bit
        guard modemLineWriter(fileDescriptor, active, bit) == 0 else {
            errorText = "Serial \(line == .dtr ? "DTR" : "RTS") change failed; verify the radio locally."
            return false
        }
        return true
    }

    public func getControlLines() -> (dtr: Bool, rts: Bool, cts: Bool, dsr: Bool, dcd: Bool, ri: Bool)? {
        ioLock.lock(); defer { ioLock.unlock() }
        guard fileDescriptor >= 0 else { return nil }
        var status: Int32 = 0
        guard ioctl(fileDescriptor, TIOCMGET, &status) == 0 else { return nil }
        return (
            dtr: (status & TIOCM_DTR) != 0,
            rts: (status & TIOCM_RTS) != 0,
            cts: (status & TIOCM_CTS) != 0,
            dsr: (status & TIOCM_DSR) != 0,
            dcd: (status & TIOCM_CAR) != 0,
            ri:  (status & TIOCM_RI) != 0
        )
    }

    // MARK: - Transmit Bytes

    @discardableResult
    public func writeData(_ data: Data) -> Bool {
        ioLock.lock(); defer { ioLock.unlock() }
        guard fileDescriptor >= 0 else { return false }
        if data.isEmpty { return true }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        return data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return false }
            var totalWritten = 0
            while totalWritten < data.count {
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    errorText = "Serial write timed out; command delivery is unconfirmed."
                    return false
                }
                let written = write(fileDescriptor, ptr.advanced(by: totalWritten), data.count - totalWritten)
                if written > 0 { totalWritten += written; continue }
                if written < 0 && errno == EINTR {
                    if ProcessInfo.processInfo.systemUptime < deadline { continue }
                } else if written == 0 || errno == EAGAIN || errno == EWOULDBLOCK {
                    if ProcessInfo.processInfo.systemUptime < deadline {
                        var item = pollfd(fd: fileDescriptor, events: Int16(POLLOUT), revents: 0)
                        _ = poll(&item, 1, 5)
                        continue
                    }
                }
                errorText = "Serial write failed or timed out; command delivery is unconfirmed."
                return false
            }
            return true
        }
    }

    // MARK: - Background Read Loop

    private func startReading() {
        guard readCallback != nil else { return }
        isReading = true
        let session = generation
        readQueue.async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 256)
            while let self {
                self.ioLock.lock()
                guard self.isReading, self.generation == session, self.fileDescriptor >= 0 else {
                    self.ioLock.unlock()
                    return
                }
                let count = read(self.fileDescriptor, &buffer, buffer.count)
                let callback = self.readCallback
                if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                    self.errorText = "Serial input failed; reconnect the radio."
                    self.closePort()
                    self.ioLock.unlock()
                    return
                }
                self.ioLock.unlock()
                if count > 0 { callback?(Data(buffer[0..<count])) }
                else { usleep(10_000) }
            }
        }
    }
}
