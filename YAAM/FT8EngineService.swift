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

nonisolated func calculateMaidenheadDistanceKm(grid1: String, grid2: String) -> Double? {
    func parseGrid(_ grid: String) -> (lat: Double, lon: Double)? {
        let clean = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 4 else { return nil }
        let chars = Array(clean)
        guard chars[0] >= "A" && chars[0] <= "R",
              chars[1] >= "A" && chars[1] <= "R",
              chars[2] >= "0" && chars[2] <= "9",
              chars[3] >= "0" && chars[3] <= "9" else { return nil }
        let lonField = Double(chars[0].asciiValue! - Character("A").asciiValue!) * 20.0 - 180.0
        let latField = Double(chars[1].asciiValue! - Character("A").asciiValue!) * 10.0 - 90.0
        let lonSquare = Double(chars[2].asciiValue! - Character("0").asciiValue!) * 2.0
        let latSquare = Double(chars[3].asciiValue! - Character("0").asciiValue!) * 1.0
        var lon = lonField + lonSquare + 1.0
        var lat = latField + latSquare + 0.5
        if clean.count >= 6, chars[4] >= "A" && chars[4] <= "X", chars[5] >= "A" && chars[5] <= "X" {
            let lonSub = Double(chars[4].asciiValue! - Character("A").asciiValue!) * (5.0 / 60.0)
            let latSub = Double(chars[5].asciiValue! - Character("A").asciiValue!) * (2.5 / 60.0)
            lon = lonField + lonSquare + lonSub + (2.5 / 60.0)
            lat = latField + latSquare + latSub + (1.25 / 60.0)
        }
        return (lat, lon)
    }

    guard let c1 = parseGrid(grid1), let c2 = parseGrid(grid2) else { return nil }
    let earthRadiusKm = 6371.0
    let dLat = (c2.lat - c1.lat) * .pi / 180.0
    let dLon = (c2.lon - c1.lon) * .pi / 180.0
    let lat1Rad = c1.lat * .pi / 180.0
    let lat2Rad = c2.lat * .pi / 180.0
    let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earthRadiusKm * c
}

