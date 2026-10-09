//
//  PracticeRecordDiscardRegression.swift
//  YAAM
//
//  The practice (SSTV and Olivia) puts no callsign in CALL. With patch 41, LOG SSTV QSO hands the callsign to the
//  Digital Suite's confirmation, where Record QSO and Discard QSO are (DigitalQSOConfirmationRegression).
//  Run from the repository root:
//    swiftc -parse-as-library Tests/PracticeRecordDiscardRegression.swift YAAM/SSTVEngine.swift YAAM/OliviaMFSKEngine.swift \
//      YAAM/TransmitIdentity.swift YAAM/GridLocator.swift -o prd && ./prd
//  The logging handler is replaced by a counter. In the app it is the only way to the logbook and to the upload queue
//  (DigitalMasterStationView.wireLoggingCallbacks -> AppState.logDigitalModemQSO). No audio engine is started. The
//  Olivia practice runs for 3 s. The operators in the QSOs are EA3JIC and EP2AES.
//

import Foundation

@main
struct PracticeRecordDiscardRegression {
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

    struct Logged: Equatable {
        let call: String, mode: String, sent: String, rcvd: String, freqHz: UInt64, band: String
    }

    @MainActor
    static func main() {
        // 1. Practice: CALL stays empty
        let sstv = SSTVEngine()
        sstv.startSimulation()
        check("SSTV practice puts no callsign in CALL", sstv.targetCallsign.isEmpty, "CALL = \(sstv.targetCallsign)")
        sstv.stopSimulation()

        let olivia = OliviaMFSKEngine()
        olivia.startSimulation()
        RunLoop.main.run(until: Date().addingTimeInterval(3.0))
        let practiceText = olivia.rxText
        let oliviaCall = olivia.targetCallsign
        olivia.stopSimulation()
        check("Olivia practice text reached the terminal", practiceText.contains("CQ CQ DE G4ABC"), "rxText = \(practiceText.prefix(30))")
        check("Olivia practice puts no callsign in CALL", oliviaCall.isEmpty, "CALL = \(oliviaCall)")

        // 2. LOG SSTV QSO saves nothing by itself: it hands the callsign to the Digital Suite, which always asks first.
        //    Record QSO and Discard QSO are checked in DigitalQSOConfirmationRegression (patch 41).
        var handed: [Logged] = []
        sstv.logQSOHandler = { handed.append(Logged(call: $0, mode: $1, sent: $2, rcvd: $3, freqHz: $4, band: $5)) }
        sstv.targetCallsign = "EA3JIC"
        sstv.logCurrentQSO()
        check("LOG SSTV QSO hands only the callsign: no fixed reports, frequency or band", handed == [
            Logged(call: "EA3JIC", mode: "SSTV", sent: "", rcvd: "", freqHz: 0, band: "")
        ], "\(handed)")
        finish()
    }

    static func finish() {
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
