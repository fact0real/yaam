//
//  FT8EngineService.swift
//  YAAM
//

import Combine
import Foundation
import FT8Codec
import FT8808Engine

nonisolated enum FT8AudioPath: String, CaseIterable, Identifiable, Sendable {
    case icomLAN = "Direct Icom LAN"
    case coreAudio = "rigctld + Audio"

    var id: String { rawValue }
}

nonisolated enum FT8OperatingState: Equatable, Sendable {
    case idle
    case monitoring
    case waiting(Date)
    case transmitting
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .monitoring: return "Monitoring"
        case .waiting: return "Waiting for UTC slot"
        case .transmitting: return "Transmitting"
        case .failed: return "Needs attention"
        }
    }

    var isMonitoring: Bool {
        if case .monitoring = self { return true }
        if case .waiting = self { return true }
        return false
    }
}

nonisolated struct FT8BandPreset: Identifiable, Hashable, Sendable {
    let band: String
    let frequencyHz: UInt64

    var id: UInt64 { frequencyHz }
    var label: String { "\(band)  \(formattedMHz)" }
    var formattedMHz: String { AmateurBandPlan.formattedMHz(Double(frequencyHz) / 1_000_000) }

    static let common: [FT8BandPreset] = [
        .init(band: "160m", frequencyHz: 1_840_000),
        .init(band: "80m", frequencyHz: 3_573_000),
        .init(band: "60m", frequencyHz: 5_357_000),
        .init(band: "40m", frequencyHz: 7_074_000),
        .init(band: "30m", frequencyHz: 10_136_000),
        .init(band: "20m", frequencyHz: 14_074_000),
        .init(band: "17m", frequencyHz: 18_100_000),
        .init(band: "15m", frequencyHz: 21_074_000),
        .init(band: "12m", frequencyHz: 24_915_000),
        .init(band: "10m", frequencyHz: 28_074_000),
        .init(band: "6m", frequencyHz: 50_313_000)
    ]
}

nonisolated struct FT8DecodedRow: Identifiable, Sendable {
    let id: UUID
    let slotStart: Date
    let text: String
    let audioFrequencyHz: Float
    let timeOffset: Float
    let syncScore: Int
    let estimatedSNR: Float
    let parsed: QSOMessages.Parsed?
    let isDirectedToMe: Bool

    init(message: FT8Message, slotStart: Date, myCall: String) {
        id = UUID()
        self.slotStart = slotStart
        text = message.text
        audioFrequencyHz = message.frequencyHz
        timeOffset = message.timeSeconds
        syncScore = message.score
        estimatedSNR = message.snrDb
        parsed = QSOMessages.parse(message.text)
        isDirectedToMe = parsed?.toCall == myCall.uppercased()
    }
}

/// Converts Icom's 48 kHz network PCM stream into UTC-aligned decode slots and
/// bounded waterfall frames. Every mutable member is protected by `lock`.
nonisolated final class IcomFT8AudioSource: AudioSource, @unchecked Sendable {
    private let lock = NSLock()
    private var accumulator = SlotAccumulator(sampleRate: 48_000)
    private let spectrum = StreamingSpectrum(
        sampleRate: 48_000,
        fftSize: 8192,
        hop: 2048,
        fMin: 200,
        fMax: 3_000
    )
    private var slotSink: (@Sendable (AudioSlot) -> Void)?
    private var frameSink: (@Sendable (SpectrumFrame) -> Void)?

    func slots() -> AsyncStream<AudioSlot> {
        AsyncStream(AudioSlot.self, bufferingPolicy: .bufferingNewest(4)) { continuation in
            lock.lock()
            slotSink = { continuation.yield($0) }
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.slotSink = nil
                self.lock.unlock()
            }
        }
    }

    func frames() -> AsyncStream<SpectrumFrame> {
        AsyncStream(SpectrumFrame.self, bufferingPolicy: .bufferingNewest(2)) { continuation in
            lock.lock()
            frameSink = { continuation.yield($0) }
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.frameSink = nil
                self.lock.unlock()
            }
        }
    }

    func push(_ samples: [Float], at time: Date) {
        guard !samples.isEmpty else { return }
        lock.lock()
        let completed = accumulator.add(samples, at: time)
        var frames: [SpectrumFrame] = []
        spectrum.push(samples, at: time) { frames.append($0) }
        let slotEmit = slotSink
        let frameEmit = frameSink
        lock.unlock()

        if let completed { slotEmit?(completed) }
        if let frameEmit { frames.forEach(frameEmit) }
    }

    func finish() {
        lock.lock()
        slotSink = nil
        frameSink = nil
        lock.unlock()
    }
}