nonisolated func resolveCountryAndFlag(for callsign: String) -> (name: String, flag: String) {
    let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !clean.isEmpty else { return ("Unknown", "🌐") }
    let flag = flagFromCallsignPrefix(clean) ?? "🌐"

    if clean.hasPrefix("RI1F") { return ("Franz Josef Land", flag) }
    if clean.hasPrefix("RI1A") || clean.hasPrefix("DP0") || clean.hasPrefix("CE9") { return ("Antarctica", flag) }
    if clean.hasPrefix("SV9") { return ("Crete", flag) }
    if clean.hasPrefix("SV5") { return ("Dodecanese", flag) }
    if clean.hasPrefix("SV") || clean.hasPrefix("SW") || clean.hasPrefix("SX") || clean.hasPrefix("SY") { return ("Greece", flag) }
    if clean.hasPrefix("E7") { return ("Bosnia-Herzegovina", flag) }
    if clean.hasPrefix("IZ") || clean.hasPrefix("IK") || clean.hasPrefix("IU") || clean.hasPrefix("I") { return ("Italy", flag) }
    if clean.hasPrefix("EA") || clean.hasPrefix("EB") || clean.hasPrefix("EC") { return ("Spain", flag) }
    if clean.hasPrefix("JA") || clean.hasPrefix("JH") || clean.hasPrefix("JR") || clean.hasPrefix("JG") || clean.hasPrefix("JE") || clean.hasPrefix("JF") || clean.hasPrefix("7") || clean.hasPrefix("8") { return ("Japan", flag) }
    if clean.hasPrefix("UA") || clean.hasPrefix("RA") || clean.hasPrefix("RW") || clean.hasPrefix("RX") || clean.hasPrefix("R") {
        return (clean.contains("9") || clean.contains("0") ? "Asiatic Russia" : "European Russia", flag)
    }
    if clean.hasPrefix("UR") || clean.hasPrefix("US") || clean.hasPrefix("UT") { return ("Ukraine", flag) }
    if clean.hasPrefix("SP") || clean.hasPrefix("SN") || clean.hasPrefix("SO") || clean.hasPrefix("SQ") { return ("Poland", flag) }
    if clean.hasPrefix("DL") || clean.hasPrefix("DJ") || clean.hasPrefix("DK") || clean.hasPrefix("DF") || clean.hasPrefix("DG") { return ("Germany", flag) }
    if clean.hasPrefix("F") || clean.hasPrefix("TM") { return ("France", flag) }
    if clean.hasPrefix("G") || clean.hasPrefix("M") || clean.hasPrefix("2") { return ("England", flag) }
    if clean.hasPrefix("HA") || clean.hasPrefix("HG") { return ("Hungary", flag) }
    if clean.hasPrefix("OE") { return ("Austria", flag) }
    if clean.hasPrefix("OK") || clean.hasPrefix("OL") { return ("Czech Republic", flag) }
    if clean.hasPrefix("OM") { return ("Slovakia", flag) }
    if clean.hasPrefix("ON") || clean.hasPrefix("OO") { return ("Belgium", flag) }
    if clean.hasPrefix("PA") || clean.hasPrefix("PB") || clean.hasPrefix("PD") || clean.hasPrefix("PE") || clean.hasPrefix("PI") { return ("Netherlands", flag) }
    if clean.hasPrefix("SM") || clean.hasPrefix("SA") || clean.hasPrefix("SK") { return ("Sweden", flag) }
    if clean.hasPrefix("OH") || clean.hasPrefix("OG") { return ("Finland", flag) }
    if clean.hasPrefix("LA") || clean.hasPrefix("LB") { return ("Norway", flag) }
    if clean.hasPrefix("OZ") { return ("Denmark", flag) }
    if clean.hasPrefix("HB9") || clean.hasPrefix("HB0") { return ("Switzerland", flag) }
    if clean.hasPrefix("YO") || clean.hasPrefix("YP") { return ("Romania", flag) }
    if clean.hasPrefix("LZ") { return ("Bulgaria", flag) }
    if clean.hasPrefix("YU") || clean.hasPrefix("YT") { return ("Serbia", flag) }
    if clean.hasPrefix("9A") { return ("Croatia", flag) }
    if clean.hasPrefix("S5") { return ("Slovenia", flag) }
    if clean.hasPrefix("Z3") { return ("North Macedonia", flag) }
    if clean.hasPrefix("TA") || clean.hasPrefix("TC") { return ("Turkey", flag) }
    if clean.hasPrefix("4X") || clean.hasPrefix("4Z") { return ("Israel", flag) }
    if clean.hasPrefix("A6") { return ("United Arab Emirates", flag) }
    if clean.hasPrefix("A4") { return ("Oman", flag) }
    if clean.hasPrefix("A7") { return ("Qatar", flag) }
    if clean.hasPrefix("A9") { return ("Bahrain", flag) }
    if clean.hasPrefix("HZ") || clean.hasPrefix("7Z") { return ("Saudi Arabia", flag) }
    if clean.hasPrefix("9K") { return ("Kuwait", flag) }
    if clean.hasPrefix("EP") || clean.hasPrefix("EQ") { return ("Iran", flag) }
    if clean.hasPrefix("BY") || clean.hasPrefix("BA") || clean.hasPrefix("BG") || clean.hasPrefix("BD") { return ("China", flag) }
    if clean.hasPrefix("HL") || clean.hasPrefix("DS") { return ("South Korea", flag) }
    if clean.hasPrefix("BV") { return ("Taiwan", flag) }
    if clean.hasPrefix("VR2") { return ("Hong Kong", flag) }
    if clean.hasPrefix("VU") { return ("India", flag) }
    if clean.hasPrefix("HS") || clean.hasPrefix("E2") { return ("Thailand", flag) }
    if clean.hasPrefix("YB") || clean.hasPrefix("YC") { return ("Indonesia", flag) }
    if clean.hasPrefix("9M") { return ("Malaysia", flag) }
    if clean.hasPrefix("9V") { return ("Singapore", flag) }
    if clean.hasPrefix("VK") { return ("Australia", flag) }
    if clean.hasPrefix("ZL") { return ("New Zealand", flag) }
    if clean.hasPrefix("K") || clean.hasPrefix("W") || clean.hasPrefix("N") || clean.hasPrefix("AA") || clean.hasPrefix("AB") || clean.hasPrefix("AC") || clean.hasPrefix("AD") || clean.hasPrefix("AE") || clean.hasPrefix("AF") || clean.hasPrefix("AG") || clean.hasPrefix("AI") || clean.hasPrefix("AJ") || clean.hasPrefix("AK") { return ("United States", flag) }
    if clean.hasPrefix("VE") || clean.hasPrefix("VA") || clean.hasPrefix("VO") || clean.hasPrefix("VY") { return ("Canada", flag) }
    if clean.hasPrefix("XE") || clean.hasPrefix("XF") { return ("Mexico", flag) }
    if clean.hasPrefix("LU") || clean.hasPrefix("LW") { return ("Argentina", flag) }
    if clean.hasPrefix("PY") || clean.hasPrefix("PP") || clean.hasPrefix("PR") || clean.hasPrefix("PU") { return ("Brazil", flag) }
    if clean.hasPrefix("CE") { return ("Chile", flag) }
    if clean.hasPrefix("CX") { return ("Uruguay", flag) }
    if clean.hasPrefix("OA") { return ("Peru", flag) }
    if clean.hasPrefix("YV") { return ("Venezuela", flag) }
    if clean.hasPrefix("ZS") || clean.hasPrefix("ZR") { return ("South Africa", flag) }
    if clean.hasPrefix("5Z") { return ("Kenya", flag) }
    if clean.hasPrefix("CN") { return ("Morocco", flag) }
    if clean.hasPrefix("UN") || clean.hasPrefix("UP") || clean.hasPrefix("UQ") { return ("Kazakhstan", flag) }
    return ("International", flag)
}

