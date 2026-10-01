import AppKit
import Combine
import CoreGraphics
import Foundation
import FT8808Engine
import FT8Codec

struct WebSDRReceiver: Identifiable, Hashable {
    let id: String
    let name: String
    let location: String
    let url: URL
    let bands: Set<String>

    var supportsAutomaticRecording: Bool {
        ["esslingen", "twente", "utah", "kfs", "na5b", "maasbree", "maasbree-high",
         "so8oo", "dk0te", "k3fef", "paraibuna", "crapoca", "bordeaux"].contains(id)
    }

    var flag: String {
        switch location {
        case "Germany": "🇩🇪"
        case "Netherlands": "🇳🇱"
        case "USA": "🇺🇸"
        case "Brazil": "🇧🇷"
        case "Australia": "🇦🇺"
        case "New Zealand": "🇳🇿"
        case "Poland": "🇵🇱"
        case "Austria": "🇦🇹"
        case "United Kingdom": "🇬🇧"
        case "France": "🇫🇷"
        default: "🌐"
        }
    }

    var continent: String {
        switch location {
        case "USA": "NA"
        case "Brazil": "SA"
        case "Australia", "New Zealand": "OC"
        case "South Africa": "AF"
        case "India", "Israel": "AS"
        default: "EU"
        }
    }

    static let presets: [Self] = [
        .init(id: "esslingen", name: "DF0HTE", location: "Germany",
              url: URL(string: "https://websdr.afunk.hs-esslingen.de/")!,
              bands: ["80m", "40m", "30m", "20m", "17m", "10m"]),
        .init(id: "maasbree", name: "Maasbree Low", location: "Netherlands",
              url: URL(string: "http://sdr.websdrmaasbree.nl:8901/")!,
              bands: ["80m", "40m", "30m", "20m", "17m", "15m"]),
        .init(id: "maasbree-high", name: "Maasbree High", location: "Netherlands",
              url: URL(string: "http://sdr.websdrmaasbree.nl:8902/")!,
              bands: ["17m", "15m", "10m"]),
        .init(id: "twente", name: "Twente", location: "Netherlands",
              url: URL(string: "http://websdr.ewi.utwente.nl:8901/")!, bands: Set(WebSDRFT8Monitor.bands.map(\.name))),
        .init(id: "utah", name: "Northern Utah", location: "USA",
              url: URL(string: "https://www.sdrutah.org/")!, bands: Set(WebSDRFT8Monitor.bands.map(\.name))),
        .init(id: "kfs", name: "KFS", location: "USA",
              url: URL(string: "http://websdr1.kfsdr.com:8901/")!,
              bands: ["80m", "40m", "30m", "20m", "17m", "15m", "10m"]),
        .init(id: "na5b", name: "NA5B", location: "USA",
              url: URL(string: "http://na5b.com:8901/")!,
              bands: ["80m", "40m", "30m", "20m", "15m", "10m"]),
        .init(id: "pardinho", name: "Pardinho", location: "Brazil",
              url: URL(string: "https://appr.org.br/")!, bands: ["80m", "40m", "20m", "15m", "10m"]),
        .init(id: "areg", name: "AREG KiwiSDR", location: "Australia",
              url: URL(string: "https://www.areg.org.au/remote-hf-rx")!, bands: Set(WebSDRFT8Monitor.bands.map(\.name))),
        .init(id: "zl2ks", name: "ZL2KS KiwiSDR", location: "New Zealand",
              url: URL(string: "https://zl2ks.org.nz/wp/online-sdr-receivers/")!, bands: Set(WebSDRFT8Monitor.bands.map(\.name))),
        .init(id: "so8oo", name: "SO8OO", location: "Poland",
              url: URL(string: "https://sdr.so8oo.net/")!, bands: ["80m", "40m", "20m", "10m"]),
        .init(id: "dk0te", name: "DK0TE · Lake Constance", location: "Germany",
              url: URL(string: "http://dk0te.dhbw-ravensburg.de:8901/")!,
              bands: ["80m", "40m", "30m", "20m", "15m", "10m"]),
        .init(id: "k3fef", name: "K3FEF · Milford", location: "USA",
              url: URL(string: "http://websdr.k3fef.com:8901/")!,
              bands: Set(WebSDRFT8Monitor.bands.map(\.name))),
        .init(id: "paraibuna", name: "Paraibuna", location: "Brazil",
              url: URL(string: "http://paraibuna.websdr.com.br:8901/")!, bands: ["10m"]),
        .init(id: "crapoca", name: "Poços de Caldas", location: "Brazil",
              url: URL(string: "http://crapoca.websdr.com.br:8901/")!, bands: ["80m", "40m", "10m"]),
        .init(id: "tugraz", name: "TU Graz · OE6XUG", location: "Austria",
              url: URL(string: "https://websdr.iks.tugraz.at/")!,
              bands: Set(WebSDRFT8Monitor.bands.map(\.name))),
        .init(id: "pi4vnw", name: "PI4VNW · VERON", location: "Netherlands",
              url: URL(string: "https://pi4vnw.pa9x.com/")!,
              bands: Set(WebSDRFT8Monitor.bands.map(\.name))),
        .init(id: "ambientscape", name: "Ambientscape", location: "United Kingdom",
              url: URL(string: "https://www.ambientscape.com/websdr")!,
              bands: ["80m", "40m", "20m", "10m"]),
        .init(id: "bordeaux", name: "Bordeaux WebSDR", location: "France",
              url: URL(string: "http://ham.websdrbordeaux.fr:8000/")!,
              bands: ["80m", "40m", "20m", "15m", "10m"]),
        .init(id: "kc4mcq", name: "KC4MCQ", location: "USA",
              url: URL(string: "https://kc4mcq.us/live-sdr/")!,
              bands: Set(WebSDRFT8Monitor.bands.map(\.name)))
    ]
}

