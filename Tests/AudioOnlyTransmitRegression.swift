import Foundation

@main
struct AudioOnlyTransmitRegression {
    static func main() {
        UserDefaults.standard.register(defaults: ["operatorCallsign": "EA3JIC"])
        let text = AudioOnlyTransmit.notice(mode: "Olivia 8/250", radio: "Hamlib")!
        precondition(text.contains("UTC") && text.contains("this mode does not key the radio") && text.contains("VOX or an external PTT"))
        precondition(text.contains("logging") && AudioOnlyTransmit.isNotice(text))
        precondition(AudioOnlyTransmit.notice(mode: "SSTV", radio: nil) == nil)
        let rig = RigControlEngine.shared
        rig.driverType = .flrig; rig.isConnected = true
        precondition(AudioOnlyTransmit.radioInUse() == "Flrig (XML-RPC)")
        rig.isConnected = false
        Lab599TX500Driver.shared.isConnected = true
        precondition(AudioOnlyTransmit.radioInUse() == "Lab599 TX-500")
        Lab599TX500Driver.shared.isConnected = false
        let olivia = OliviaMFSKEngine(), hell = HellschreiberEngine(), js8 = JS8Engine(), sstv = SSTVEngine()
        olivia.isTransmitting = true; olivia.txRefusal = text
        hell.isTransmitting = true; hell.txRefusal = text
        olivia.queueTextForTransmission("TEST")
        hell.queueTextForTransmission("TEST")
        precondition(olivia.txRefusal == text && hell.txRefusal == text)
        _ = TransmitShutdown.releaseAll()
        precondition(!olivia.isTransmitting && !hell.isTransmitting)
        precondition(olivia.txRefusal.isEmpty && hell.txRefusal.isEmpty)
        olivia.txRefusal = "Audio transmitter unavailable"
        olivia.stopTransmission()
        precondition(olivia.txRefusal == "Audio transmitter unavailable")
        js8.composerText = "CQ TEST"
        let count = js8.messages.count
        precondition(!js8.nativeTransmitAvailable && !js8.sendMessage(text: "CQ TEST", to: "@ALLCALL"))
        precondition(!js8.isTransmitting && js8.messages.count == count && js8.composerText == "CQ TEST")
        precondition(js8.transmitRefusal.contains("does not yet encode JS8") && js8.transmitRefusal.contains("no audio"))
        sstv.isTransmitting = true
        _ = TransmitShutdown.releaseAll()
        precondition(!sstv.isTransmitting)
        precondition(KeyLog.drain().allSatisfy { !$0.contains("PTT true") })
        print("PASS audio-only transparency, shutdown, preserved errors, and native JS8 refuses without audio/history/composer changes")
    }
}