public struct FT8OpportunityAlert: Identifiable, Sendable {
    public let id = UUID()
    public let callsign: String
    public let entityName: String
    public let flag: String
    public let continent: String
    public let grid: String
    public let frequencyHz: Float
    public let snrDb: Float
    public let isNewDXCC: Bool
    public let isNewGrid: Bool
    public let timestamp: Date = Date()
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
    let isCQ: Bool
    let callerCall: String?
    let callerGrid: String?
    let countryName: String
    let countryFlag: String
    let continent: String
    let distanceKm: Double?
    var isNewDXCC: Bool
    var isNewGrid: Bool
    var isNewCall: Bool

    init(message: FT8Message, slotStart: Date, myCall: String, myGrid: String = "") {
        self.id = UUID()
        self.slotStart = slotStart
        self.text = message.text
        self.audioFrequencyHz = message.frequencyHz
        self.timeOffset = message.timeSeconds
        self.syncScore = message.score
        self.estimatedSNR = message.snrDb
        let p = QSOMessages.parse(message.text)
        self.parsed = p
        self.isDirectedToMe = p?.toCall == myCall.uppercased()
        self.isCQ = p?.isCQ == true || message.text.hasPrefix("CQ ")
        let caller = p?.deCall ?? Self.extractCaller(from: message.text)
        self.callerCall = caller
        self.callerGrid = p?.grid
        if let caller, !caller.isEmpty {
            let info = DXCCDatabase.resolve(callsign: caller)
            self.countryName = info.entityName
            self.countryFlag = info.flagEmoji
            self.continent = info.continent
        } else {
            self.countryName = ""
            self.countryFlag = "🌐"
            self.continent = "??"
        }
        if let g = p?.grid, !g.isEmpty, !myGrid.isEmpty {
            self.distanceKm = calculateMaidenheadDistanceKm(grid1: myGrid, grid2: g)
        } else {
            self.distanceKm = nil
        }
        self.isNewDXCC = false
        self.isNewGrid = false
        self.isNewCall = false
    }

    private static func extractCaller(from msg: String) -> String? {
        let parts = msg.split(separator: " ").map(String.init)
        if parts.count >= 2 && parts[0] == "CQ" {
            return parts.count >= 3 && parts[1].count <= 3 ? parts[2] : parts[1]
        }
        return parts.first
    }
}

