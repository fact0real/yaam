// Stand-ins for the radio drivers and clients that CWKeyerService, DigitalModemEngine and FT8EngineService call,
// for the behaviour tests of the transmit checks (Tests/TransmitGatesBehaviourRegression.swift,
// Tests/TransmitGatesFT8Regression.swift). They do nothing except record, in KeyLog, what the real code would
// have handed to a radio. Only the members the real sources use are declared. Nothing here opens a port, a
// socket or an audio device. They replace the real drivers only in these test programs; nothing in the app
// refers to this file.
import Foundation

enum KeyLog {
    static var events: [String] = []
    static func add(_ s: String) { events.append(s) }
    static func drain() -> [String] { let e = events; events = []; return e }
}

enum StubRaw: String { case a = "A" }
enum StubModel: String { case ic7300MK2 = "IC-7300MK2" }
enum StubConnection: String { case usb = "USB", bluetooth = "Bluetooth" }

final class WinKeyerDriver {
    static let shared = WinKeyerDriver()
    var isConnected = false
    var wkVersion = "stub"
    var selectedPort = ""
    var isTransmitting = false
    var onCharacterEchoed: ((String) -> Void)?
    var onTransmissionComplete: (() -> Void)?
    var onPaddleBreakIn: (() -> Void)?
    func setSpeed(_ wpm: Int) {}
    // As YAAM/WinKeyerDriver.swift: sendMorseText marks the WinKeyer busy; abort() clears it, marks it idle and,
    // unless reportEnd is false, reports the end at once (Tests/WinKeyerAutoCQRegression.swift checks the real
    // driver does the same).
    func sendMorseText(_ text: String) {
        guard isConnected else { return }
        isTransmitting = true
        KeyLog.add("KEYED via WinKeyer: \(text)")
    }
    func abort(reportEnd: Bool = true) {
        guard isConnected else { return }
        KeyLog.add("WinKeyer buffer cleared")
        isTransmitting = false
        if reportEnd { onTransmissionComplete?() }
    }
}

final class SerialKeyerDriver {
    static let shared = SerialKeyerDriver()
    var isConnected = false
    var selectedPort = ""
    var cwPin = StubRaw.a
    var pttPin = StubRaw.a
    func sendMorse(text: String, wpm: Int, onCharacter: @escaping (String) -> Void, onComplete: @escaping () -> Void) {
        KeyLog.add("KEYED via serial pin: \(text)"); onComplete()
    }
    func abort() {}
}

final class FX4CRDriver {
    static let shared = FX4CRDriver()
    var isConnected = false
    var selectedPort = ""
    var connectionType = StubConnection.usb
    var formattedFrequency = ""
    var mode = ""
    func sendMorse(_ text: String, wpm: Int) { KeyLog.add("KEYED via FX-4CR: \(text)") }
    func stopMorse() {}
    func setPTT(_ on: Bool, maximumDuration: TimeInterval = 14) { KeyLog.add("PTT \(on) via FX-4CR") }
    func setFrequencyHz(_ hz: UInt64) {}
    func setMode(_ m: String) {}
}

final class IcomUSBRadioDriver {
    static let shared = IcomUSBRadioDriver()
    var isConnected = false
    var selectedPort = ""
    var model = StubModel.ic7300MK2
    var formattedFrequency = ""
    var mode = ""
    func setKeyerSpeed(_ wpm: Int) {}
    func sendMorse(_ text: String) { KeyLog.add("KEYED via Icom USB: \(text)") }
    func stopMorse() {}
    func setPTT(_ on: Bool, maximumDuration: TimeInterval = 16) { KeyLog.add("PTT \(on) via Icom USB") }
    func prepareForDigital(frequencyHz: UInt64) {}
    var rfPowerWatts: Double = 0
    var swr: Double = 1
    var alcLevel: Double = 0
    var sMeterValue: Double = 0
    var swrUpdatedAt: Date? = nil
}

final class Lab599TX500Driver {
    static let shared = Lab599TX500Driver()
    var isConnected = false
    var selectedPort = ""
    var formattedFrequency = ""
    var mode = ""
    func sendMorse(_ text: String, wpm: Int) { KeyLog.add("KEYED via Lab599 TX-500: \(text)") }
    func stopMorse() {}
    func setPTT(_ on: Bool, maximumDuration: TimeInterval = 14) { KeyLog.add("PTT \(on) via Lab599 TX-500") }
    func setFrequencyHz(_ hz: UInt64) {}
    var powerWatts = 0
    var sMeterValue: Double = 0
    var swrUpdatedAt: Date? = nil
    func checkFT8Receive() {}
    func keyFT8Verified(maximumDuration: TimeInterval, before deadline: Date) async throws {
        setPTT(true, maximumDuration: maximumDuration)
    }

}

final class Xiegu6100Driver {
    static let shared = Xiegu6100Driver()
    var isConnected = false
    var selectedPort = ""
    var formattedFrequency = ""
    var mode = ""
    func setKeyerSpeed(_ wpm: Int) {}
    func sendMorse(_ text: String) { KeyLog.add("KEYED via Xiegu X6100: \(text)") }
    func stopMorse() {}
    func setPTT(_ on: Bool, maximumDuration: TimeInterval = 15) { KeyLog.add("PTT \(on) via Xiegu X6100") }
    func prepareForDigital(frequencyHz: UInt64) {}
    var powerWatts = 0
    var swr: Double = 1
    var alcLevel: Double = 0
    var sMeterValue: Double = 0
    var swrUpdatedAt: Date? = nil
}

