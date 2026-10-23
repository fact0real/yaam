import Foundation

nonisolated final class VFOURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var vfo = "14074000"
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
        }
        let body = String(decoding: data, as: UTF8.self)
        let value = body.contains("rig.get_xcvr") ? "DUMMY" : body.contains("rig.get_vfo") ? Self.vfo : body.contains("rig.get_mode") ? "USB" : "0"
        let reply = "<methodResponse><params><param><value><string>\(value)</string></value></param></params></methodResponse>"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct FlrigOutsideVFORegression {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VFOURLProtocol.self]
        let client = FLRigClient(session: URLSession(configuration: config))
        client.pollingInterval = 3600
        client.connect(host: "fixture.invalid")
        try await Task.sleep(for: .milliseconds(150))
        await client.pollRigStatus()
        precondition(client.isConnected && client.frequencyHz == 14_074_000)
        for value in ["nan", "inf", "-5", "1e30", "18446744073709551616"] {
            VFOURLProtocol.vfo = value
            await client.pollRigStatus()
            precondition(client.frequencyHz == 14_074_000, "Invalid VFO must never enter published state")
        }
        VFOURLProtocol.vfo = "7030000.5"
        await client.pollRigStatus()
        precondition(client.frequencyHz == 7_030_000.5)
        client.stopPolling()
        print("PASS actual FLRig client rejects malformed VFOs and accepts fractional valid hertz; mocked HTTP only")
    }
}
