//
//  PracticeRecordDiscardRegression.swift
//  YAAM
//
//  The practice (SSTV and Olivia) puts no callsign in CALL, and an SSTV QSO is saved only with Record QSO.
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

        // 2. Record QSO: one QSO, with what the operator confirmed
        var logged: [Logged] = []
        sstv.logQSOHandler = { logged.append(Logged(call: $0, mode: $1, sent: $2, rcvd: $3, freqHz: $4, band: $5)) }
        sstv.targetCallsign = "EA3JIC"
        sstv.logCurrentQSO()
        check("LOG SSTV QSO opens the confirmation with the callsign from CALL, and saves nothing",
              sstv.pendingLog?.callsign == "EA3JIC" && logged.isEmpty, "\(logged)")
        guard var draft = sstv.pendingLog else {
            check("the confirmation is open", false)
            return finish()
        }
        check("Record QSO without the RSV reports saves nothing", sstv.logConfirmedQSO(draft) == false && logged.isEmpty)
        draft.rsvSent = "595"
        draft.rsvReceived = "575"
        sstv.logConfirmedQSO(draft)
        check("Record QSO saves one QSO with the values confirmed", logged == [
            Logged(call: "EA3JIC", mode: "SSTV", sent: "595", rcvd: "575", freqHz: 14_230_000, band: "20m")
        ], "\(logged)")

        // 3. Discard QSO: nothing
        sstv.targetCallsign = "EP2AES"
        sstv.logCurrentQSO()
        sstv.discardPendingLog()
        check("Discard QSO saves nothing and closes the confirmation", logged.count == 1 && sstv.pendingLog == nil, "\(logged)")

        // The two buttons, in the view
        let view = (try? String(contentsOfFile: "YAAM/SSTVStudioView.swift", encoding: .utf8)) ?? ""
        check("the confirmation has Record QSO and Discard QSO",
              view.contains("Button(\"Record QSO\")") && view.contains("Button(\"Discard QSO\", role: .cancel)")
              && view.contains(".sheet(item: $engine.pendingLog)"))
        finish()
    }

    static func finish() {
        print("\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