struct StubCTYEntity {
    let entityName = "Unknown"
    let flagEmoji = ""
    let continent = ""
}

struct StubCTYMatch { let entity = StubCTYEntity() }
final class CTYDatabaseManager {
    static let shared = CTYDatabaseManager()
    func lookup(callsign: String) -> StubCTYMatch? { nil }
}

final class TCIClient {
    static let shared = TCIClient()
    var isConnected = false
    func sendCW(text: String, wpm: Int) { KeyLog.add("KEYED via TCI: \(text)") }
    func stopCW() {}
}

final class FLRigClient {
    static let shared = FLRigClient()
    var isConnected = false
    var frequencyHz: Double = 0
    // The keyer calls sendMorse(text) at f83e099 and sendMorse(text, wpm:) once the flrig client of patch 32 is applied.
    // Tests/FlrigCWErrorRegression.swift sets sendMorseError to make it throw, as the real client does when flrig
    // refuses the text or does not answer (FLRigError), and sendMorseDelay for the time flrig takes to answer.
    var stopMorseError: Error?
    var sendMorseError: Error?
    var sendMorseDelay: TimeInterval = 0
    func sendMorse(_ text: String, wpm: Int? = nil) async throws {
        let answer = sendMorseError          // flrig's answer to this text, whatever the test sets meanwhile
        if sendMorseDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(sendMorseDelay * 1_000_000_000)) }
        if let answer { throw answer }
        KeyLog.add("KEYED via flrig: \(text)")
    }
    // Tests/CATStopDestinationRegression.swift checks where a CAT Morse STOP goes (the real stopMorse sends the stop
    // sequence to flrig whatever its last poll said).
    func stopMorse() async throws { KeyLog.add("CW STOP via flrig"); if let stopMorseError { throw stopMorseError } }
}

struct StubRigState { var isConnected = false }
struct StubRigSnapshot { var frequencyMHz = ""; var mode = "" }
final class RigControlClient {
    static let shared = RigControlClient()
    var state = StubRigState()
    var snapshot: StubRigSnapshot? = nil
    func sendMorse(_ text: String) { KeyLog.add("KEYED via rigctl: \(text)") }
    // Records every stop the keyer asks for (the real one sends nothing while rigctld is not connected).
    func stopMorse() { KeyLog.add("CW STOP via rigctl") }
    func setKeyerSpeed(_ wpm: Int) {}
    func setFrequencyHz(_ hz: UInt64) {}
    func setMode(_ m: String, passbandHz: Int) {}
    func setPTT(_ on: Bool, maximumDuration: TimeInterval = 14) { KeyLog.add("PTT \(on) via rigctl") }
}

struct CallHistoryRecord {
    var name = ""; var userExchange = ""; var state = ""; var arrlSection = ""; var gridSquare = ""; var cqZone = 0
}
final class CallHistoryLookupEngine {
    static let shared = CallHistoryLookupEngine()
    func lookup(callsign: String) -> CallHistoryRecord? { nil }
}

/// The names are those of YAAM/RigControlEngine.swift.
enum RigDriverType: String {
    case icomUSB = "Icom Transceiver (USB CI-V)", flrig = "Flrig (XML-RPC)", rigctld = "Hamlib (rigctld TCP)"
    case tx500 = "Lab599 TX-500 (USB-C Serial)", fx4cr = "FX-4CR (USB / Bluetooth)", xiegu6100 = "Xiegu X6100 (USB-C)"
    case disabled = "Disabled"
}

final class RigControlEngine {
    static let shared = RigControlEngine()
    /// "Disabled" by default, as when no radio is chosen, so tests that do not set it are not refused for it.
    var driverType: RigDriverType = .disabled
    var isConnected = false
    func setPTT(_ on: Bool) { KeyLog.add("PTT \(on) via RigControlEngine") }
    func capturePTTRelease() -> () -> Void { { KeyLog.add("PTT false via RigControlEngine") } }
}

// Icom network radio: only the members FT8EngineService uses.
struct StubIcomState { var isConnected = false }
enum IcomNetworkError: Error { case disconnected }
final class IcomNetworkRadio {
    var state = StubIcomState()
    var selectedModel = StubModel.ic7300MK2
    var transmitArmed = false
    var rfPowerWatts: Double = 0
    var swr: Double = 1
    var alcLevel: Double = 0
    var sMeterUnits: Double = 0
    var sMeterValue: Double = 0
    var swrUpdatedAt: Date? = nil
    func setFrequencyHz(_ hz: UInt64) {}
    func setUSBDataMode() {}
    func setPTT(_ on: Bool, maximumDuration: TimeInterval = 16) { KeyLog.add("PTT \(on) via Icom LAN") }
    func transmit(samples: [Float], gain: Float) async throws { KeyLog.add("Icom LAN audio") }
    var radioName = "stub"
    func setAudioSampleHandler(_ h: (([Float], Date) -> Void)?) {}
    nonisolated static func protocolSelfTest() -> Bool { true }
}

// AmateurBandPlan (OperatorModels.swift) pulls in half of the app; FT8EngineService only formats the dial with it.
nonisolated enum AmateurBandPlan {
    static func band(forMHz mhz: Double) -> String? { nil }
    static func formattedMHz(_ mhz: Double) -> String { String(format: "%.3f", mhz) }
}
