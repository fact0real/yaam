import Foundation
nonisolated enum CIVCapture {
    private static let lock=NSLock()
    nonisolated(unsafe) static var packet=Data()
    static func note(_ data:Data) { lock.lock(); defer{lock.unlock()}; if data.count>5 && data[4]==0x14 && data[5]==0x0C { packet=data } }
    static func latest()->Data { lock.lock();defer{lock.unlock()};return packet }
}
@main struct SerialLinkHealthRegression {
    static func pump(_ seconds:Double) { RunLoop.main.run(until:Date().addingTimeInterval(seconds)) }
    static func main() {
        SerialPortService.allowsOpen=true
        SerialPortService.writeReply={ command in command.contains("FA;") ? "FA00014074000;" : nil }
        let tx=Lab599TX500Driver.shared; tx.connect(port:"health-fixture")
        let fx=FX4CRDriver.shared; fx.connect(port:"health-fixture",type:.usb)
        SerialPortService.writeDataReply={ data in
            CIVCapture.note(data)
            guard data.count==6, data[4]==0x03 else{return nil}
            return Data([0xFE,0xFE,0xE0,data[2],0x03,0x00,0x40,0x07,0x14,0x00,0xFD])
        }
        let icom=IcomUSBRadioDriver.shared;icom.model = .ic7300;icom.connect(port:"health-fixture")
        let xiegu=Xiegu6100Driver.shared;xiegu.connect(port:"health-fixture")
        icom.setKeyerSpeed(6); precondition(Array(CIVCapture.latest().dropFirst(6).prefix(2))==[0,0])
        icom.setKeyerSpeed(45);precondition(Array(CIVCapture.latest().dropFirst(6).prefix(2))==[0x02,0x37],"Icom 14 0C requires two BCD bytes on its normalized scale")
        // Accelerated fixture sources keep all parsing and lifecycle logic, changing only clock intervals.
        pump(0.8)
        precondition(tx.isConnected && fx.isConnected && icom.isConnected && xiegu.isConnected,"Fresh replies keep every transport connected: TX500 \(tx.isConnected) FX \(fx.isConnected) Icom \(icom.isConnected) Xiegu \(xiegu.isConnected)")
        SerialPortService.writeReply=nil;SerialPortService.writeDataReply=nil
        pump(0.6)
        precondition(!tx.isConnected && !fx.isConnected && !icom.isConnected && !xiegu.isConnected,"A silent but open UART cannot remain connected")
        precondition(TransmitNotices.shared.notices.filter{$0.text.contains("CAT stopped answering")}.count>=4)
        tx.disconnect();fx.disconnect();icom.disconnect();xiegu.disconnect()
        print("PASS real driver parsers: healthy replies, silent-link expiration, persistent RX uncertainty and Icom normalized BCD speed; fake ports only")
    }
}
