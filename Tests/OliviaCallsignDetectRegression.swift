// Experimental Olivia must never turn practice or synthetic receive text into a contact.
// Run via Tests/run-board-priorities-regressions.sh; no audio devices or transports are opened.
import Foundation

@main @MainActor
struct OliviaCallsignDetectRegression {
    static func main() {
        let engine = OliviaMFSKEngine()
        for char in "CQ DE G4ABC 599 K " { engine.appendDecodedChar(char) }
        precondition(engine.targetCallsign.isEmpty, "Practice text must never populate CALL")
        precondition(engine.rxText.contains("G4ABC"))
        var saved: [(String, String, String, String, UInt64, String)] = []
        engine.logQSOHandler = { saved.append(($0, $1, $2, $3, $4, $5)) }
        engine.logCurrentQSO()
        precondition(saved.isEmpty)
        engine.targetCallsign = "K1ABC"
        engine.isSimulationActive = true
        engine.logCurrentQSO()
        precondition(saved.isEmpty && engine.targetCallsign == "K1ABC", "Simulation must refuse logging even with manual CALL")
        engine.isSimulationActive = false
        engine.logCurrentQSO()
        precondition(saved.count == 1 && saved[0].0 == "K1ABC")
        precondition(saved[0].2.isEmpty && saved[0].3.isEmpty && saved[0].4 == 0 && saved[0].5.isEmpty,
                     "Manual review receives no invented reports, frequency or band")
        precondition(engine.targetCallsign.isEmpty)
        print("PASS Olivia practice isolation, simulation logging refusal and manual contact review without invented fields")
    }
}