struct WebSDRAutomaticEndpoint: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let flag: String
    let continent: String
    let baseURL: URL
    let bands: Set<String>

    func tunedURL(for band: WebSDRFT8Band) -> URL? {
        guard bands.contains(band.name) else { return nil }
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        parts?.query = "tune=\(band.dialHz / 1_000)usb"
        return parts?.url
    }

    static let all: [Self] = {
        let normal = WebSDRReceiver.presets.filter {
            $0.supportsAutomaticRecording && $0.id != "utah"
        }.map { receiver in
            Self(id: receiver.id, name: receiver.name, flag: receiver.flag, continent: receiver.continent,
                 baseURL: receiver.url, bands: receiver.bands)
        }
        let utah = UtahWebSDR.all.map { receiver in
            Self(id: "utah-\(receiver.number)", name: "Utah #\(receiver.number) · \(receiver.antenna)",
                 flag: "🇺🇸", continent: "NA", baseURL: receiver.url, bands: receiver.bands)
        }
        return normal + utah
    }()
}

struct UtahWebSDR: Identifiable, Hashable {
    let number: Int
    let antenna: String
    let bands: Set<String>
    var id: Int { number }
    var label: String { "#\(number) · \(antenna)" }
    var url: URL { URL(string: "http://websdr\(number).sdrutah.org:890\(number)/index1a.html")! }

    static let all: [Self] = [
        .init(number: 1, antenna: "Omni · Yellow", bands: ["80m", "40m"]),
        .init(number: 2, antenna: "Omni · Green", bands: ["30m", "20m", "17m", "15m", "10m"]),
        .init(number: 3, antenna: "Omni backup · Blue", bands: ["80m", "40m", "30m"]),
        .init(number: 4, antenna: "East beam · Magenta", bands: ["40m", "30m", "20m", "17m", "15m", "10m"]),
        .init(number: 5, antenna: "Northwest beam · Teal", bands: ["30m", "20m", "17m", "15m", "10m"])
    ]
}

struct WebSDRFT8Band: Identifiable, Hashable {
    let name: String
    let dialHz: Int
    var id: String { name }
    var label: String { "\(name) · \(String(format: "%.3f", Double(dialHz) / 1_000_000)) MHz" }
}

struct WebSDRDecodedMessage: Identifiable {
    let id: String
    let slotStart: Date
    let sender: String?
    let text: String
    let audioFrequencyHz: Float
    let receiverID: String
    let receiverName: String
    let receiverFlag: String
    let transmittingCallsign: String?
    let transmittingFlag: String
    let signalLevelDbFS: Double?
    let mentionsTarget: Bool
    let addressedToTarget: Bool

    var isEvenCycle: Bool { WebSDRSlotTime.isEven(slotStart) }

    var isAcknowledgement: Bool {
        let suffix = text.split(separator: " ").dropFirst(2).joined(separator: " ")
        return addressedToTarget && ["RRR", "RR73", "73"].contains(suffix)
    }
}

struct WebSDRAggregatedMessage: Identifiable {
    let slotStart: Date
    let detections: [WebSDRDecodedMessage]
    let totalSelectedReceivers: Int

    var id: String { "\(Int(slotStart.timeIntervalSince1970))|\(text)" }
    var text: String { detections.first?.text ?? "" }
    var receiverCount: Int { Set(detections.map(\.receiverID)).count }
    var hasMajority: Bool { totalSelectedReceivers >= 2 && receiverCount > totalSelectedReceivers / 2 }
    var mentionsTarget: Bool { detections.contains(where: \.mentionsTarget) }
    var addressedToTarget: Bool { detections.contains(where: \.addressedToTarget) }
    var isAcknowledgement: Bool { detections.contains(where: \.isAcknowledgement) }
    var transmittingFlag: String { detections.first?.transmittingFlag ?? "🌐" }
    var transmittingCallsign: String? { detections.first?.transmittingCallsign }
    var signalLevelDbFS: Double? { detections.compactMap(\.signalLevelDbFS).max() }
    var receivers: [WebSDRDecodedMessage] {
        var seen = Set<String>()
        return detections.filter { seen.insert($0.receiverID).inserted }
    }
}

/// Display-only scale. The decoder's calibrated audio dBFS remains untouched.
enum WebSDRRelativeLevel {
    static func value(_ raw: Double?, among messages: [WebSDRAggregatedMessage]) -> Int? {
        guard let raw else { return nil }
        let levels = messages.compactMap(\.signalLevelDbFS)
        guard let low = levels.min(), let high = levels.max(), high > low else { return -25 }
        return Int(min(0, max(-25, (-25 + 25 * (raw - low) / (high - low)).rounded())))
    }
}

struct WebSDRLogbookStatus {
    let entity: DXCCEntityInfo
    let workedCall: Bool
    let workedEntity: Bool
    let workedEntityBand: Bool
    let loggedGrid: String?
    let loggedState: String?

    var isNewDXCC: Bool { entity.countryCode != "--" && !workedEntity }
    var isNewBand: Bool { entity.countryCode != "--" && workedEntity && !workedEntityBand }
}

