import Foundation
import Network

struct DXSpot {
    var callsign="EA3JIC", spotter="EP2AES", comment="", grid="", mode="FT8", band="20M"
    var frequencyKHz=14074.0
    var lastSeenAt=Date()
}
enum GregorianDate {
    static func formatter(_ format: String, timeZone: TimeZone?) -> DateFormatter {
        let value=DateFormatter(); value.dateFormat=format; value.timeZone=timeZone; return value
    }
}
@main struct LocalClusterBoundaryRegression {
    static func pump(_ condition: () -> Bool, seconds: Double=3) -> Bool {
        let deadline=Date().addingTimeInterval(seconds)
        while !condition() && deadline.timeIntervalSinceNow>0 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return condition()
    }
    static func main() {
        let name="YAAM-local-feed-test-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        defaults.set(999999, forKey:"localClusterServerPort")
        let server=LocalClusterServer(defaults:defaults)
        precondition(server.port==7300 && !server.udpEnabled && !server.isRunning)
        server.port=999999; server.start()
        precondition(pump({server.lastErrorMessage != nil}) && !server.isRunning, "Invalid ports must fail without a UInt16 trap")
        server.port=47383; server.start(); server.start()
        let started=pump({server.isRunning})
        if !started { print("Loopback listener diagnostic: \(server.lastErrorMessage ?? "none")") }
        precondition(started, "Repeated Start must produce one listener")
        let client=NWConnection(host:"127.0.0.1",port:47383,using:.tcp)
        let queue=DispatchQueue(label:"YAAM-local-feed-fixture")
        client.start(queue:queue)
        precondition(pump({server.clientCount==1}))
        client.send(content:Data(repeating:65,count:10000),completion:.contentProcessed({_ in}))
        precondition(pump({server.clientCount==0}), "A line exceeding the receive bound must close its connection")
        client.cancel()
        server.stop(); precondition(pump({!server.isRunning}))
        print("Local feed default-off, invalid-port, duplicate-start and oversized-input checks passed on loopback only")
    }
}
