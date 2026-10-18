// Runs the real keyer against recording drivers; never connects or transmits.
// Included by run-cw-safety-regressions.sh.
import Foundation

@main
@MainActor
struct CWConnectionLossRegression {
    static func tick(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    static func main() {
        let keyer = CWKeyerService.shared
        keyer.sidetoneEnabled = false
        keyer.useCutNumbers = false
        keyer.wpm = 20
        RigControlClient.shared.state.isConnected = true
        keyer.transmissionMode = .catMorse
        precondition(keyer.hardwareStatusSummary.isConnected, "A connected rigctld must work before Operator Desk appears")
        keyer.send(text: "CQ CQ CQ CQ CQ CQ", myCall: "EA3XYZ")
        tick(0.1)
        precondition(KeyLog.drain().contains { $0.contains("KEYED via rigctl") })
        // A different connected driver must not conceal loss of the actual destination.
        FX4CRDriver.shared.isConnected = true
        RigControlClient.shared.state.isConnected = false
        tick(0.4)
        precondition(!keyer.isTransmitting && !keyer.isAutoCQActive)
        precondition(keyer.transmitRefusal.contains("rigctld"))
        precondition(KeyLog.drain().contains("CW STOP via rigctl"))
        FX4CRDriver.shared.isConnected = false
        for (mode, connect, disconnect, name) in [
            (CWTransmissionMode.lab599TX500, { Lab599TX500Driver.shared.isConnected = true }, { Lab599TX500Driver.shared.isConnected = false }, "TX-500"),
            (.fx4cr, { FX4CRDriver.shared.isConnected = true }, { FX4CRDriver.shared.isConnected = false }, "FX-4CR"),
            (.icomUSB, { IcomUSBRadioDriver.shared.isConnected = true }, { IcomUSBRadioDriver.shared.isConnected = false }, "Icom"),
            (.xiegu6100, { Xiegu6100Driver.shared.isConnected = true }, { Xiegu6100Driver.shared.isConnected = false }, "Xiegu")
        ] {
            connect()
            keyer.transmissionMode = mode
            keyer.send(text: "CQ CQ CQ CQ CQ CQ", myCall: "EA3XYZ")
            tick(0.1)
            precondition(keyer.isTransmitting)
            disconnect()
            tick(0.4)
            precondition(!keyer.isTransmitting && keyer.transmitRefusal.contains(name))
        }
        // Cancellation of an old watcher must not stop a replacement message.
        Lab599TX500Driver.shared.isConnected = true
        keyer.transmissionMode = .lab599TX500
        keyer.send(text: "CQ CQ CQ", myCall: "EA3XYZ")
        tick(0.05)
        keyer.stop()
        keyer.send(text: "CQ CQ CQ", myCall: "EA3XYZ")
        tick(0.3)
        precondition(keyer.isTransmitting && keyer.transmitRefusal.isEmpty)
        keyer.stop()
        print("CWConnectionLossRegression passed: shared rigctld, five destinations, replacement cancellation")
    }
}
