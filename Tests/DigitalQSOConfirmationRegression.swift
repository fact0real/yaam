//
//  DigitalQSOConfirmationRegression.swift
//  YAAM
//
//  Digital Suite QSOs take the radio's frequency and band, and the operator confirms them when something is missing,
//  for SSTV, or with the "Always" setting.
//  Run from the repository root:
//    swiftc -parse-as-library Tests/DigitalQSOConfirmationRegression.swift YAAM/DigitalQSOConfirmation.swift \
//      YAAM/OperatorModels.swift YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift \
//      YAAM/CountryFlagEngine.swift YAAM/CountryNameNormalizer.swift -o dqc && ./dqc
//  The band comes from the Quick Log's band plan (AmateurBandPlan). The logbook is replaced by a counter. The parts
//  that need the whole app (AppState, the Digital Suite view, the sheet) are checked in their source. Nothing opens
//  a port, a device or the microphone. The operators are EA3JIC and EP2AES.
//

import Foundation

// Stand-in for the app's QSO record: only what YAAM/PortableActivity.swift reads (OperatorModels.swift needs that file)
nonisolated struct QSORecordModel {
    var fields: [String: String] = [:]
    var isConfirmed = false
    subscript(key: String) -> String { fields[key] ?? "" }
}

@main
struct DigitalQSOConfirmationRegression {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            passes += 1
            print("PASS \(label)")
        } else {
            failures += 1
            let extra = detail()
            print("FAIL \(label)" + (extra.isEmpty ? "" : "   [\(extra)]"))
        }
    }

    static func source(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    /// The text of a function, from its declaration to the next "    func " or "    private func " at the same indent.
    static func body(of declaration: String, in text: String) -> String {
        guard let start = text.range(of: declaration) else { return "" }
        let rest = text[start.upperBound...]
        let end = [rest.range(of: "\n    func "), rest.range(of: "\n    private func ")].compactMap { $0?.lowerBound }.min()
        return String(rest[..<(end ?? rest.endIndex)])
    }

    static func draft(_ call: String, _ mode: String, _ sent: String, _ rcvd: String, radio: UInt64?) -> DigitalQSODraft {
        DigitalQSODraft(callsign: call, mode: mode, reportSent: sent, reportReceived: rcvd, radioFrequencyHz: radio)
    }

    @MainActor
    static func main() {
        radio()
        drafts()
        confirmation()
        center()
        app()
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // 1. The radio's frequency: only from a connected source, never a built-in value
    static func radio() {
        typealias S = RadioFrequency.Source
        check("no source connected: no frequency", RadioFrequency.firstConnected([]) == nil)
        check("sources not connected are not read, though they hold 14.074 MHz",
              RadioFrequency.firstConnected([S(isConnected: false, frequencyHz: 14_074_000), S(isConnected: false, frequencyHz: 14_074_000)]) == nil)
        check("the first connected source gives the frequency",
              RadioFrequency.firstConnected([S(isConnected: false, frequencyHz: 14_074_000), S(isConnected: true, frequencyHz: 7_040_000),
                                             S(isConnected: true, frequencyHz: 3_573_000)]) == 7_040_000)
        check("a connected source at 0 Hz is skipped",
              RadioFrequency.firstConnected([S(isConnected: true, frequencyHz: 0), S(isConnected: true, frequencyHz: 21_074_000)]) == 21_074_000)
    }

    // 2. The draft: frequency and band as the Quick Log reads them
    static func drafts() {
        let sstv = draft("EA3JIC", "SSTV", "", "", radio: 14_230_000)
        check("from the radio at 14.230 MHz: 14.23, 20m",
              sstv.frequencyText == "14.23" && sstv.band == "20m" && sstv.frequencyHz == 14_230_000,
              "\(sstv.frequencyText) \(String(describing: sstv.band))")
        check("from the radio at 7.074 MHz: 40m", draft("EA3JIC", "RTTY", "599", "599", radio: 7_074_000).band == "40m")
        let none = draft("EA3JIC", "RTTY", "599", "599", radio: nil)
        check("no radio: the frequency is empty and the QSO is not complete", none.frequencyText.isEmpty && none.band == nil && !none.isComplete)
        for (typed, band) in [("7.074", "40m"), ("7074", "40m"), ("14,230", "20m"), ("3573000", "80m")] {
            var d = none
            d.frequencyText = typed
            check("typed \"\(typed)\": \(band)", d.band == band && d.isComplete, "\(String(describing: d.band))")
        }
        for typed in ["15.000", "abc", "0"] {
            var d = none
            d.frequencyText = typed
            check("typed \"\(typed)\": outside the bands, not complete", d.band == nil && !d.isComplete)
        }
        var rsv = sstv
        rsv.reportSent = "595"
        rsv.reportReceived = "575"
        check("SSTV with RSV 595 and 575 is complete", rsv.isComplete)
        rsv.reportReceived = "599"
        check("SSTV with 599 is not an RSV report (video 1-5)", !rsv.isComplete)
        check("JS8 with -10 and -12 is complete", draft("EP2AES", "JS8", "-10", "-12", radio: 14_078_000).isComplete)
        check("an empty report is not complete", !draft("EP2AES", "OLIVIA", "", "599", radio: 14_072_000).isComplete)
        check("an empty callsign is not complete", !draft(" ", "OLIVIA", "599", "599", radio: 14_072_000).isComplete)
    }

    // 3. When the operator is asked
    static func confirmation() {
        let complete = draft("EA3JIC", "RTTY", "599", "599", radio: 14_085_000)
        check("radio connected, nothing missing, setting \"only when missing\": saved without asking",
              !complete.needsConfirmation(.whenFrequencyMissing))
        check("setting \"Always\": asked", complete.needsConfirmation(.always))
        check("no radio: asked", draft("EA3JIC", "RTTY", "599", "599", radio: nil).needsConfirmation(.whenFrequencyMissing))
        check("SSTV: always asked", draft("EA3JIC", "SSTV", "595", "575", radio: 14_230_000).needsConfirmation(.whenFrequencyMissing))
        check("an empty callsign: asked", draft("", "HELL", "599", "599", radio: 14_063_000).needsConfirmation(.whenFrequencyMissing))
        check("the setting starts at \"only when missing\"", DigitalQSOConfirmationMode.current == .whenFrequencyMissing)
        let texts = DigitalQSOConfirmationMode.allCases.map(\.tradeOffs)
        check("each option, the default too, says what it is good and not good for",
              texts.allSatisfy { $0.contains("Good for: ") && $0.contains("Not good for: ") } && Set(texts).count == texts.count)
    }

    // 4. Record QSO and Discard QSO
    @MainActor
    static func center() {
        let center = DigitalQSOConfirmationCenter()
        var saved: [DigitalQSODraft] = []
        center.record = { saved.append($0) }

        center.submit(draft("EA3JIC", "RTTY", "599", "579", radio: 14_085_000), setting: .whenFrequencyMissing)
        check("with the radio, a complete QSO is saved at once with the radio's frequency",
              saved.count == 1 && saved.last?.frequencyHz == 14_085_000 && saved.last?.band == "20m" && center.pending == nil)

        center.submit(draft("EP2AES", "OLIVIA", "599", "599", radio: nil), setting: .whenFrequencyMissing)
        check("without a radio, the QSO waits for the operator and nothing is saved", center.pending?.callsign == "EP2AES" && saved.count == 1)
        guard var waiting = center.pending else { return }
        check("Record QSO with no frequency saves nothing", center.recordPending(waiting) == false && saved.count == 1)
        waiting.frequencyText = "7.074"
        check("Record QSO with 7.074 saves one QSO on 40m",
              center.recordPending(waiting) && saved.count == 2 && saved.last?.frequencyHz == 7_074_000 && saved.last?.band == "40m")
        check("after Record QSO the confirmation is closed", center.pending == nil)

        center.submit(draft("EA3JIC", "SSTV", "", "", radio: 14_230_000), setting: .whenFrequencyMissing)
        check("an SSTV QSO waits for the operator, with the radio's frequency", center.pending?.frequencyText == "14.23" && saved.count == 2)
        center.discardPending()
        check("Discard QSO saves nothing and closes the confirmation", center.pending == nil && saved.count == 2)
    }

    // 5. The app, in its source
    static func app() {
        let features = source("YAAM/AppStateRadioContestFeatures.swift")
        let log = body(of: "func logDigitalModemQSO(", in: features)
        check("logDigitalModemQSO takes the radio's frequency, not the engine's, and hands the QSO to the confirmation",
              log.contains("radioFrequencyHz: currentRadioFrequencyHz()") && log.contains("DigitalQSOConfirmationCenter.shared.submit(draft, setting: .current)")
              && !log.contains("saveDigitalModemQSO"))
        let record = body(of: "func recordDigitalModemQSO(", in: features)
        check("recordDigitalModemQSO saves with the draft's frequency and band",
              record.contains("guard draft.isComplete, let freqHz = draft.frequencyHz, let band = draft.band") && record.contains("freqHz: freqHz, band: band"))
        let radio = body(of: "func currentRadioFrequencyHz(", in: features)
        check("the radio's frequency is read from eight sources, each only while connected",
              radio.components(separatedBy: "isConnected:").count - 1 == 8 && radio.components(separatedBy: ".isConnected").count - 1 == 8)
        check("the confirmed QSOs are saved by AppState", features.contains("DigitalQSOConfirmationCenter.shared.record = { [weak self] draft in"))
        let suite = source("YAAM/DigitalMasterStationView.swift")
        check("the Digital Suite shows the confirmation and the setting",
              suite.contains(".sheet(item: $confirmations.pending)") && suite.contains("DigitalQSOConfirmationModePicker()"))
        check("under the setting, the text of the option chosen", source("YAAM/DigitalQSOConfirmationSheet.swift").contains("Text(setting.tradeOffs)"))
        let sheet = source("YAAM/DigitalQSOConfirmationSheet.swift")
        check("the confirmation has Record QSO, needing a complete QSO, and Discard QSO",
              sheet.contains("Button(\"Record QSO\")") && sheet.contains(".disabled(!draft.isComplete)")
              && sheet.contains("Button(\"Discard QSO\", role: .cancel)"))
        check("the frequency can be typed in the confirmation", sheet.contains("TextField(\"Frequency (MHz)\", text: $draft.frequencyText)"))
    }
}