struct WebSDRLogbookIndex {
    private var calls = Set<String>()
    private var entities = Set<String>()
    private var entityBands = Set<String>()
    private var grids: [String: String] = [:]
    private var states: [String: String] = [:]

    init(records: [QSORecordModel] = []) {
        for record in records {
            let fields = record.fields
            let call = (fields["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !call.isEmpty else { continue }
            let entity = DXCCDatabase.resolve(callsign: call, country: fields["COUNTRY"])
            let key = entity.entityName.uppercased()
            calls.insert(call)
            if entity.countryCode != "--" { entities.insert(key) }
            let band = (fields["BAND"].flatMap { $0.isEmpty ? nil : $0 }
                        ?? fields["FREQ"].flatMap(AmateurBandPlan.band(for:))
                        ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !band.isEmpty { entityBands.insert("\(key)|\(band)") }
            if let grid = fields["GRIDSQUARE"], !grid.isEmpty { grids[call] = grid }
            if let state = fields["STATE"], !state.isEmpty { states[call] = state }
        }
    }

    func status(for call: String, band: String) -> WebSDRLogbookStatus {
        let upper = call.uppercased()
        let entity = DXCCDatabase.resolve(callsign: upper)
        let key = entity.entityName.uppercased()
        return .init(entity: entity, workedCall: calls.contains(upper),
                     workedEntity: entities.contains(key),
                     workedEntityBand: entityBands.contains("\(key)|\(band.lowercased())"),
                     loggedGrid: grids[upper], loggedState: states[upper])
    }
}

enum WebSDRMessageParser {
    static func grid(in text: String) -> String? {
        guard let candidate = text.uppercased().split(whereSeparator: \.isWhitespace).last.map(String.init) else { return nil }
        guard candidate != "RR73", candidate != "RRR" else { return nil }
        let characters = Array(candidate)
        guard characters.count == 4 || characters.count == 6 else { return nil }
        guard ("A"..."R").contains(characters[0]), ("A"..."R").contains(characters[1]),
              characters[2].isNumber, characters[3].isNumber else { return nil }
        if characters.count == 6 {
            guard ("A"..."X").contains(characters[4]), ("A"..."X").contains(characters[5]) else { return nil }
        }
        return candidate
    }
    static func transmittingCallsign(in text: String) -> String? {
        let words = text.uppercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return nil }
        let candidate = words[0] == "CQ" ? (words.count >= 3 && !isCallsign(words[1]) ? words[2] : words[1])
            : words[0] == "QRZ" ? words[1] : words[1]
        return isCallsign(candidate) ? candidate : nil
    }

    private static func isCallsign(_ value: String) -> Bool {
        guard !value.contains("<"), !value.contains(">"), value.count >= 3,
              value.rangeOfCharacter(from: .decimalDigits) != nil,
              value.rangeOfCharacter(from: .letters) != nil else { return false }
        return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "/") }
    }
    static func mentions(_ callsign: String, in text: String) -> Bool {
        let target = callsign.uppercased()
        return text.uppercased().split(whereSeparator: \.isWhitespace).contains { token in
            token.trimmingCharacters(in: CharacterSet(charactersIn: "<>.,:;[]()")) == target
        }
    }

    /// Only a directed message with a resolved second callsign identifies an answering station.
    static func directedSender(in text: String, to target: String) -> String? {
        let words = text.uppercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 3, words[0] == target.uppercased() else { return nil }
        let sender = words[1]
        guard sender != target.uppercased(), sender.rangeOfCharacter(from: .decimalDigits) != nil,
              sender.rangeOfCharacter(from: .letters) != nil,
              !sender.contains("<"), !sender.contains(">") else { return nil }
        return sender
    }
}

@MainActor
final class WebSDRFT8Monitor: ObservableObject {
    static let shared = WebSDRFT8Monitor()
    static let systemAudioUID = "yaam.system-audio"
    static let automaticRecordingUID = "yaam.websdr-recording"

    static let bands: [WebSDRFT8Band] = [
        .init(name: "80m", dialHz: 3_573_000),
        .init(name: "40m", dialHz: 7_074_000),
        .init(name: "30m", dialHz: 10_136_000),
        .init(name: "20m", dialHz: 14_074_000),
        .init(name: "17m", dialHz: 18_100_000),
        .init(name: "15m", dialHz: 21_074_000),
        .init(name: "10m", dialHz: 28_074_000)
    ]

    @Published var selectedReceiverID = "esslingen"
    @Published var selectedBand = "20m"
    @Published var selectedUtahReceiver = 2
    @Published var selectedParallelEndpointIDs: Set<String> = []
    @Published private(set) var customEndpoints: [WebSDRAutomaticEndpoint] = {
        guard let data = UserDefaults.standard.data(forKey: "webSDRCustomEndpoints") else { return [] }
        return (try? JSONDecoder().decode([WebSDRAutomaticEndpoint].self, from: data)) ?? []
    }()
    @Published var selectedInputUID = automaticRecordingUID
    @Published var listenToReceiver = false {
        didSet {
            for (id, browser) in browsers {
                browser.setListening(listenToReceiver && id == primaryAutomaticEndpoint?.id)
            }
        }
    }
    @Published private(set) var audioInputs: [AudioInputDevice] = []
    @Published private(set) var messages: [WebSDRDecodedMessage] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var status = "Ready to decode system playback audio."
    @Published private(set) var phaseSeconds: Double?
    @Published private(set) var clockOffsetSeconds: Double?
    @Published private(set) var receiverStatuses: [String: String] = [:]