nonisolated struct FT8SignalPeak: Identifiable, Sendable {
    let id: UUID
    let callsign: String
    let frequencyHz: Float
    let snrDb: Float
    let isCQ: Bool
    let isDirectedToMe: Bool
    let timestamp: Date

    init(callsign: String, frequencyHz: Float, snrDb: Float, isCQ: Bool, isDirectedToMe: Bool, timestamp: Date = Date()) {
        self.id = UUID()
        self.callsign = callsign
        self.frequencyHz = frequencyHz
        self.snrDb = snrDb
        self.isCQ = isCQ
        self.isDirectedToMe = isDirectedToMe
        self.timestamp = timestamp
    }
}

nonisolated struct FT8TxLogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let audioFrequencyHz: Float
    let text: String
    let targetCall: String?

    init(timestamp: Date = Date(), audioFrequencyHz: Float, text: String, targetCall: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.audioFrequencyHz = audioFrequencyHz
        self.text = text
        self.targetCall = targetCall
    }
}

nonisolated enum FT8StreamItem: Identifiable, Sendable {
    case rx(FT8DecodedRow)
    case tx(FT8TxLogEntry)
    case status(id: UUID, time: Date, text: String, isMilestone: Bool)

    var id: UUID {
        switch self {
        case .rx(let r): return r.id
        case .tx(let t): return t.id
        case .status(let id, _, _, _): return id
        }
    }

    var timestamp: Date {
        switch self {
        case .rx(let r): return r.slotStart
        case .tx(let t): return t.timestamp
        case .status(_, let time, _, _): return time
        }
    }
}