@MainActor
final class FT8EngineService: ObservableObject {
    @Published private(set) var state: FT8OperatingState = .idle
    @Published private(set) var status = "FT8 engine is ready"
    @Published private(set) var decodedRows: [FT8DecodedRow] = []
    @Published private(set) var waterfallRows: [[Float]] = []
    @Published private(set) var secondsToNextTX = 0.0
    @Published private(set) var transmitProgress: Float = 0
    @Published private(set) var selfTestStatus = "Not run"
    @Published private(set) var sequencePhase = "Manual"
    @Published private(set) var selectedDecodeID: UUID?
    @Published var audioPath: FT8AudioPath = .icomLAN
    @Published var dialFrequencyHz: UInt64 = 14_074_000
    @Published var txAudioFrequencyHz: Float = 1_500
    @Published var txGain: Float = 0.35
    @Published var txParity: SlotParity = .even
    @Published var txText = ""
    @Published var myCall = ""
    @Published var myGrid = ""
    @Published var transmitArmed = false {
        didSet {
            if !transmitArmed { cancelTransmission(reason: "Transmit disarmed") }
        }
    }
    @Published var autoSequenceEnabled = false
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var outputDevices: [AudioInputDevice] = []

    private var liveSource: LiveRadioSource?
    private var icomSource: IcomFT8AudioSource?
    private weak var activeIcom: IcomNetworkRadio?
    private weak var activeRig: RigControlClient?
    private var activeOutputDevice: String?
    private var decodeTask: Task<Void, Never>?
    private var waterfallTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var transmitTask: Task<Void, Never>?
    private var txOutput: TxAudioOutput?
    private var txPlayer: WaveformPlayer?
    private var sequencer: QSOSequencer?
    private var waterfallFrameCounter = 0

    init() {
        refreshAudioDevices()
        startClock()
    }

    deinit {
        decodeTask?.cancel()
        waterfallTask?.cancel()
        clockTask?.cancel()
        transmitTask?.cancel()
        liveSource?.stop()
        icomSource?.finish()
        txOutput?.stop()
    }

    func configureStation(callsign: String, grid: String) {
        myCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        myGrid = String(grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(4))
    }

    func refreshAudioDevices() {
        inputDevices = AudioDevices.inputDevices()
        outputDevices = AudioDevices.outputDevices()
    }

    func startIcomMonitoring(radio: IcomNetworkRadio) {
        stopMonitoring()
        guard radio.state.isConnected else {
            fail("Connect the Icom radio before starting FT8 monitoring.")
            return
        }

        audioPath = .icomLAN
        activeIcom = radio
        activeRig = nil
        let source = IcomFT8AudioSource()
        icomSource = source
        radio.setAudioSampleHandler { [weak source] samples, date in
            source?.push(samples, at: date)
        }
        launchDecode(source: source)
        launchWaterfall(frames: source.frames())
        state = .monitoring
        status = "Listening to 48 kHz audio from \(radio.radioName.isEmpty ? "Icom LAN" : radio.radioName)"
    }

    func startCoreAudioMonitoring(
        rig: RigControlClient,
        inputDevice: String?,
        outputDevice: String?
    ) {
        stopMonitoring()
        audioPath = .coreAudio
        activeRig = rig
        activeIcom = nil
        activeOutputDevice = cleanDevice(inputDevice: outputDevice)

        let source = LiveRadioSource(
            device: cleanDevice(inputDevice: inputDevice),
            slotSeconds: 15,
            fftSize: 2048,
            hop: 512,
            fMin: 200,
            fMax: 3_000
        )
        liveSource = source
        launchDecode(source: source)
        launchWaterfall(frames: source.frames())
        state = .monitoring
        status = "Listening to the selected Core Audio input"
    }

