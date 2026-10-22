import Foundation
import FT8Codec
import FT8808Engine

/// A scheduled MainActor task is cancelled synchronously before yielding; no waveform or output is ever created.
@main
struct FT8TransmitShutdownRegression {
    static func main() {
        let engine = FT8EngineService()
        engine.myCall = "EP2AES"; engine.myGrid = "LL35"
        engine.txText = "CQ EP2AES LL35"
        engine.audioPath = .lab599TX500
        Lab599TX500Driver.shared.isConnected = true
        engine.transmitArmed = true
        engine.autoSequenceEnabled = true
        engine.autoHunterEnabled = true
        engine.isCallingCQContinually = true
        engine.scheduleTransmission()
        precondition(engine.isTransmitScheduled)
        TransmitShutdown.beginShutdown()
        precondition(TransmitShutdown.releaseAll().contains("FT8/FT4"))
        precondition(!engine.isTransmitScheduled && !engine.transmitArmed && !engine.isCallingCQContinually)
        precondition(!engine.autoSequenceEnabled && !engine.autoHunterEnabled)
        engine.transmitArmed = true
        engine.scheduleTransmission()
        precondition(!engine.isTransmitScheduled, "Shutdown must reject a newly scheduled slot")
        precondition(!KeyLog.drain().contains { $0.contains("PTT true") })
        print("PASS actual FT8 engine: scheduled slot cancelled, auto modes disarmed and new slots refused before any codec/audio/PTT task runs")
    }
}