    private var loopbackCapture: LiveRadioSource?
    private var systemCapture: SystemAudioFT8Source?
    private struct RecordedStream {
        var previous: AudioSlot?
        var nextIndex = 0
        var shortSegments = 0
    }
    private var browsers: [String: WebSDRBrowserSession] = [:]
    private var recordedStreams: [String: RecordedStream] = [:]
    private var recordingDecodeTasks: [String: Task<Void, Never>] = [:]
    private var liveTimelines: [String: WebSDRAudioTimeline] = [:]
    private var livePreviousSlots: [String: AudioSlot] = [:]
    private var liveDecodeTasks: [String: Task<Void, Never>] = [:]
    private var liveAudioAt: [String: Date] = [:]
    private var activeTapIDs: [String: Int] = [:]
    private var decodeTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var activeTarget = ""
    private var activeReceiverName = ""
    private var sessionID = UUID()
    private var seenIDs = Set<String>()
    private var consensusReceiverCount = 1
    private var systemAudioGrantNeedsRestart = false

    var receiver: WebSDRReceiver {
        WebSDRReceiver.presets.first { $0.id == selectedReceiverID } ?? WebSDRReceiver.presets[0]
    }

    var band: WebSDRFT8Band {
        Self.bands.first { $0.name == selectedBand } ?? Self.bands[3]
    }

    var directedMessages: [WebSDRDecodedMessage] { messages.filter(\.addressedToTarget) }
    var targetMatches: [WebSDRDecodedMessage] { messages.filter(\.mentionsTarget) }
    var consensusMessages: [WebSDRAggregatedMessage] {
        let groups = WebSDRConsensusBuilder.build(messages.map {
            .init(id: $0.id, receiverID: $0.receiverID, slotStart: $0.slotStart, text: $0.text)
        }, primaryReceiverID: primaryAutomaticEndpoint?.id)
        let byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        return groups.compactMap { group in
            let detections = group.observationIDs.compactMap { byID[$0] }
            guard !detections.isEmpty else { return nil }
            return .init(slotStart: group.slotStart, detections: detections,
                         totalSelectedReceivers: consensusReceiverCount)
        }
    }
    var consensusTargetMatches: [WebSDRAggregatedMessage] {
        consensusMessages.filter(\.mentionsTarget)
    }
    var availableUtahReceivers: [UtahWebSDR] {
        UtahWebSDR.all.filter { $0.bands.contains(selectedBand) }
    }
    var activeUtahReceiver: UtahWebSDR? {
        availableUtahReceivers.first { $0.number == selectedUtahReceiver } ?? availableUtahReceivers.first
    }
    var availableAutomaticEndpoints: [WebSDRAutomaticEndpoint] {
        (WebSDRAutomaticEndpoint.all + customEndpoints).filter { $0.bands.contains(selectedBand) }
    }