    func stopMonitoring() {
        decodeTask?.cancel()
        decodeTask = nil
        waterfallTask?.cancel()
        waterfallTask = nil
        liveSource?.stop()
        liveSource = nil
        icomSource?.finish()
        icomSource = nil
        activeIcom?.setAudioSampleHandler(nil)
        if transmitTask == nil {
            state = .idle
            status = "FT8 monitoring stopped"
        }
    }

    func clearDecodes() {
        decodedRows.removeAll(keepingCapacity: true)
        waterfallRows.removeAll(keepingCapacity: true)
        selectedDecodeID = nil
    }

    func applyDialAndMode() {
        switch audioPath {
        case .icomLAN:
            guard let activeIcom, activeIcom.state.isConnected else {
                fail("Connect the Icom radio first.")
                return
            }
            activeIcom.setFrequencyHz(dialFrequencyHz)
            activeIcom.setUSBDataMode()
            status = "Dial set to \(formattedDial) MHz in USB-D"
        case .coreAudio:
            guard let activeRig, activeRig.state.isConnected else {
                fail("Connect rigctld first.")
                return
            }
            activeRig.setFrequencyHz(dialFrequencyHz)
            activeRig.setMode("USB", passbandHz: 3_000)
            status = "Dial set to \(formattedDial) MHz through rigctld"
        }
    }

    func beginCQ() {
        guard validateIdentity() else { return }
        sequencer = QSOSequencer(callCQ: myCall, myGrid: myGrid)
        txText = sequencer?.message() ?? ""
        sequencePhase = "CQ"
        status = "CQ prepared; review the message and arm TX when ready"
    }

    func selectForReply(_ row: FT8DecodedRow) {
        guard validateIdentity(), let parsed = row.parsed, let dxCall = parsed.deCall, !dxCall.isEmpty else {
            fail("The selected decode is not a standard FT8 message with a callsign.")
            return
        }
        selectedDecodeID = row.id
        let heard = normalizedReport(row.estimatedSNR)
        if parsed.isCQ {
            sequencer = QSOSequencer(
                answer: dxCall,
                dxGrid: parsed.grid,
                heardSnr: heard,
                myCall: myCall,
                myGrid: myGrid
            )
        } else if parsed.toCall == myCall {
            sequencer = QSOSequencer(
                resuming: parsed,
                dxGrid: parsed.grid,
                heardSnr: heard,
                myCall: myCall,
                myGrid: myGrid
            )
        } else {
            fail("Choose a CQ or a message addressed to \(myCall).")
            return
        }
        txText = sequencer?.message() ?? ""
        sequencePhase = sequencer?.phase.rawValue ?? "Reply"
        txParity = SlotClock.parity(at: row.slotStart).toggled
        status = "Reply to \(dxCall) prepared for the opposite FT8 sequence"
    }

