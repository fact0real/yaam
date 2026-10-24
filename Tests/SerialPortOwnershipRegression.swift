import Foundation
import Darwin
@main struct SerialPortOwnershipRegression {
    static func main() {
        var master:Int32 = -1, slave:Int32 = -1
        precondition(openpty(&master,&slave,nil,nil,nil)==0)
        let path=String(cString:ttyname(slave)); close(slave)
        defer { close(master) }
        let first=SerialPortService(), second=SerialPortService()
        precondition(first.openPort(path:path,baudRate:9600))
        precondition(!second.openPort(path:path,baudRate:9600), "Two YAAM tools must not share one UART")
        let bytes=Data("KY TEST;RX;".utf8)
        precondition(first.writeData(bytes))
        var received=[UInt8](repeating:0,count:64)
        let count=read(master,&received,64)
        precondition(count==bytes.count && Data(received.prefix(count))==bytes)
        // Fill the nonblocking tty while its peer stops consuming; never spin forever on EAGAIN.
        let started=ProcessInfo.processInfo.systemUptime
        precondition(!first.writeData(Data(repeating:0x41,count:2_000_000)))
        precondition(ProcessInfo.processInfo.systemUptime-started<0.8 && first.lastError != nil)
        let closing=ProcessInfo.processInfo.systemUptime
        first.closePort()
        precondition(ProcessInfo.processInfo.systemUptime-closing<0.6 && !first.isOpen)
        print("PASS real PTY: exclusive UART ownership, exact byte delivery, bounded backpressure/retry and bounded close; no radio")
    }
}
