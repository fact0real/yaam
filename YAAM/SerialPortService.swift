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

public final class SerialPortService: @unchecked Sendable {
    public static let shared = SerialPortService()

    private var fileDescriptor: Int32 = -1
    private var isReading: Bool = false
    private let readQueue = DispatchQueue(label: "com.yaam.serialport.read", qos: .userInitiated)
    private var readCallback: (@Sendable (Data) -> Void)?

    public init() {}

    deinit {
        closePort()
    }

    // MARK: - Port Discovery

    public static func availablePorts() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else {
            return []
        }
        return files
            .filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && !$0.contains("wlan") }
            .map { "/dev/\($0)" }
            .sorted()
    }

    public var isOpen: Bool {
        fileDescriptor >= 0
    }

    // MARK: - Open & Configure Port

    public func openPort(
        path: String,
        baudRate: Int = 1200,
        onReceive: (@escaping @Sendable (Data) -> Void)
    ) -> Bool {
        closePort()

        self.readCallback = onReceive

        // Open in non-blocking read-write mode
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            return false
        }
        self.fileDescriptor = fd

        // Configure termios
        var settings = termios()
        guard tcgetattr(fd, &settings) == 0 else {
            close(fd)
            self.fileDescriptor = -1
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

        // 8 Data Bits, 1 Stop Bit, No Parity
        settings.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
        settings.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        settings.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)

        // VMIN and VTIME for non-blocking read
        settings.c_cc.16 = 0 // VMIN
        settings.c_cc.17 = 1 // VTIME (100ms timeout)

        guard tcsetattr(fd, TCSANOW, &settings) == 0 else {
            close(fd)
            self.fileDescriptor = -1
            return false
        }

        // Clear existing input/output buffers
        tcflush(fd, TCIOFLUSH)

        startReading()
        return true
    }

    public func closePort() {
        isReading = false
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
        readCallback = nil
    }

    // MARK: - Transmit Bytes

    @discardableResult
    public func writeData(_ data: Data) -> Bool {
        guard fileDescriptor >= 0 else { return false }
        return data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return false }
            var totalWritten = 0
            while totalWritten < data.count {
                let written = write(fileDescriptor, ptr.advanced(by: totalWritten), data.count - totalWritten)
                if written <= 0 {
                    return false
                }
                totalWritten += written
            }
            return true
        }
    }

    // MARK: - Background Read Loop

    private func startReading() {
        isReading = true
        readQueue.async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 256)
            while let self = self, self.isReading, self.fileDescriptor >= 0 {
                let bytesRead = read(self.fileDescriptor, &buffer, buffer.count)
                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    self.readCallback?(data)
                } else {
                    usleep(10_000) // 10ms poll
                }
            }
        }
    }
}