    func scheduleTransmission() {
        guard transmitTask == nil else { return }
        guard transmitArmed else {
            fail("Arm TX before scheduling an FT8 transmission.")
            return
        }
        guard validateIdentity() else { return }

        let message = txText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !message.isEmpty else {
            fail("Enter or prepare an FT8 message first.")
            return
        }

        let path = audioPath
        let audioFrequency = min(2_900, max(300, txAudioFrequencyHz))
        let gain = min(1, max(0.02, txGain))
        let parity = txParity
        let icom = activeIcom
        let rig = activeRig
        let outputDevice = activeOutputDevice

        switch path {
        case .icomLAN:
            guard let icom, icom.state.isConnected else {
                fail("The Icom LAN radio is not connected.")
                return
            }
            icom.transmitArmed = true
        case .coreAudio:
            guard let rig, rig.state.isConnected else {
                fail("rigctld is not connected, so PTT is unavailable.")
                return
            }
        }

        transmitTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sampleRate = 48_000
                let waveform = try await Task.detached(priority: .userInitiated) {
                    try FT8Codec.transmitAudio(
                        message,
                        baseFrequencyHz: audioFrequency,
                        protocol: .ft8,
                        sampleRate: sampleRate,
                        slotSeconds: 15
                    )
                }.value

                applyDialAndMode()
                let slot = SlotClock.nextSlotStart(parity: parity, after: Date())
                state = .waiting(slot)
                status = "TX queued for \(Self.utcTime(slot)) UTC"
                let keyAt = slot.addingTimeInterval(-0.20)
                let wait = keyAt.timeIntervalSinceNow
                if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
                try Task.checkCancellation()

                state = .transmitting
                transmitProgress = 0
                status = "Transmitting \(message)"
                switch path {
                case .icomLAN:
                    guard let icom else { throw IcomNetworkError.disconnected }
                    icom.setPTT(true, maximumDuration: 16)
                    defer {
                        icom.setPTT(false)
                        icom.transmitArmed = false
                    }
                    let progressTask = startProgressClock(duration: 15)
                    defer { progressTask.cancel() }
                    try await icom.transmit(samples: waveform, gain: gain)
                case .coreAudio:
                    guard let rig else { throw FT8RunError.rigUnavailable }
                    let player = WaveformPlayer(samples: waveform, amplitude: gain)
                    let output = TxAudioOutput(player: player, sampleRate: 48_000, device: outputDevice)
                    txPlayer = player
                    txOutput = output
                    rig.setPTT(true, maximumDuration: 16)
                    defer {
                        output.stop()
                        rig.setPTT(false)
                        txOutput = nil
                        txPlayer = nil
                    }
                    try output.start()
                    while !output.isFinished {
                        try Task.checkCancellation()
                        transmitProgress = player.progress
                        try await Task.sleep(for: .milliseconds(50))
                    }
                }

                transmitProgress = 1
                state = decodeTask == nil ? .idle : .monitoring
                status = "FT8 transmission completed; PTT released"
            } catch is CancellationError {
                releasePTT()
                state = decodeTask == nil ? .idle : .monitoring
                status = "FT8 transmission cancelled; PTT released"
            } catch {
                releasePTT()
                fail(error.localizedDescription)
            }
            transmitTask = nil
        }
    }

    func cancelTransmission(reason: String = "Transmission cancelled") {
        guard transmitTask != nil || state == .transmitting else { return }
        transmitTask?.cancel()
        transmitTask = nil
        txOutput?.stop()
        txOutput = nil
        txPlayer = nil
        releasePTT()
        transmitProgress = 0
        state = decodeTask == nil ? .idle : .monitoring
        status = reason
    }

    func runSelfTest() {
        selfTestStatus = "Running codec and timing checks..."
        Task { [weak self] in
            do {
                let passed = try await Task.detached(priority: .userInitiated) {
                    guard IcomNetworkRadio.protocolSelfTest() else { throw FT8RunError.civSelfTestFailed }
                    let message = "CQ K1ABC FN42"
                    let tones = try FT8Codec.encode(message, protocol: .ft8)
                    guard tones.count == 79 else { throw FT8RunError.codecSelfTestFailed }
                    let audio = try FT8Codec.transmitAudio(
                        message,
                        baseFrequencyHz: 1_500,
                        protocol: .ft8,
                        sampleRate: 12_000
                    )
                    guard audio.count == 180_000, audio.allSatisfy(\.isFinite) else {
                        throw FT8RunError.codecSelfTestFailed
                    }
                    let decoded = try FT8Codec.decode(
                        samples: audio,
                        sampleRate: 12_000,
                        protocol: .ft8,
                        maxMessages: 8
                    )
                    let next = SlotClock.nextSlotStart(parity: .even, after: Date())
                    guard next > Date(), SlotClock.parity(at: next) == .even else {
                        throw FT8RunError.clockSelfTestFailed
                    }
                    return decoded.contains { $0.text == message }
                }.value
                self?.selfTestStatus = passed
                    ? "Passed: CI-V, FT8 encode/decode, audio, and UTC slot clock"
                    : "FT8 loopback decode did not reproduce the test message"
            } catch {
                self?.selfTestStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    var formattedDial: String {
        AmateurBandPlan.formattedMHz(Double(dialFrequencyHz) / 1_000_000)
    }

    var selectedDecode: FT8DecodedRow? {
        decodedRows.first { $0.id == selectedDecodeID }
    }

    private func launchDecode<Source: AudioSource>(source: Source) {
        decodeTask = Task.detached(priority: .userInitiated) { [weak self] in
            let decoder = DecodeEngine(proto: .ft8, spectrumColumns: 120, passband: 200...3_000)
            for await result in decoder.results(from: source) {
                guard !Task.isCancelled else { break }
                await self?.consume(result)
            }
        }
    }

    private func launchWaterfall(frames: AsyncStream<SpectrumFrame>) {
        waterfallTask = Task.detached(priority: .utility) { [weak self] in
            for await frame in frames {
                guard !Task.isCancelled else { break }
                await self?.consume(frame)
            }
        }
    }

    private func consume(_ result: SlotResult) {
        let start = result.startTime ?? Date()
        let rows = result.messages.map { FT8DecodedRow(message: $0, slotStart: start, myCall: myCall) }
        if !rows.isEmpty {
            decodedRows.insert(contentsOf: rows, at: 0)
            if decodedRows.count > 250 { decodedRows.removeLast(decodedRows.count - 250) }
        }
        consumeSequence(rows)
        status = rows.isEmpty
            ? "Decoded UTC slot \(Self.utcTime(start)); no FT8 messages found"
            : "Decoded \(rows.count) FT8 message\(rows.count == 1 ? "" : "s") at \(Self.utcTime(start)) UTC"
    }

    private func consume(_ frame: SpectrumFrame) {
        waterfallFrameCounter += 1
        guard waterfallFrameCounter.isMultiple(of: 4) else { return }
        let normalized = normalizeSpectrum(frame.magnitudesDB)
        guard !normalized.isEmpty else { return }
        waterfallRows.append(normalized)
        if waterfallRows.count > 64 { waterfallRows.removeFirst(waterfallRows.count - 64) }
    }

    private func consumeSequence(_ rows: [FT8DecodedRow]) {
        guard var sequencer else { return }
        for row in rows {
            guard let parsed = row.parsed else { continue }
            if sequencer.receive(parsed, snr: normalizedReport(row.estimatedSNR)) {
                self.sequencer = sequencer
                sequencePhase = sequencer.phase.rawValue
                txText = sequencer.message() ?? ""
                if sequencer.isComplete {
                    autoSequenceEnabled = false
                    status = "FT8 exchange with \(sequencer.dxCall) is complete; review and log the QSO"
                } else if autoSequenceEnabled, transmitArmed, transmitTask == nil {
                    scheduleTransmission()
                }
                return
            }
        }
    }

    private func normalizeSpectrum(_ values: [Float]) -> [Float] {
        let finite = values.filter(\.isFinite).sorted()
        guard finite.count > 4 else { return [] }
        let floor = finite[finite.count / 5]
        let ceiling = max(floor + 18, finite[(finite.count * 19) / 20])
        return values.map { value in
            guard value.isFinite else { return 0 }
            return min(1, max(0, (value - floor) / (ceiling - floor)))
        }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                secondsToNextTX = SlotClock.secondsUntilNextSlot(parity: txParity, after: Date())
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func startProgressClock(duration: TimeInterval) -> Task<Void, Never> {
        let started = Date()
        return Task { [weak self] in
            while !Task.isCancelled {
                self?.transmitProgress = min(1, Float(Date().timeIntervalSince(started) / duration))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func releasePTT() {
        activeIcom?.setPTT(false)
        activeIcom?.transmitArmed = false
        activeRig?.setPTT(false)
    }

    private func validateIdentity() -> Bool {
        guard myCall.contains(where: \.isNumber), myCall.count >= 3 else {
            fail("Set a valid station callsign before operating FT8.")
            return false
        }
        guard myGrid.count == 4 else {
            fail("Set a valid four-character Maidenhead Grid in the active station profile.")
            return false
        }
        return true
    }

    private func normalizedReport(_ estimate: Float) -> Int {
        min(10, max(-30, Int(estimate.rounded())))
    }

    private func cleanDevice(inputDevice: String?) -> String? {
        guard let inputDevice else { return nil }
        let trimmed = inputDevice.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fail(_ message: String) {
        state = .failed(message)
        status = message
    }

    nonisolated private static func utcTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

nonisolated private enum FT8RunError: LocalizedError, Sendable {
    case rigUnavailable
    case civSelfTestFailed
    case codecSelfTestFailed
    case clockSelfTestFailed

    var errorDescription: String? {
        switch self {
        case .rigUnavailable: return "rigctld became unavailable during transmit."
        case .civSelfTestFailed: return "CI-V frequency encoding self-test failed."
        case .codecSelfTestFailed: return "FT8 codec self-test failed."
        case .clockSelfTestFailed: return "UTC slot clock self-test failed."
        }
    }
}
