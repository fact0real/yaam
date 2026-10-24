// swiftc -D MESSAGING_REGRESSION -parse-as-library Tests/SKEDMessagingRegression.swift
// YAAM/SKEDMessagingService.swift YAAM/SKEDMessagingModel.swift -o /tmp/sked-messaging && /tmp/sked-messaging
import Foundation

final class MessagingStubProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (URLRequest) throws -> (Int, Data) = { _ in (503, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

@main struct SKEDMessagingRegression {
    static let token = "qrz_" + String(repeating: "a", count: 48)
    static let status = SKEDMessagingStatus(available: true, verifiedCallsign: "EP2AES", enabled: true, retentionDays: 30)
    static func data(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    @MainActor static func main() async throws {
        let draft = try SKEDMessageDraft(recipient: " g0jhc ", body: "سلام، 20m at 14:00 UTC?")
        let bytes = try JSONEncoder().encode(draft)
        let request = try SKEDMessagingContract.request(action: "messages", method: "POST", token: token, body: bytes, userAgent: "YAAM-test")
        precondition(request.url?.absoluteString == "https://qrz-rank.asis.sh/api/v1/messaging/messages")
        precondition(request.url?.query == nil && request.value(forHTTPHeaderField: "Authorization") == "Bearer " + token)
        precondition(request.httpShouldHandleCookies == false && request.cachePolicy == .reloadIgnoringLocalCacheData)
        let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        precondition(Set(object.keys) == ["recipient", "body", "client_id"])
        precondition(object["recipient"] as? String == "G0JHC")
        for call in ["G0JHC/", "/EP2AES", "../x", "ABC", "123", "EP2AES\n"] {
            precondition(!SKEDMessagingContract.validCallsign(call))
        }
        for text in ["", "  ", String(repeating: "x", count: 2001), "ab\u{202e}cd", "a\0b"] {
            precondition(!SKEDMessagingContract.validBody(text))
        }
        for bad in ["", "qrz_short", token + "\r\nInjected: true"] {
            do { _ = try SKEDMessagingContract.request(action: "status", token: bad, userAgent: "test"); fatalError("bad token accepted") }
            catch SKEDMessagingError.missingToken { }
        }
        for path in ["../quota", "https://evil.invalid", "blocks/EP2AES?token=abc"] {
            do { _ = try SKEDMessagingContract.request(action: path, token: token, userAgent: "test"); fatalError("bad path accepted") }
            catch SKEDMessagingError.invalidInput { }
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MessagingStubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = SKEDMessagingService(userAgent: "test", session: session)
        var recordedIDs: [String] = []
        var attempts = 0
        // Network loses the first acknowledgement after the server accepted it.
        // The retry must carry exactly the same UUID and payload.
        MessagingStubProtocol.handler = { req in
            switch req.url!.lastPathComponent {
            case "status": return (200, try JSONEncoder().encode(status))
            case "blocks": return (200, data(["callsigns": []]))
            case "messages" where req.httpMethod == "POST":
                var body = req.httpBody ?? Data()
                if body.isEmpty, let stream = req.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        body.append(contentsOf: buffer.prefix(count))
                    }
                }
                let payload = try JSONDecoder().decode(SKEDMessageDraft.self, from: body)
                recordedIDs.append(payload.clientID)
                attempts += 1
                if attempts == 1 { throw URLError(.networkConnectionLost) }
                let message = SKEDPrivateMessage(id: "42", clientID: payload.clientID, sender: "EP2AES", recipient: payload.recipient,
                    body: payload.body, createdAt: "2026-10-24T10:00:00.000000Z")
                return (200, data(["message": try JSONSerialization.jsonObject(with: JSONEncoder().encode(message))]))
            default: return (200, data(["messages": [], "next_before": NSNull()]))
            }
        }
        var activeToken = token
        let model = SKEDMessagingModel(service: service, tokenProvider: { activeToken })
        await model.refresh()
        precondition(model.enabled && model.owner == "EP2AES")
        model.text = "SKED 20m 14 UTC?"
        await model.send()
        precondition(model.pending != nil && model.error != nil && model.messages.isEmpty)
        let pending = model.pending!
        await model.send()
        precondition(recordedIDs == [pending.clientID, pending.clientID])
        precondition(model.pending == nil && model.text.isEmpty && model.messages.count == 1)

        // The server must never be able to splice another account's inbox into this UI.
        let foreign = SKEDPrivateMessage(id: "3", clientID: UUID().uuidString, sender: "EA3JIC", recipient: "K1ABC", body: "foreign",
                                         createdAt: "2026-10-24T10:00:00.000000Z")
        MessagingStubProtocol.handler = { _ in (200, try JSONEncoder().encode(SKEDMessagePage(messages: [foreign], nextBefore: nil))) }
        do { _ = try await service.messages(token: token, owner: "EP2AES"); fatalError("foreign inbox accepted") }
        catch SKEDMessagingError.invalidResponse { }
        MessagingStubProtocol.handler = { _ in (200, Data(repeating: 32, count: SKEDMessagingContract.maxResponseBytes + 1)) }
        do { _ = try await service.status(token: token); fatalError("oversized body accepted") }
        catch SKEDMessagingError.invalidResponse { }
        MessagingStubProtocol.handler = { _ in (429, data(["error": ["message": "SECRET"]])) }
        do { _ = try await service.status(token: token); fatalError("rate limit accepted") }
        catch SKEDMessagingError.rateLimited { }
        MessagingStubProtocol.handler = { _ in (401, Data()) }
        await model.refresh()
        precondition(model.messages.isEmpty && model.status == nil)

        MessagingStubProtocol.handler = { req in
            if req.url!.lastPathComponent == "status" { return (200, try JSONEncoder().encode(status)) }
            if req.url!.lastPathComponent == "blocks" { return (200, data(["callsigns": []])) }
            return (200, try JSONEncoder().encode(SKEDMessagePage(messages: [], nextBefore: nil)))
        }
        await model.refresh()
        precondition(model.enabled)
        activeToken = "qrz_" + String(repeating: "b", count: 48)
        model.text = "must not send as the replacement account"
        var sendCount = 0
        MessagingStubProtocol.handler = { _ in sendCount += 1; return (503, Data()) }
        await model.send()
        precondition(sendCount == 0 && model.status == nil && model.text.isEmpty)
        model.close()
        precondition(model.messages.isEmpty && model.pending == nil && !model.working)
        print("PASS: messaging contract, hostile input, bounded responses, account isolation, token change, safe retry, redacted errors and memory cleanup")
    }
}