    func addCustomEndpoint(name: String, urlText: String, flag: String, continent: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, let url = URL(string: cleanURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, ["AS", "EU", "AF", "NA", "SA", "OC"].contains(continent) else { return false }
        let endpoint = WebSDRAutomaticEndpoint(
            id: "custom-\(UUID().uuidString)", name: cleanName,
            flag: flag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "🌐" : flag,
            continent: continent, baseURL: url, bands: [selectedBand])
        customEndpoints.append(endpoint)
        if let data = try? JSONEncoder().encode(customEndpoints) {
            UserDefaults.standard.set(data, forKey: "webSDRCustomEndpoints")
        }
        selectedParallelEndpointIDs.insert(endpoint.id)
        reconcileAutomaticEndpoints()
        return true
    }

    func removeCustomEndpoint(_ id: String) {
        selectedParallelEndpointIDs.remove(id)
        customEndpoints.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(customEndpoints) {
            UserDefaults.standard.set(data, forKey: "webSDRCustomEndpoints")
        }
        reconcileAutomaticEndpoints()
    }
    var primaryAutomaticEndpoint: WebSDRAutomaticEndpoint? {
        let id = receiver.id == "utah" ? "utah-\(activeUtahReceiver?.number ?? 2)" : receiver.id
        return availableAutomaticEndpoints.first { $0.id == id }
    }
    var selectedAutomaticEndpoints: [WebSDRAutomaticEndpoint] {
        guard let primary = primaryAutomaticEndpoint else { return [] }
        return [primary] + availableAutomaticEndpoints.filter {
            $0.id != primary.id && selectedParallelEndpointIDs.contains($0.id)
        }
    }
    var activeReceiverURL: URL? {
        let base = receiver.id == "utah" ? activeUtahReceiver?.url : receiver.url
        guard let base else { return nil }
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        if receiver.supportsAutomaticRecording || receiver.id.hasPrefix("maasbree") {
            parts?.query = "tune=\(band.dialHz / 1_000)usb"
        }
        return parts?.url
    }
    var estimatedDelayModuloCycle: Double? {
        guard let phaseSeconds else { return nil }
        let corrected = phaseSeconds + (clockOffsetSeconds ?? 0)
        return (corrected + 15).truncatingRemainder(dividingBy: 15)
    }

    func refreshInputs() { audioInputs = AudioDevices.inputDevices() }
    func openReceiver() { NSWorkspace.shared.open(activeReceiverURL ?? receiver.url) }

    var systemAudioPermissionGranted: Bool { CGPreflightScreenCaptureAccess() }

    func requestSystemAudioAccess() {
        guard !CGPreflightScreenCaptureAccess() else {
            status = "System Audio access is available. Start receiving when ready."
            return
        }
        let granted = CGRequestScreenCaptureAccess()
        if granted { systemAudioGrantNeedsRestart = true }
        status = granted
            ? "Permission granted. Quit and reopen YAAM once before starting System Audio."
            : "System Audio access is off. Enable YAAM in macOS Privacy & Security, then reopen YAAM."
    }

    func toggleParallelEndpoint(_ id: String) {
        if selectedParallelEndpointIDs.contains(id) {
            selectedParallelEndpointIDs.remove(id)
        } else if availableAutomaticEndpoints.contains(where: { $0.id == id }),
                  id != primaryAutomaticEndpoint?.id {
            selectedParallelEndpointIDs.insert(id)
        } else {
            status = "This receiver is unavailable on the selected band."
        }
        reconcileAutomaticEndpoints()
    }

    func selectAllParallelEndpoints() {
        selectedParallelEndpointIDs = Set(availableAutomaticEndpoints.map(\.id))
        selectedParallelEndpointIDs.remove(primaryAutomaticEndpoint?.id ?? "")
        reconcileAutomaticEndpoints()
    }

    func clearParallelEndpoints() {
        selectedParallelEndpointIDs.removeAll()
        reconcileAutomaticEndpoints()
    }

    /// Changes only the receivers whose selection changed. Existing audio streams and
    /// decoder state remain continuous, including the primary receiver's 15 s timeline.
    func reconcileAutomaticEndpoints() {
        guard isMonitoring, selectedInputUID == Self.automaticRecordingUID else { return }
        let wanted = selectedAutomaticEndpoints
        let wantedIDs = Set(wanted.map(\.id))
        for id in Array(browsers.keys) where !wantedIDs.contains(id) {
            removeAutomaticEndpoint(id)
        }
        consensusReceiverCount = wanted.count
        for endpoint in wanted where browsers[endpoint.id] == nil {
            startAutomaticEndpoint(endpoint, session: sessionID)
        }
        status = "Receiving from \(browsers.count) WebSDR receiver(s) · \(messages.count) decoded"
    }

    private func removeAutomaticEndpoint(_ id: String) {
        browsers.removeValue(forKey: id)?.stop()
        recordingDecodeTasks.removeValue(forKey: id)?.cancel()
        recordedStreams.removeValue(forKey: id)
        for key in Array(liveDecodeTasks.keys) where key.hasPrefix(id + "#") {
            liveDecodeTasks.removeValue(forKey: key)?.cancel()
            liveTimelines.removeValue(forKey: key)
            livePreviousSlots.removeValue(forKey: key)
        }
        liveAudioAt.removeValue(forKey: id)
        activeTapIDs.removeValue(forKey: id)
        receiverStatuses.removeValue(forKey: id)
    }

    private func startAutomaticEndpoint(_ endpoint: WebSDRAutomaticEndpoint, session: UUID) {
        guard let url = endpoint.tunedURL(for: band) else { return }
        let browser = WebSDRBrowserSession()
        browsers[endpoint.id] = browser
        recordedStreams[endpoint.id] = RecordedStream()
        browser.onStatus = { [weak self, weak browser] message in
            guard let self, self.sessionID == session,
                  let browser, self.browsers[endpoint.id] === browser else { return }
            self.receiverStatuses[endpoint.id] = message
            if self.messages.isEmpty { self.status = "\(endpoint.name): \(message)" }
        }
        browser.onRecording = { [weak self, weak browser] recording in
            guard let self, let browser, self.browsers[endpoint.id] === browser else { return }
            self.queueRecording(recording, endpoint: endpoint, session: session)
        }
        browser.onAudio = { [weak self, weak browser] samples, endedAt, tapID in
            guard let self, let browser, self.browsers[endpoint.id] === browser else { return }
            self.consumeLiveAudio(samples, endedAt: endedAt,
                                  tapID: tapID, endpoint: endpoint, session: session)
        }
        browser.start(url: url,
                      listening: listenToReceiver && endpoint.id == primaryAutomaticEndpoint?.id)
    }

    func normalizeSelection() {
        if !receiver.bands.contains(selectedBand) {
            selectedBand = receiver.bands.contains("20m") ? "20m" :
                (Self.bands.first { receiver.bands.contains($0.name) }?.name ?? "20m")
        }
        if receiver.id == "utah", !availableUtahReceivers.contains(where: { $0.number == selectedUtahReceiver }) {
            selectedUtahReceiver = availableUtahReceivers.first?.number ?? 2
        }
        let available = Set(availableAutomaticEndpoints.map(\.id))
        selectedParallelEndpointIDs = selectedParallelEndpointIDs.intersection(available)
        selectedParallelEndpointIDs.remove(primaryAutomaticEndpoint?.id ?? "")
        if !receiver.supportsAutomaticRecording && selectedInputUID == Self.automaticRecordingUID {
            selectedInputUID = Self.systemAudioUID
        }
    }

    func start(targetCallsign: String) {
        let call = targetCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !call.isEmpty else { status = "Enter the callsign to monitor."; return }
        guard receiver.bands.contains(selectedBand) else {
            status = "This receiver does not list \(selectedBand); choose a supported band."
            return
        }
        if selectedInputUID == Self.automaticRecordingUID, !receiver.supportsAutomaticRecording {
            status = "Automatic recording is not available for this receiver. Select System Audio."
            return
        }
        if selectedInputUID != Self.systemAudioUID && selectedInputUID != Self.automaticRecordingUID,
           !audioInputs.contains(where: { $0.uid == selectedInputUID }) {
            status = "Select an available audio input."
            return
        }
        if selectedInputUID == Self.systemAudioUID &&
            (!systemAudioPermissionGranted || systemAudioGrantNeedsRestart) {
            status = systemAudioGrantNeedsRestart
                ? "Quit and reopen YAAM once to activate newly granted System Audio access."
                : "System Audio needs macOS access. Use the explicit permission button, then reopen YAAM; automatic WebSDR audio needs no permission."
            return
        }
        stop()
        messages.removeAll()
        seenIDs.removeAll()
        phaseSeconds = nil
        clockOffsetSeconds = nil
        activeTarget = call
        activeReceiverName = receiver.id == "utah" ? "Utah #\(activeUtahReceiver?.number ?? 2)" : receiver.name
        sessionID = UUID()
        let startedSession = sessionID
        if selectedInputUID == Self.automaticRecordingUID {
            let endpoints = selectedAutomaticEndpoints
            guard !endpoints.isEmpty else {
                status = "Choose an automatic WebSDR receiver."
                return
            }
            consensusReceiverCount = endpoints.count
            isMonitoring = true
            status = "Opening \(endpoints.count) WebSDR receiver\(endpoints.count == 1 ? "" : "s")…"
            for endpoint in endpoints { startAutomaticEndpoint(endpoint, session: startedSession) }
            clockTask = Task { await synchronizeClock(session: startedSession) }
            return
        }
        consensusReceiverCount = 1
        let selectedSource: any AudioSource
        if selectedInputUID == Self.systemAudioUID {
            let capture = SystemAudioFT8Source()
            systemCapture = capture
            selectedSource = capture
        } else {
            let capture = LiveRadioSource(device: selectedInputUID, slotSeconds: 15)
            loopbackCapture = capture
            selectedSource = capture
        }
        isMonitoring = true
        status = "Listening to \(selectedInputUID == Self.systemAudioUID ? "system audio" : "selected input")…"
        clockTask = Task { await synchronizeClock(session: startedSession) }
        decodeTask = Task.detached(priority: .userInitiated) { [weak self] in
            var previous: AudioSlot?
            for await slot in selectedSource.slots() {
                guard !Task.isCancelled else { break }
                let origin = slot.startTime ?? Date()
                if let prior = previous {
                    let detections = WebSDRCycleDecoder.decode(previous: prior.samples,
                                                               next: slot.samples,
                                                               sampleRate: slot.sampleRate)
                    let previousOrigin = prior.startTime ?? origin.addingTimeInterval(-prior.duration)
                    for detection in detections {
                        await self?.consume(detection.message,
                                        observedAt: previousOrigin.addingTimeInterval(detection.cycleOffsetSeconds),
                                            signalLevelDbFS: detection.signalLevelDbFS,
                                            session: startedSession)
                    }
                }
                previous = slot
            }
            if !Task.isCancelled {
                await self?.captureEnded(session: startedSession)
            }
        }
    }

    func stop() {
        sessionID = UUID()
        for browser in browsers.values { browser.stop() }
        browsers.removeAll()
        for task in recordingDecodeTasks.values { task.cancel() }
        recordingDecodeTasks.removeAll()
        recordedStreams.removeAll()
        for task in liveDecodeTasks.values { task.cancel() }
        liveDecodeTasks.removeAll()
        liveTimelines.removeAll()
        livePreviousSlots.removeAll()
        liveAudioAt.removeAll()
        activeTapIDs.removeAll()
        receiverStatuses.removeAll()
        decodeTask?.cancel()
        decodeTask = nil
        clockTask?.cancel()
        clockTask = nil
        loopbackCapture?.stop()
        loopbackCapture = nil
        systemCapture?.stop()
        systemCapture = nil
        if isMonitoring { status = "Monitoring stopped." }
        isMonitoring = false
    }

    private func consumeLiveAudio(_ samples: [Float], endedAt: Date, tapID: Int,
                                  endpoint: WebSDRAutomaticEndpoint, session: UUID) {
        guard session == sessionID else { return }
        if activeTapIDs[endpoint.id] == nil {
            guard samples.contains(where: { abs($0) > 0.000_1 }) else { return }
            activeTapIDs[endpoint.id] = tapID
        }
        guard activeTapIDs[endpoint.id] == tapID else { return }
        let streamKey = "\(endpoint.id)#\(tapID)"
        if samples.contains(where: { abs($0) > 0.000_1 }) {
            liveAudioAt[endpoint.id] = Date()
        }
        var timeline = liveTimelines[streamKey] ?? WebSDRAudioTimeline()
        let result = timeline.append(samples, endedAt: endedAt)
        liveTimelines[streamKey] = timeline
        if let gap = result.interruptionSeconds, gap > 3 {
            livePreviousSlots.removeValue(forKey: streamKey)
            receiverStatuses[endpoint.id] = "Audio interrupted for \(Int(gap.rounded())) s; resynchronizing"
        }
        for slot in result.slots {
            queueLiveSlot(slot, streamKey: streamKey, endpoint: endpoint, session: session)
        }
    }

    private func queueLiveSlot(_ slot: AudioSlot, streamKey: String,
                               endpoint: WebSDRAutomaticEndpoint,
                               session: UUID) {
        let previousSlot = livePreviousSlots[streamKey]
        livePreviousSlots[streamKey] = slot
        let previousTask = liveDecodeTasks[streamKey]
        liveDecodeTasks[streamKey] = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            let across = await Task.detached(priority: .userInitiated) {
                previousSlot.map {
                    WebSDRCycleDecoder.decode(previous: $0.samples, next: slot.samples,
                                              sampleRate: slot.sampleRate)
                } ?? []
            }.value
            guard let self, !Task.isCancelled,
                  session == self.sessionID, self.browsers[endpoint.id] != nil else { return }
            let countBefore = self.messages.count
            let start = slot.startTime ?? Date()
            if let previousSlot {
                let origin = previousSlot.startTime ?? start.addingTimeInterval(-15)
                for detection in across {
                    self.addRecordedMessage(detection.message,
                                            cycleAt: origin.addingTimeInterval(detection.cycleOffsetSeconds),
                                            signalLevelDbFS: detection.signalLevelDbFS,
                                            endpoint: endpoint, session: session)
                }
            }
            self.receiverStatuses[endpoint.id] = self.messages.count > countBefore
                ? "Continuous audio · FT8 decoded"
                : "Continuous audio · no FT8 in latest cycle"
        }
    }

