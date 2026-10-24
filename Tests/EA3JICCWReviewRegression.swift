import Foundation
import Network
// Capture cwdaemon datagrams without opening a socket.
nonisolated final class NWConnection: @unchecked Sendable {
    enum SendCompletion { case contentProcessed(@Sendable (NWError?) -> Void) }
    nonisolated(unsafe) static var packets: [Data] = []
    init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters) {}
    func start(queue: DispatchQueue) {}
    func cancel() {}
    func send(content: Data?, completion: SendCompletion) {
        if let content { Self.packets.append(content) }
        if case .contentProcessed(let done)=completion { done(nil) }
    }
}

private enum Refused: LocalizedError { case cat; var errorDescription: String? { "fixture CAT rejection" } }
@main struct EA3JICCWReviewRegression {
    static func pump(_ seconds: Double = 0.05) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    static func main() {
        let keys = ["cwKeyerWPM", "cwMaximumMessageSeconds", "cwAutoCQMaximumCalls", "cwAutoCQMaximumMinutes"]
        let saved = keys.map { UserDefaults.standard.object(forKey:$0) }
        defer { for (key,value) in zip(keys,saved) { if let value { UserDefaults.standard.set(value,forKey:key) } else { UserDefaults.standard.removeObject(forKey:key) } } }
        let keyer=CWKeyerService.shared, flrig=FLRigClient.shared
        keyer.transmissionMode = .catMorse; keyer.sidetoneEnabled=false; keyer.useCutNumbers=false
        flrig.isConnected=true; flrig.sendMorseDelay=0.15; flrig.sendMorseError=Refused.cat
        let esm=ContestESMEngine(); esm.isESMEnabled=true; esm.myCallsign="EA3JIC"
        var call="EP2AES", exchange="001", logged=0
        esm.handleEnterPressed(callsign:&call,sentExchange:"002",rcvdExchange:&exchange) { logged += 1; return true }
        precondition(logged==0); pump(0.35)
        precondition(logged==0 && esm.statusMessage.contains("rejection"), "Late CAT rejection must not log/advance the QSO")
        flrig.sendMorseError=nil
        esm.handleEnterPressed(callsign:&call,sentExchange:"002",rcvdExchange:&exchange) { logged += 1; return true }
        precondition(logged==0); keyer.stop(); pump(0.3)
        precondition(logged==0, "STOP must invalidate pending acceptance")
        esm.handleEnterPressed(callsign:&call,sentExchange:"002",rcvdExchange:&exchange) { logged += 1; return true }
        pump(0.3); precondition(logged==1)
        keyer.stop(); pump(); precondition(!esm.isTransmitting && esm.activeOutgoingText.isEmpty, "ESM HUD must clear after keyer STOP")
        flrig.stopMorseError=Refused.cat; keyer.stop(); pump()
        precondition(keyer.operationNotice.contains("CW stop was not confirmed"))
        flrig.stopMorseError=nil; keyer.send(text:"E",myCall:"EA3JIC"); pump(0.3)
        precondition(!keyer.operationNotice.isEmpty, "A later send must not erase the stop warning")
        keyer.stop(); _=KeyLog.drain(); keyer.setWPM(5); keyer.maximumMessageSeconds=10
        keyer.send(text:String(repeating:"TEST ",count:50),myCall:"EA3JIC")
        precondition(!keyer.isTransmitting && keyer.transmitRefusal.contains("limit"))
        precondition(!KeyLog.drain().contains { $0.hasPrefix("KEYED") })
        keyer.maximumMessageSeconds=120; keyer.setWPM(60); keyer.autoCQMaximumCalls=1; keyer.autoCQIntervalSeconds=1
        keyer.startAutoCQ(template:"E",myCall:"EA3JIC"); pump(2)
        precondition(!keyer.isAutoCQActive && keyer.operationNotice.contains("1 calls"))
        keyer.stop(); keyer.autoCQMaximumCalls=20
        keyer.startAutoCQ(template:"E",myCall:"EA3JIC"); pump(0.3)
        NotificationCenter.default.post(name:Notification.Name("YAAMRadioConnectionLost"),object:IcomUSBRadioDriver.shared)
        precondition(keyer.isAutoCQActive,"An unrelated radio must not cancel this keyer")
        NotificationCenter.default.post(name:Notification.Name("YAAMRadioConnectionLost"),object:flrig)
        precondition(!keyer.isAutoCQActive && !keyer.isTransmitting,"Link loss must cancel a producer immediately, even before a connected flag changes or a quick reconnect")
        keyer.stop(); _=KeyLog.drain()
        keyer.send(text:"E",myCall:"EA3JIC")
        NotificationCenter.default.post(name:Notification.Name("YAAMRadioConnectionLost"),object:flrig)
        pump(0.3)
        precondition(!KeyLog.drain().contains{$0.hasPrefix("KEYED")},"Loss before backend handoff cancels pending CW, too")
        keyer.stop(); keyer.setWPM(Int.min); precondition(keyer.wpm==5)
        keyer.setWPM(Int.max); precondition(keyer.wpm==60)
        IcomUSBRadioDriver.shared.isConnected=true; keyer.transmissionMode = .icomUSB
        keyer.send(text:"E",myCall:"EA3JIC"); precondition(keyer.wpm==45); keyer.stop()
        keyer.transmissionMode = .cwdaemon
        keyer.cwdaemonHost="fixture.invalid"; keyer.cwdaemonPort=6789
        keyer.send(text:"E",myCall:"EA3JIC"); pump()
        keyer.stop()
        precondition(NWConnection.packets.last==Data([0x1B,0x34]),"cwdaemon STOP must abort the message with ESC4")
        precondition(!NWConnection.packets.contains(Data([0x1B,0x35])),"STOP must never exit the daemon")
        print("PASS asynchronous ESM acceptance/refusal/cancellation, persistent CW-stop failure, time/count limits and WPM boundaries; no devices")
    }
}
