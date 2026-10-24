import Foundation
import Network

/// One reader per TCP connection. Every request uses Hamlib's extended response protocol,
/// so a failed poll cannot be mistaken for the acknowledgement of a PTT or CW release.
@MainActor
final class RigctldReplyStream {
    struct Reply {
        let command: String
        let arguments: String
        let fields: [String: String]
        let result: Int
    }
    let connection: NWConnection
    var onReply: ((Reply) -> Void)?
    var onError: ((String, Bool) -> Void)?
    var onFailure: ((String, Bool) -> Void)?
    private var unanswered: [TimeInterval] = []
    private var freshnessTask: Task<Void, Never>?
    private var pttActive = false
    private var cwActive = false
    private var transmitEpoch = 0
    private var releaseEpochs: [String: Int] = [:]
    var transmitActive: Bool { pttActive || cwActive }
    private(set) var pendingReleases: [String: UUID] = [:]
    var hasTransmitRisk: Bool { transmitActive || !pendingReleases.isEmpty }
    private var buffer = Data()
    private var responseBytes = 0
    private var command = "", arguments = ""
    private var fields: [String: String] = [:]
    private var reading = false
    private var finished = false
    private var closingCommand: String?

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        guard !reading, !finished else { return }
        reading = true
        freshnessTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, !self.finished else { return }
                if let oldest = self.unanswered.first, ProcessInfo.processInfo.systemUptime - oldest >= 3 {
                    self.fail("rigctld stopped answering commands (3 s reply deadline)")
                    return
                }
            }
        }
        receive()
    }

    func send(_ raw: String, closeAfterRelease: Bool = false) {
        if closeAfterRelease { closingCommand = "set_ptt" }
        for rawLine in raw.split(separator: "\n") {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let plain = line.hasPrefix("+") ? String(line.dropFirst()) : line
            let release: String? = plain == "T 0" ? "set_ptt" : (plain == "\\stop_morse" ? "stop_morse" : nil)
            if closingCommand != nil && !closeAfterRelease && release == nil {
                onError?("\(plain) was not sent; the original connection is retiring", transmitActive)
                continue
            }
            if finished {
                onError?("\(plain) was not sent; the original connection is closed", release != nil || transmitActive)
                continue
            }
            guard unanswered.count < 256 else { fail("too many unanswered rigctld commands"); return }
            unanswered.append(ProcessInfo.processInfo.systemUptime)
            if plain == "T 1" { pttActive = true; transmitEpoch &+= 1 }
            if plain.hasPrefix("b ") { cwActive = true; transmitEpoch &+= 1 }
            if let release {
                let id = UUID()
                pendingReleases[release] = id
                releaseEpochs[release] = transmitEpoch
                // This task keeps a retiring session alive until acknowledgement or timeout.
                Task { @MainActor [self] in
                    try? await Task.sleep(for: .seconds(1.5))
                    guard pendingReleases[release] == id else { return }
                    pendingReleases[release] = nil
                    clearTransmit(for: release)
                    onError?("\(plain) acknowledgement timed out; receive is unconfirmed", true)
                    if closingCommand == release { finish() }
                }
            }
            connection.send(content: Data(("+" + plain + "\n").utf8), completion: .contentProcessed { [self] error in
                guard let error else { return }
                Task { @MainActor [self] in
                    let safety = release != nil || self.transmitActive
                    if let release {
                        self.pendingReleases[release] = nil
                        self.clearTransmit(for: release)
                    }
                    self.onError?("\(plain) write failed: \(error.localizedDescription)", safety)
                    if self.closingCommand != nil { self.finish() }
                }
            })
        }
    }

    private func clearTransmit(for release: String) {
        guard releaseEpochs.removeValue(forKey: release) == transmitEpoch else { return }
        if release == "set_ptt" { pttActive = false }
        if release == "stop_morse" { cwActive = false }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, !self.finished else { return }
                if let data { self.consume(data) }
                if error != nil || complete {
                    self.fail("the reply connection was lost")
                } else if !self.finished { self.receive() }
            }
        }
    }

    func fail(_ reason: String) {
        guard !finished, closingCommand == nil else { return }
        let risk = hasTransmitRisk
        onError?(reason, risk)
        if risk {
            // A silent reply stream may still accept writes. Release its original radio before retiring it;
            // the existing release deadline bounds how long this session stays alive.
            buffer.removeAll(); responseBytes = 0; command = ""; arguments = ""; fields = [:]
            send("\\stop_morse\nT 0\n", closeAfterRelease: true)
        } else { finish() }
        onFailure?(reason, risk)
    }

    func finish() {
        finished = true
        freshnessTask?.cancel()
        freshnessTask = nil
        unanswered.removeAll()
        pendingReleases.removeAll()
        connection.cancel()
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 65_536 else { fail("oversized rigctld reply"); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...newline)
            responseBytes += line.utf8.count + 1
            guard responseBytes <= 65_536 else { fail("oversized rigctld response"); return }
            if line.hasPrefix("RPRT "), let result = Int(line.dropFirst(5)) {
                if !unanswered.isEmpty { unanswered.removeFirst() }
                let reply = Reply(command: command, arguments: arguments, fields: fields, result: result)
                let isRelease = (command == "set_ptt" && arguments == "0") || command == "stop_morse"
                if isRelease {
                    pendingReleases[command] = nil
                    clearTransmit(for: command)
                }
                if result != 0 {
                    onError?("rigctld refused \(command.isEmpty ? "an unframed command" : command) \(arguments) (RPRT \(result))", isRelease || transmitActive)
                }
                onReply?(reply)
                command = ""; arguments = ""; fields = [:]; responseBytes = 0
                if isRelease && closingCommand == reply.command { finish(); return }
            } else if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon])
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if key.first?.isLowercase == true {
                    command = key; arguments = value; fields = [:]
                } else { fields[key] = value }
            }
        }
    }
}
