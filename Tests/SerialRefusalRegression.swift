import Foundation

@main struct SerialRefusalRegression {
    static func pump(_ seconds: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    static func main() {
        UserDefaults.standard.set(false, forKey: "lab599AutoConnect")
        UserDefaults.standard.set(false, forKey: "fx4crAutoConnect")
        UserDefaults.standard.set(false, forKey: "icomUSBAutoConnect")
        SerialPortService.allowsOpen = true
        SerialPortService.writeReply = { command in
            if command == "KY ;RX;" || command == "RX;" { return "?;" }
            if command == "MD;" { return "MD6;" }
            if command == "PT;" { return "PT1;" }
            return nil
        }
        let tx = Lab599TX500Driver.shared
        tx.connect(port: "fixture.invalid")
        tx.sendMorse("CQ TEST")
        tx.stopMorse(); pump()
        precondition(tx.catError != nil)
        precondition(!tx.lastMessage.contains("Aborted"))
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("TX-500") && $0.text.contains("?;") })
        pump(0.5)
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("fresh PT0 receive was NOT confirmed") })
        tx.disconnect()
        print("PASS real TX-500 parser exposes rejected CW stop and missing RX readback; no success claim")
        let fx = FX4CRDriver.shared
        fx.connect(port: "fixture.invalid", type: .usb)
        fx.sendMorse("CQ TEST"); fx.stopMorse(); pump()
        precondition(fx.catError?.contains("?;") == true)
        precondition(!fx.lastMessage.contains("Aborted"))
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("FX-4CR") && $0.text.contains("?;") })
        fx.disconnect()
        SerialPortService.writeReply = nil
        print("PASS real FX-4CR parser exposes ?; and never infers RX from absence of an error")
        let icom = IcomUSBRadioDriver.shared
        icom.model = .ic7300
        icom.connect(port: "fixture.invalid"); pump()
        SerialPortService.writeDataReply = { data in
            guard data.count > 5, data[4] == 0x1C else { return nil }
            return Data([0xFE, 0xFE, 0xE0, 0x94, 0xFA, 0xFD])
        }
        icom.setPTT(true); icom.setPTT(false); pump()
        precondition(icom.catError?.contains("NAK") == true)
        precondition(TransmitNotices.shared.notices.contains { $0.text.contains("Icom USB") && $0.text.contains("NAK") })
        SerialPortService.writeDataReply = { data in
            guard data.count == 7, data[4] == 0x1C, data[5] == 0 else { return nil }
            return Data([0xFE, 0xFE, 0xE0, 0x94, 0x1C, 0x00, 0x00, 0xFD])
        }
        icom.setPTT(false); pump()
        precondition(icom.lastMessage.contains("fresh CI-V status reports receive"))
        precondition(!icom.isTransmitting)
        SerialPortService.writeDataReply = nil
        icom.stopMorse(); pump(0.6)
        precondition(icom.catError?.contains("not confirmed") == true)
        icom.disconnect()
        print("PASS real Icom NAK/status parser: rejected release, 1C 00 payload indexing, fresh RX, silence timeout; no devices")
    }
}