    private func queueRecording(_ recording: WebSDRRecording, endpoint: WebSDRAutomaticEndpoint,
                                session: UUID) {
        if let liveAt = liveAudioAt[endpoint.id], Date().timeIntervalSince(liveAt) < 5 { return }
        let previous = recordingDecodeTasks[endpoint.id]
        recordingDecodeTasks[endpoint.id] = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.consumeRecording(recording, endpoint: endpoint, session: session)
        }
    }

    private func consumeRecording(_ recording: WebSDRRecording, endpoint: WebSDRAutomaticEndpoint,
                                  session: UUID) async {
        guard session == sessionID else { return }
        var stream = recordedStreams[endpoint.id] ?? RecordedStream()
        let index = stream.nextIndex
        stream.nextIndex += 1
        let previous = stream.previous
        let result = await Task.detached(priority: .userInitiated) {
            let samples = WebSDRWAV.samples(at12kHz: recording.wav)
            let direct = (try? FT8Codec.decode(samples: samples, sampleRate: 12_000,
                                               protocol: .ft8, maxMessages: 64)) ?? []
            let across = previous.map {
                WebSDRCycleDecoder.decode(previous: $0.samples, next: samples, sampleRate: 12_000)
            } ?? []
            let levels = direct.map {
                WebSDRSignalLevel.estimate(samples: samples, sampleRate: 12_000,
                    onsetSeconds: Double($0.timeSeconds), frequencyHz: $0.frequencyHz)
            }
            return (samples, direct, across, levels)
        }.value
        guard !Task.isCancelled, session == sessionID, browsers[endpoint.id] != nil else { return }
        let (samples, direct, across, levels) = result
        let mediaDuration = Double(samples.count) / 12_000
        let wallDuration = recording.stoppedAt.timeIntervalSince(recording.startedAt)
        guard abs(mediaDuration - wallDuration) <= 2.0 else {
            stream.previous = nil
            stream.shortSegments += 1
            recordedStreams[endpoint.id] = stream
            receiverStatuses[endpoint.id] = "WebSDR recording lost \(Int(abs(mediaDuration - wallDuration).rounded())) s of audio"
            return
        }
        guard samples.count >= 12_000 * 10 else {
            stream.previous = nil
            stream.shortSegments += 1
            recordedStreams[endpoint.id] = stream
            if stream.shortSegments >= 3 {
                receiverStatuses[endpoint.id] = "Short audio segments; reconnecting may help."
                if messages.isEmpty { status = "\(endpoint.name): short audio segments." }
            }
            return
        }
        let meanPower = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
        guard meanPower > 0.000_000_01 else {
            stream.previous = nil
            stream.shortSegments += 1
            recordedStreams[endpoint.id] = stream
            if stream.shortSegments >= 3 {
                receiverStatuses[endpoint.id] = "Silent audio; check this receiver."
                if messages.isEmpty { status = "\(endpoint.name): silent audio." }
            }
            return
        }
        let began = recording.stoppedAt.addingTimeInterval(-mediaDuration)
        let slot = AudioSlot(index: index, samples: samples, sampleRate: 12_000, startTime: began)
        stream.previous = slot
        stream.shortSegments = 0
        recordedStreams[endpoint.id] = stream
        receiverStatuses[endpoint.id] = "Receiving FT8 audio"
        let directOffsets = direct.map { Double($0.timeSeconds) }.sorted()
        let directCycle = began.addingTimeInterval(directOffsets.isEmpty ? 0 : directOffsets[directOffsets.count / 2])
        for (index, message) in direct.enumerated() {
            addRecordedMessage(message, cycleAt: directCycle,
                               signalLevelDbFS: levels[index],
                               endpoint: endpoint, session: session)
        }
        if let previous {
            let origin = previous.startTime ?? began.addingTimeInterval(-previous.duration)
            for detection in across {
                addRecordedMessage(detection.message,
                                   cycleAt: origin.addingTimeInterval(detection.cycleOffsetSeconds),
                                   signalLevelDbFS: detection.signalLevelDbFS,
                                   endpoint: endpoint, session: session)
            }
        }
        if direct.isEmpty, across.isEmpty, messages.isEmpty {
            status = "Recording \(selectedAutomaticEndpoints.count) receiver(s) · waiting for FT8…"
        }
    }

    private func addRecordedMessage(_ message: FT8Message, cycleAt: Date,
                                    signalLevelDbFS: Double?,
                                    endpoint: WebSDRAutomaticEndpoint, session: UUID) {
        guard session == sessionID, browsers[endpoint.id] != nil else { return }
        let cycle = WebSDRSlotTime.nearestBoundary(to: cycleAt)
        let cycleIndex = Int((cycle.timeIntervalSince1970 / 15).rounded())
        let frequency = Int(message.frequencyHz.rounded())
        let key = "\(endpoint.id)|\(cycleIndex)|\(message.text)|\(frequency)"
        guard seenIDs.insert(key).inserted else { return }
        let sender = WebSDRMessageParser.directedSender(in: message.text, to: activeTarget)
        let transmitter = WebSDRMessageParser.transmittingCallsign(in: message.text)
        messages.append(.init(id: key, slotStart: cycle, sender: sender,
                              text: message.text, audioFrequencyHz: message.frequencyHz,
                              receiverID: endpoint.id,
                              receiverName: endpoint.name, receiverFlag: endpoint.flag,
                              transmittingCallsign: transmitter,
                              transmittingFlag: transmitter.map { DXCCDatabase.resolve(callsign: $0).flagEmoji } ?? "🌐",
                              signalLevelDbFS: signalLevelDbFS,
                              mentionsTarget: WebSDRMessageParser.mentions(activeTarget, in: message.text),
                              addressedToTarget: sender != nil))
        messages.sort {
            if $0.slotStart != $1.slotStart { return $0.slotStart > $1.slotStart }
            if $0.text != $1.text { return $0.text < $1.text }
            return $0.receiverID < $1.receiverID
        }
        if messages.count > 2_000 { messages = Array(messages.prefix(2_000)) }
        if seenIDs.count > 8_000 { seenIDs = Set(messages.map(\.id)) }
        if endpoint.id == primaryAutomaticEndpoint?.id {
            phaseSeconds = (cycleAt.timeIntervalSince1970 - cycle.timeIntervalSince1970 + 15)
                .truncatingRemainder(dividingBy: 15)
        }
        status = "\(messages.count) decoded · \(targetMatches.count) mention \(activeTarget) · \(browsers.count) receivers"
    }

    private func captureEnded(session: UUID) {
        guard session == sessionID else { return }
        let error = systemCapture?.lastError ?? loopbackCapture?.lastError
        status = error?.localizedDescription ?? "Audio capture stopped."
        isMonitoring = false
        systemCapture?.stop()
        loopbackCapture?.stop()
        systemCapture = nil
        loopbackCapture = nil
        decodeTask = nil
        clockTask?.cancel()
        clockTask = nil
    }

    private func consume(_ message: FT8Message, observedAt: Date,
                         signalLevelDbFS: Double?, session: UUID) {
        guard session == sessionID else { return }
        let cycle = WebSDRSlotTime.nearestBoundary(to: observedAt)
        let cycleIndex = Int((cycle.timeIntervalSince1970 / 15).rounded())
        let key = "input|\(cycleIndex)|\(message.text)|\(Int(message.frequencyHz.rounded()))"
        guard seenIDs.insert(key).inserted else { return }
        let sender = WebSDRMessageParser.directedSender(in: message.text, to: activeTarget)
        let transmitter = WebSDRMessageParser.transmittingCallsign(in: message.text)
        messages.append(.init(id: key, slotStart: cycle, sender: sender,
                              text: message.text, audioFrequencyHz: message.frequencyHz,
                              receiverID: "input", receiverName: activeReceiverName,
                              receiverFlag: receiver.flag,
                              transmittingCallsign: transmitter,
                              transmittingFlag: transmitter.map { DXCCDatabase.resolve(callsign: $0).flagEmoji } ?? "🌐",
                              signalLevelDbFS: signalLevelDbFS,
                              mentionsTarget: WebSDRMessageParser.mentions(activeTarget, in: message.text),
                              addressedToTarget: sender != nil))
        messages.sort {
            if $0.slotStart != $1.slotStart { return $0.slotStart > $1.slotStart }
            if $0.text != $1.text { return $0.text < $1.text }
            return $0.receiverID < $1.receiverID
        }
        if messages.count > 500 { messages = Array(messages.prefix(500)) }
        if seenIDs.count > 1_000 { seenIDs = Set(messages.map(\.id)) }
        phaseSeconds = (observedAt.timeIntervalSince1970 - cycle.timeIntervalSince1970 + 15)
            .truncatingRemainder(dividingBy: 15)
        status = "\(messages.count) decoded · \(targetMatches.count) mention \(activeTarget)"
    }

    private func synchronizeClock(session: UUID) async {
        var observations: [(offset: Double, roundTrip: Double)] = []
        for _ in 0..<3 {
            var request = URLRequest(url: URL(string: "https://time.cloudflare.com/")!)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 4
            let sent = Date()
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  let header = http.value(forHTTPHeaderField: "Date") else { continue }
            let received = Date()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            guard let server = formatter.date(from: header) else { continue }
            let midpoint = sent.addingTimeInterval(received.timeIntervalSince(sent) / 2)
            observations.append((server.timeIntervalSince(midpoint), received.timeIntervalSince(sent)))
        }
        guard session == sessionID, let best = observations.min(by: { $0.roundTrip < $1.roundTrip }) else { return }
        clockOffsetSeconds = best.offset
    }
}
