import Foundation

final class InboxFixtureProtocol: URLProtocol, @unchecked Sendable {
    static var requests: [URL] = []
    static var landing = "<a href='../DownloadedFiles/fixture-long-name.adi'>.ADI file</a>"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        Self.requests.append(url)
        let body = url.pathExtension == "adi" ? "<ADIF_VER:5>3.1.6<EOH><CALL:5>ON5AM<QSO_DATE:8>20260709<EOR>" : Self.landing
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct EQSLInboxDownloadRegression {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InboxFixtureProtocol.self]
        let session = URLSession(configuration: config)
        let url = URL(string: "https://www.eqsl.cc/qslcard/DownloadInBox.cfm")!
        let adif = try await EQSLInboxDownload.download(session: session, url: url)
        precondition(adif.contains("ON5AM") && InboxFixtureProtocol.requests.count == 2)
        precondition(InboxFixtureProtocol.requests.last!.path == "/DownloadedFiles/fixture-long-name.adi")
        precondition(EQSLInboxDownload.adifURL(in: "<a href='https://attacker.invalid/stolen.adi'>.ADI</a>", relativeTo: url) == nil)
        InboxFixtureProtocol.landing = "<html>Service unavailable</html>"
        do { _ = try await EQSLInboxDownload.download(session: session, url: url); preconditionFailure("HTML treated as empty inbox") } catch {}
        InboxFixtureProtocol.landing = "Error: No such Callsign found"
        do { _ = try await EQSLInboxDownload.download(session: session, url: url); preconditionFailure("Login error ignored") } catch { precondition((error as NSError).code == 401) }
        precondition(EQSLInboxDownload.failure(in: "Error: Missing QSOMode parameter") != nil)
        print("PASS: two-stage inbox download, relative ADIF links, rejected external links, service errors and authentication failures")
    }
}
