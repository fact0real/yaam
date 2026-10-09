//
//  FLRigClient.swift
//  YAAM
//
//  Native XML-RPC Client for FLRig (W1HKJ Transceiver Control)
//  Connects over local HTTP XML-RPC to http://127.0.0.1:12345
//  Supports VFO A/B frequency polling, Mode, PTT, S-meter, and 1-click QSY.
//

import Combine
import Foundation

public enum FLRigError: LocalizedError {
    case noAnswer                 // no HTTP answer from flrig
    case fault(String)            // flrig answered HTTP 200 with a fault
    case nothingToSend
    case pttNotReleased(String)   // rig.set_ptt 0 was sent but flrig still reports PTT on, or the state could not be read

    public var errorDescription: String? {
        switch self {
        case .noAnswer: return "flrig did not answer."
        case .fault(let message): return "flrig refused the command: \(message)"
        case .nothingToSend: return "There is no text to send."
        case .pttNotReleased(let warning): return warning
        }
    }
}

@MainActor
public final class FLRigClient: ObservableObject {
    public static let shared = FLRigClient()

    // MARK: - Published State
    /// What flrig says (see FlrigLink). `isConnected` is true only while flrig reports a radio name: a flrig with
    /// no radio selected answers every query with made-up values (14.070 MHz, USB).
    @Published public private(set) var link: FlrigLink = .idle
    public var isConnected: Bool { link.isReporting }
    /// True from connect() to disconnect(), also while flrig has no radio or cannot be reached.
    @Published public private(set) var isPolling: Bool = false
    @Published public var host: String = "127.0.0.1"
    @Published public var port: Int = 12345
    @Published public var rigName: String = "FLRig Transceiver"
    @Published public var frequencyHz: Double = 14_074_000
    @Published public var mode: String = "USB"
    @Published public var isPTTActive: Bool = false
    @Published public var sMeter: Double = 0.0
    @Published public var powerWatts: Double = 100.0
    /// What is wrong, if anything: a command flrig refused (kept until flrig accepts a command or the link changes),
    /// else the problem with the link. Changed only when its text changes.
    @Published public var lastError: String? = nil
    /// Set when a release of PTT could not be confirmed: flrig still reports PTT on after rig.set_ptt 0, or YAAM could not
    /// read rig.get_ptt. Also part of lastError. Ends when a release is read back as off or the poll reads PTT off.
    @Published public private(set) var pttWarning: String? = nil
    @Published public var pollingInterval: TimeInterval = 0.5

    private var pollTimer: Timer?
    private var pollGeneration = 0          // +1 at every stopPolling(): polls of an older generation are dropped
    private var activePollGeneration: Int?   // the generation of the poll that is waiting for flrig, if any
    private let chain = FlrigCommandChain()
    private var errors = FlrigErrorState()
    private let urlSession: URLSession
    private let userAgent = "YAAM-macOS-FLRigClient/1.0"

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 3.0
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Connect & Disconnect

    public func connect(host: String = "127.0.0.1", port: Int = 12345) {
        self.host = host
        self.port = port
        link = .idle
        errors = FlrigErrorState()
        lastError = nil
        pttWarning = nil
        startPolling()
    }

    public func disconnect() {
        stopPolling()
        link = .idle
        errors = FlrigErrorState()
        lastError = nil
        pttWarning = nil
    }