nonisolated enum SmartHunterCriteria: String, CaseIterable, Identifiable, Sendable {
    case newDXCC = "New DXCC First"
    case maxDistance = "Max Distance (DX)"
    case maxSNR = "Strongest Signal (Max SNR)"
    case newGrid = "New Grid First"
    case firstInSlot = "First in Slot"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .newDXCC: return "globe.americas.fill"
        case .maxDistance: return "arrow.up.right.and.arrow.down.left.rectangle.fill"
        case .maxSNR: return "antenna.radiowaves.left.and.right"
        case .newGrid: return "square.grid.3x3.fill"
        case .firstInSlot: return "forward.fill"
        }
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

    // ─── Operational Properties for Dual-Pane Console & Spectrum ───
    @Published var rxAudioFrequencyHz: Float = 1_500
    @Published var dxCall = ""
    @Published var dxGrid = ""
    @Published var dxReport = "-10"
    @Published var lockTxRxFreq = false
    @Published var isCallingCQContinually = false
    @Published var resumeCQAfterQSO = false
    @Published private(set) var qsoStreamItems: [FT8StreamItem] = []
    @Published private(set) var activeSignalPeaks: [FT8SignalPeak] = []
    @Published private(set) var latestSpectrumMagnitudes: [Float] = []

    // ─── Smart Auto-Hunter Engine ───
    @Published var autoHunterEnabled = false
    @Published var autoHunterCriteria: SmartHunterCriteria = .newDXCC
    @Published var autoHunterMinSNR: Int = -20
    @Published var autoHunterSkipWorked = true
    @Published var autoHunterContinent = "ALL"
    @Published private(set) var autoHunterStatus = "Auto-Hunter standby"

    @Published private(set) var latestOpportunityAlert: FT8OpportunityAlert?
    @Published private(set) var clockSkewAlert: String?

    // Handlers for logging and duplicate checking against local logbook
    var logQSOHandler: ((_ call: String, _ grid: String, _ sentRST: String, _ rcvdRST: String, _ band: String, _ freqMHz: Double) -> Void)?
    var isCountryWorkedOnBand: ((_ country: String, _ band: String) -> Bool)?
    var isCallWorkedToday: ((_ call: String, _ band: String) -> Bool)?
    var isCallWorked: ((_ call: String) -> Bool)?
    var isGridWorked: ((_ grid: String) -> Bool)?

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

    // MARK: - Frequency & Message Controls

    func syncTxToRx() {
        txAudioFrequencyHz = rxAudioFrequencyHz
    }

    func syncRxToTx() {
        rxAudioFrequencyHz = txAudioFrequencyHz
    }

    func generateStandardMessage(index: Int) -> String {
        guard !myCall.isEmpty else { return "" }
        let target = dxCall.isEmpty ? "CQ" : dxCall
        let grid = myGrid.isEmpty ? "----" : myGrid
        let rep = dxReport.isEmpty ? "-10" : dxReport

        switch index {
        case 1:
            // Tx 1: DX MY GRID
            return "\(target) \(myCall) \(grid)"
        case 2:
            // Tx 2: DX MY REPORT
            return "\(target) \(myCall) \(rep)"
        case 3:
            // Tx 3: DX MY R-REPORT
            let sign = rep.hasPrefix("-") || rep.hasPrefix("+") ? "" : "-"
            return "\(target) \(myCall) R\(sign)\(rep.replacingOccurrences(of: "R", with: ""))"
        case 4:
            // Tx 4: DX MY RR73
            return "\(target) \(myCall) RR73"
        case 5:
            // Tx 5: DX MY 73
            return "\(target) \(myCall) 73"
        case 6:
            // Tx 6: CQ MY GRID
            return "CQ \(myCall) \(grid)"
        default:
            return "CQ \(myCall) \(grid)"
        }
    }

    func setTxMessageIndex(_ index: Int) {
        txText = generateStandardMessage(index: index)
    }

    func clearDecodes() {
        decodedRows.removeAll(keepingCapacity: true)
        waterfallRows.removeAll(keepingCapacity: true)
        activeSignalPeaks.removeAll(keepingCapacity: true)
        selectedDecodeID = nil
    }

    func clearBandActivity() {
        decodedRows.removeAll(keepingCapacity: true)
        activeSignalPeaks.removeAll(keepingCapacity: true)
        selectedDecodeID = nil
    }

    func clearRxStream() {
        qsoStreamItems.removeAll(keepingCapacity: true)
    }

    func dismissOpportunityAlert() {
        latestOpportunityAlert = nil
    }

    func answerOpportunity(_ alert: FT8OpportunityAlert) {
        latestOpportunityAlert = nil
        rxAudioFrequencyHz = alert.frequencyHz
        txAudioFrequencyHz = alert.frequencyHz
        dxCall = alert.callsign
        dxGrid = alert.grid
        let heard = normalizedReport(alert.snrDb)
        dxReport = String(format: "%+03d", heard)
        sequencer = QSOSequencer(
            answer: alert.callsign,
            dxGrid: alert.grid,
            heardSnr: heard,
            myCall: myCall,
            myGrid: myGrid
        )
        txText = sequencer?.message() ?? ""
        sequencePhase = "Answer \(alert.callsign)"
        transmitArmed = true
        status = "Locked onto \(alert.callsign) (\(alert.entityName)) at \(Int(alert.frequencyHz)) Hz; TX armed"
        scheduleTransmission()
    }

    func appendAllTextLog(line: String) {
        Task.detached(priority: .utility) {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
            let dir = appSupport.appendingPathComponent("YAAM/FT8", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fileURL = dir.appendingPathComponent("ALL.TXT")
            let entry = "\(line)\n"
            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
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
        dxCall = ""
        sequencer = QSOSequencer(callCQ: myCall, myGrid: myGrid)
        txText = sequencer?.message() ?? ""
        sequencePhase = "CQ"
        status = "CQ prepared; review the message and arm TX when ready"
    }

    func startContinuousCQ() {
        guard validateIdentity() else { return }
        isCallingCQContinually = true
        beginCQ()
        autoSequenceEnabled = true
        qsoStreamItems.append(.status(id: UUID(), time: Date(), text: "~ Started Continuous CQ cycle on \(txParity == .even ? "1st (:00/:30)" : "2nd (:15/:45)") slot", isMilestone: true))
        if transmitArmed && transmitTask == nil {
            scheduleTransmission()
        }
    }

    func stopContinuousCQ() {
        isCallingCQContinually = false
        if sequencer?.phase == .cq {
            cancelTransmission(reason: "CQ stopped by operator")
        }
    }

    func answerCallsign(_ row: FT8DecodedRow) {
        guard validateIdentity() else { return }
        guard let caller = row.callerCall, !caller.isEmpty else { return }

        isCallingCQContinually = false
        dxCall = caller
        dxGrid = row.callerGrid ?? ""
        dxReport = String(format: "%+03d", normalizedReport(row.estimatedSNR))

        // Set RX audio frequency to caller
        rxAudioFrequencyHz = row.audioFrequencyHz
        if !lockTxRxFreq {
            txAudioFrequencyHz = row.audioFrequencyHz
        }

        // Add to active QSO stream
        qsoStreamItems.append(.status(id: UUID(), time: Date(), text: "~ Engaging \(caller) (\(row.countryName))", isMilestone: true))
        qsoStreamItems.append(.rx(row))

        selectForReply(row)
        autoSequenceEnabled = true

        if transmitArmed && transmitTask == nil {
            scheduleTransmission()
        }
    }

    func selectForReply(_ row: FT8DecodedRow) {
        guard validateIdentity(), let parsed = row.parsed, let caller = row.callerCall, !caller.isEmpty else {
            fail("The selected decode is not a standard FT8 message with a callsign.")
            return
        }
        selectedDecodeID = row.id
        dxCall = caller
        dxGrid = row.callerGrid ?? ""
        let heard = normalizedReport(row.estimatedSNR)
        dxReport = String(format: "%+03d", heard)

        if parsed.isCQ || row.isCQ {
            sequencer = QSOSequencer(
                answer: caller,
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
        status = "Reply to \(caller) prepared for the opposite FT8 sequence"
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

                // Record in active QSO stream
                let txEntry = FT8TxLogEntry(audioFrequencyHz: audioFrequency, text: message, targetCall: dxCall.isEmpty ? nil : dxCall)
                qsoStreamItems.append(.tx(txEntry))
                if qsoStreamItems.count > 150 { qsoStreamItems.removeFirst(qsoStreamItems.count - 150) }
                let dialMHzStr = String(format: "%.6f", Double(dialFrequencyHz) / 1_000_000.0)
                appendAllTextLog(line: "\(Self.utcTime(Date())) \(dialMHzStr) Tx FT8 \(Int(audioFrequency)) \(message)")

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
                    ? "Passed: CI-V, safe UDP, FT8 encode/decode, audio, and UTC slot clock"
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
        let currentBand = FT8BandPreset.common.first(where: { $0.frequencyHz == dialFrequencyHz })?.band ?? "20m"
        let dialMHzStr = String(format: "%.6f", Double(dialFrequencyHz) / 1_000_000.0)
        let slotUtc = Self.utcTime(start)

        var rows = result.messages.map { FT8DecodedRow(message: $0, slotStart: start, myCall: myCall, myGrid: myGrid) }

        // Determine if new DXCC, new Grid, or new Call
        for i in rows.indices {
            let country = rows[i].countryName
            if !country.isEmpty && country != "Unknown" && country != "International" {
                let worked = isCountryWorkedOnBand?(country, currentBand) ?? true
                rows[i].isNewDXCC = !worked
            }
            if let grid = rows[i].callerGrid, grid.count >= 4 {
                let gridWorked = isGridWorked?(grid) ?? true
                rows[i].isNewGrid = !gridWorked
            }
            if let call = rows[i].callerCall, !call.isEmpty {
                let callWorked = isCallWorked?(call) ?? true
                rows[i].isNewCall = !callWorked
            }

            // Continuous ALL.TXT default logging
            let snrStr = String(format: "%+03d", Int(rows[i].estimatedSNR.rounded()))
            let dtStr = String(format: "%+.1f", rows[i].timeOffset)
            let freqStr = String(format: "%04d", Int(rows[i].audioFrequencyHz.rounded()))
            appendAllTextLog(line: "\(slotUtc) \(dialMHzStr) Rx FT8 \(snrStr) \(dtStr) \(freqStr) \(rows[i].text)")

            // Check for high-value opportunity alert (New DXCC or New Grid calling CQ)
            if rows[i].isCQ && (rows[i].isNewDXCC || rows[i].isNewGrid) && rows[i].callerCall != myCall {
                if let call = rows[i].callerCall {
                    latestOpportunityAlert = FT8OpportunityAlert(
                        callsign: call,
                        entityName: rows[i].countryName,
                        flag: rows[i].countryFlag,
                        continent: rows[i].continent,
                        grid: rows[i].callerGrid ?? "",
                        frequencyHz: rows[i].audioFrequencyHz,
                        snrDb: rows[i].estimatedSNR,
                        isNewDXCC: rows[i].isNewDXCC,
                        isNewGrid: rows[i].isNewGrid
                    )
                }
            }
        }

        // Clock Drift Analysis: Calculate median DT across decoded signals
        if !rows.isEmpty {
            let dtValues = rows.map { $0.timeOffset }.sorted()
            let medianDT = dtValues[dtValues.count / 2]
            if abs(medianDT) > 2.0 {
                clockSkewAlert = "Clock Drift Warning: Median DT is \(String(format: "%+.2f", medianDT))s! Local system clock is misaligned. Run 'sudo sntp -sS time.apple.com' to sync."
            } else if abs(medianDT) < 0.8 {
                clockSkewAlert = nil
            }
        }

        if !rows.isEmpty {
            decodedRows.insert(contentsOf: rows, at: 0)
            if decodedRows.count > 300 { decodedRows.removeLast(decodedRows.count - 300) }

            // Update active signal peaks for spectrum overlay
            let newPeaks = rows.compactMap { r -> FT8SignalPeak? in
                guard let c = r.callerCall, !c.isEmpty else { return nil }
                return FT8SignalPeak(
                    callsign: c,
                    frequencyHz: r.audioFrequencyHz,
                    snrDb: r.estimatedSNR,
                    isCQ: r.isCQ,
                    isDirectedToMe: r.isDirectedToMe,
                    timestamp: r.slotStart
                )
            }
            let cutoff = Date().addingTimeInterval(-35)
            activeSignalPeaks = (activeSignalPeaks.filter { $0.timestamp > cutoff } + newPeaks)
        }

        // Stream decodes near rxAudioFrequencyHz or directed to me or from dxCall into qsoStreamItems
        for row in rows {
            let isFreqMatch = abs(row.audioFrequencyHz - rxAudioFrequencyHz) <= 60
            let isPartyMatch = row.isDirectedToMe || (!dxCall.isEmpty && row.callerCall?.uppercased() == dxCall.uppercased())
            if isFreqMatch || isPartyMatch {
                qsoStreamItems.append(.rx(row))
                if qsoStreamItems.count > 150 { qsoStreamItems.removeFirst(qsoStreamItems.count - 150) }
            }
        }

        consumeSequence(rows)

        // Evaluate Auto-Hunter if enabled
        evaluateAutoHunter(with: rows)

        status = rows.isEmpty
            ? "Decoded slot \(slotUtc); no FT8 messages found"
            : "Decoded \(rows.count) FT8 message\(rows.count == 1 ? "" : "s") at \(slotUtc)"
    }

    private func consume(_ frame: SpectrumFrame) {
        waterfallFrameCounter += 1
        guard waterfallFrameCounter.isMultiple(of: 2) else { return }
        let normalized = normalizeSpectrum(frame.magnitudesDB)
        guard !normalized.isEmpty else { return }
        waterfallRows.append(normalized)
        if waterfallRows.count > 80 { waterfallRows.removeFirst(waterfallRows.count - 80) }
        latestSpectrumMagnitudes = normalized
    }

    private func greedyScore(_ row: FT8DecodedRow) -> Int {
        var score = 0
        if row.isNewDXCC { score += 100 }
        if row.isNewGrid { score += 50 }
        if row.isNewCall { score += 30 }
        score += Int(row.estimatedSNR) + 30
        if let km = row.distanceKm { score += min(20, Int(km / 1000)) }
        return score
    }

    private func evaluateAutoHunter(with rows: [FT8DecodedRow]) {
        guard autoHunterEnabled, !rows.isEmpty else { return }
        // Don't interrupt an ongoing exchange
        if let seq = sequencer, !seq.isComplete && seq.phase != .cq {
            return
        }

        let minSNR = Float(autoHunterMinSNR)
        let currentBand = FT8BandPreset.common.first(where: { $0.frequencyHz == dialFrequencyHz })?.band ?? "20m"

        let cqs = rows.filter { row in
            guard row.isCQ, let caller = row.callerCall, !caller.isEmpty else { return false }
            if caller == myCall { return false }
            if row.estimatedSNR < minSNR { return false }
            if autoHunterSkipWorked && (isCallWorkedToday?(caller, currentBand) ?? false) {
                return false
            }
            if autoHunterContinent != "ALL" && row.continent != autoHunterContinent {
                return false
            }
            return true
        }

        guard !cqs.isEmpty else {
            autoHunterStatus = "Auto-Hunter: Monitoring... no qualifying CQs found in last slot (Min SNR: \(autoHunterMinSNR) dB)"
            return
        }

        let bestTarget: FT8DecodedRow?
        switch autoHunterCriteria {
        case .newDXCC:
            bestTarget = cqs.max(by: { greedyScore($0) < greedyScore($1) })
        case .maxDistance:
            bestTarget = cqs.max(by: { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) })
        case .maxSNR:
            bestTarget = cqs.max(by: { $0.estimatedSNR < $1.estimatedSNR })
        case .newGrid:
            bestTarget = cqs.first(where: { $0.isNewGrid }) ?? cqs.first
        case .firstInSlot:
            bestTarget = cqs.first
        }

        guard let target = bestTarget, let targetCall = target.callerCall else { return }
        autoHunterStatus = "🎯 Auto-Hunter: Locked onto \(targetCall) (\(target.countryName), \(Int(target.distanceKm ?? 0)) km, \(Int(target.estimatedSNR)) dB) · Answering!"
        answerCallsign(target)
    }

    private func consumeSequence(_ rows: [FT8DecodedRow]) {
        // Continuous CQ handling:
        if isCallingCQContinually {
            // Greedy pileup selection if multiple stations answered our CQ!
            let callers = rows.filter { $0.isDirectedToMe }
            if !callers.isEmpty {
                isCallingCQContinually = false
                let bestCaller = callers.max(by: { greedyScore($0) < greedyScore($1) }) ?? callers[0]
                qsoStreamItems.append(.status(id: UUID(), time: Date(), text: "~ Answered by \(bestCaller.callerCall ?? "") (Score \(greedyScore(bestCaller)))! Engaging...", isMilestone: true))
                answerCallsign(bestCaller)
                return
            } else if autoSequenceEnabled && transmitArmed && transmitTask == nil {
                // Repeat CQ on the next matching parity slot
                beginCQ()
                scheduleTransmission()
                return
            }
        }

        guard var sequencer else { return }
        for row in rows {
            guard let parsed = row.parsed else { continue }
            if sequencer.receive(parsed, snr: normalizedReport(row.estimatedSNR)) {
                self.sequencer = sequencer
                sequencePhase = sequencer.phase.rawValue
                txText = sequencer.message() ?? ""

                if sequencer.isComplete {
                    autoSequenceEnabled = false
                    let completedDX = sequencer.dxCall
                    let currentBand = FT8BandPreset.common.first(where: { $0.frequencyHz == dialFrequencyHz })?.band ?? "20m"
                    let dialMHz = Double(dialFrequencyHz) / 1_000_000.0

                    qsoStreamItems.append(.status(id: UUID(), time: Date(), text: "★ QSO with \(completedDX) successfully finished and logged!", isMilestone: true))
                    status = "FT8 exchange with \(completedDX) is complete; logged to YAAM Log Table"

                    // Auto-log to Log Table!
                    logQSOHandler?(
                        completedDX,
                        dxGrid,
                        dxReport,
                        String(format: "%+03d", normalizedReport(row.estimatedSNR)),
                        currentBand,
                        dialMHz
                    )
                    appendAllTextLog(line: "\(Self.utcTime(Date())) \(dialMHz) QSO Logged: \(completedDX) \(dxGrid) FT8 \(currentBand)")

                    // Resume CQ if desired
                    if resumeCQAfterQSO {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            if self.resumeCQAfterQSO && self.transmitArmed {
                                self.startContinuousCQ()
                            }
                        }
                    }
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