    public func startPolling() {
        stopPolling()
        isPolling = true
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollRigStatus()
            }
        }
        Task { @MainActor in
            await self.pollRigStatus()
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
        pollGeneration += 1      // a poll that is still waiting for flrig must not apply its result
    }

    // MARK: - Status Polling Loop

    public func pollRigStatus() async {
        let generation = pollGeneration
        guard activePollGeneration != generation else { return }
        activePollGeneration = generation
        defer { if activePollGeneration == generation { activePollGeneration = nil } }
        do {
            try await poll(generation)
        } catch {
            // Disconnected (or connected again) while a request was in flight: leave everything as it is.
        }
    }

    private func poll(_ generation: Int) async throws {
        // 1. Who answers? rig.get_xcvr does not touch the radio. With no radio (NONE, or "" when it never answered)
        //    the other queries return made-up values, so they are not read and YAAM is not "connected".
        let newLink = FlrigXMLRPC.link(forXcvr: try await query(.getXcvr, generation))
        if newLink != link {
            link = newLink
            errors.linkChanged()
            logOnce(newLink.problem)
            publishError()
        }
        guard newLink.isReporting else { return }

        // 2. VFO, 3. mode, 4. S-meter, 5. PTT. A fault or a missing answer leaves the old value; it is never read as data.
        if let freq = try await query(.getVFO, generation)?.text.flatMap({ Double($0) }), freq > 0 { frequencyHz = freq }
        if let newMode = try await query(.getMode, generation)?.text, !newMode.isEmpty { mode = newMode }
        if let sm = try await query(.getSmeter, generation)?.text.flatMap({ Double($0) }) { sMeter = sm }
        if let ptt = try await query(.getPTT, generation)?.text.flatMap({ Int($0) }) {
            isPTTActive = (ptt == 1)
            // flrig reporting PTT off ends a warning that the radio may be keyed (see pttWarning).
            if errors.pttObserved(keyed: ptt == 1) { publishError() }
        }
    }

    // MARK: - Control Commands (1-Click QSY & Mode)

    public func setFrequency(hz: Double) async throws {
        try await run(.setVFO(hz: hz))
        self.frequencyHz = hz
    }

    public func setMode(_ newMode: String) async throws {
        try await run(.setMode(newMode))
        self.mode = newMode
    }

    /// PTT on, or off. Off is read back and repeated if flrig still reports PTT on (FlrigPTTRelease); it throws
    /// .pttNotReleased when that did not work or the state could not be read, and the warning stays in pttWarning.
    public func setPTT(active: Bool) async throws {
        try await run(.setPTT(active))
        if active { self.isPTTActive = true }
    }

    /// CW through flrig's own keyer (cwio): set the speed, then queue "[text]". flrig makes the Morse timing itself
    /// and keys the line (a DTR or RTS line of a serial port) set in flrig's "CW keying" window. If flrig has no CW
    /// line configured it still answers without an error and nothing is keyed.
    public func sendMorse(_ text: String, wpm: Int? = nil) async throws {
        guard FlrigCommand.cwText(text) != nil else { throw FLRigError.nothingToSend }
        let (host, port, session, agent) = (self.host, self.port, self.urlSession, self.userAgent)
        let outcome = await chain.enqueue {
            let outcome = await FlrigSequences.sendCW(text, wpm: wpm) { command in
                await FlrigTransport.sendUncancelled(command, host: host, port: port, session: session, userAgent: agent)
            }
            await self.report(outcome)
            return outcome
        }.value
        try finish(outcome)
    }

    /// Stop CW: drop the queued text (the letter in progress is finished) and release PTT, read back and repeated if
    /// flrig still reports PTT on. The next message starts 150 ms after this one, because flrig empties its text box
    /// a moment after the stop.
    public func stopMorse() async throws {
        let (host, port, session, agent) = (self.host, self.port, self.urlSession, self.userAgent)
        let outcome = await chain.enqueue {
            let outcome = await FlrigSequences.stopCW(send: { command in
                await FlrigTransport.sendUncancelled(command, host: host, port: port, session: session, userAgent: agent)
            }, pause: { try? await Task.sleep(nanoseconds: $0) })
            await self.report(outcome)
            return outcome
        }.value
        try finish(outcome)
    }

    // MARK: - XML-RPC Transport

    /// A query during a poll: the reply, or nil for no usable answer. A fault comes back as .fault, never as a value,
    /// and is kept as the error. Throws when the poll is no longer wanted (disconnected, or connected again).
    private func query(_ command: FlrigCommand, _ generation: Int) async throws -> FlrigReply? {
        let reply = try await FlrigTransport.send(command, host: host, port: port, session: urlSession, userAgent: userAgent)
        try Task.checkCancellation()
        guard generation == pollGeneration, isPolling else { throw CancellationError() }
        if case .fault(_, let message)? = reply {
            errors.refused(command.method, message)
            logOnce(errors.commandFault)
            publishError()
        }
        return reply
    }

    /// A set command, behind every command issued before it. rig.set_ptt 0 is read back and repeated inside the same
    /// job (FlrigPTTRelease), so the release stays the last command and nothing is sent between it and its checks.
    private func run(_ command: FlrigCommand) async throws {
        let (host, port, session, agent) = (self.host, self.port, self.urlSession, self.userAgent)
        let outcome = await chain.enqueue {
            let send: FlrigSequences.Send = { await FlrigTransport.sendUncancelled($0, host: host, port: port, session: session, userAgent: agent) }
            let outcome: FlrigOutcome
            if command.isPTTRelease {
                outcome = await FlrigPTTRelease.release(send: send, pause: { try? await Task.sleep(nanoseconds: $0) })
            } else {
                outcome = FlrigOutcome(method: command.method, reply: await send(command))
            }
            await self.report(outcome)
            return outcome
        }.value
        try finish(outcome)
    }

    /// Keeps a fault as the error until flrig accepts a command or the link changes. A release that flrig did not
    /// confirm is kept as a warning and written to the system log.
    private func report(_ outcome: FlrigOutcome?) {
        guard let outcome else { return }
        errors.record(outcome)
        logOnce(errors.commandFault)
        if let line = outcome.releaseCheck?.logLine { NSLog("[flrig] %@", line) }
        switch outcome.releaseCheck {
        case .released?: isPTTActive = false
        case .stillKeyed?: isPTTActive = true     // flrig reports PTT on
        case .unknown?, nil: break                // not known: left as it was
        }
        publishError()
    }

    private func finish(_ outcome: FlrigOutcome?) throws {
        switch outcome?.reply {
        case .fault(_, let message)?: throw FLRigError.fault(message)
        case .malformed?, nil: throw FLRigError.noAnswer
        case .value?: break
        }
        if let warning = outcome?.releaseCheck?.warning { throw FLRigError.pttNotReleased(warning) }
    }

    /// lastError changes only when its text changes, so a problem that persists is not published at every poll.
    private func publishError() {
        let text = errors.text(for: link)
        if text != lastError { lastError = text }
        if errors.pttWarning != pttWarning { pttWarning = errors.pttWarning }
    }

    /// Writes a problem to the system log once, not at every poll.
    private func logOnce(_ problem: String?) {
        if let line = errors.newProblemToLog(problem) { NSLog("[flrig] %@", line) }
    }
}
