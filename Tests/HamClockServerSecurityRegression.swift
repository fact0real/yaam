// Tests/HamClockServerSecurityRegression.swift
// Tests for HamClockRemoteWebServer security hardening and connection cleanup.

import AppKit
import Foundation
import Network
import YAAM

@main
struct HamClockServerSecurityRegression {
    static func wait(seconds: Double = 3.0, condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && deadline.timeIntervalSinceNow > 0 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    static func sendHTTP(port: UInt16, request: String) -> (status: String, headers: [String: String], body: String)? {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let queue = DispatchQueue(label: "hamclock-test-client")
        var responseData = Data()
        var completed = false

        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
            }
        }

        func readLoop() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    responseData.append(data)
                }
                if isComplete || error != nil {
                    completed = true
                    connection.cancel()
                } else {
                    readLoop()
                }
            }
        }

        connection.start(queue: queue)
        readLoop()

        _ = wait(seconds: 4.0) { completed }
        connection.cancel()

        guard let responseString = String(data: responseData, encoding: .utf8) else { return nil }
        let lines = responseString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { return nil }

        var headers: [String: String] = [:]
        var bodyIndex = lines.count
        for (i, line) in lines.enumerated().dropFirst() {
            if line.isEmpty {
                bodyIndex = i + 1
                break
            }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        let body = lines[bodyIndex...].joined(separator: "\r\n")
        return (statusLine, headers, body)
    }

    @MainActor
    static func main() {
        print("[*] Starting HamClockServerSecurityRegression...")
        let server = HamClockRemoteWebServer.shared
        server.port = 18089
        server.start()

        guard wait(condition: { server.isRunning }) else {
            fatalError("[-] Server failed to start on port 18089")
        }
        print("[+] HamClockRemoteWebServer running on port \(server.port)")
        let token = server.authToken
        assert(!token.isEmpty, "Auth token must not be empty")

        // Test 1: Unauthenticated request to /api/rotator must be rejected with 401
        let unauthReq = "POST /api/rotator HTTP/1.1\r\nHost: 127.0.0.1:18089\r\nContent-Type: application/json\r\nContent-Length: 17\r\n\r\n{\"azimuth\": 180}"
        guard let unauthRes = sendHTTP(port: server.port, request: unauthReq) else {
            fatalError("[-] No response for unauthenticated request")
        }
        assert(unauthRes.status.contains("401"), "Expected 401 Unauthorized but got: \(unauthRes.status)")
        assert(unauthRes.headers["access-control-allow-origin"] == nil, "CORS wildcard must not be present")
        print("[+] Test 1 Passed: Unauthenticated POST /api/rotator rejected with 401 and no wildcard CORS.")

        // Test 2: Authenticated request with query parameter token
        let authReq = "POST /api/rotator?token=\(token) HTTP/1.1\r\nHost: 127.0.0.1:18089\r\nContent-Type: application/json\r\nContent-Length: 17\r\n\r\n{\"azimuth\": 225}"
        guard let authRes = sendHTTP(port: server.port, request: authReq) else {
            fatalError("[-] No response for authenticated request")
        }
        assert(authRes.status.contains("200"), "Expected 200 OK but got: \(authRes.status)")
        assert(authRes.body.contains("\"azimuth\":225"), "Expected azimuth 225 confirmation")
        assert(authRes.headers["access-control-allow-origin"] == nil, "CORS wildcard must not be present on response")
        print("[+] Test 2 Passed: Authenticated POST /api/rotator succeeded with 200 OK.")

        // Test 3: Authenticated telemetry request
        let telReq = "GET /api/telemetry?token=\(token) HTTP/1.1\r\nHost: 127.0.0.1:18089\r\n\r\n"
        guard let telRes = sendHTTP(port: server.port, request: telReq) else {
            fatalError("[-] No response for telemetry request")
        }
        assert(telRes.status.contains("200"), "Expected 200 OK for telemetry")
        print("[+] Test 3 Passed: Authenticated GET /api/telemetry succeeded.")

        // Test 4: Verify connection cleanup on client disconnect
        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: server.port)!, using: .tcp)
        conn.start(queue: DispatchQueue(label: "disconnect-test"))
        _ = wait(condition: { server.connectedClientsCount > 0 })
        conn.cancel()
        guard wait(condition: { server.connectedClientsCount == 0 }) else {
            fatalError("[-] Disconnected client was not cleaned up from activeConnections!")
        }
        print("[+] Test 4 Passed: Disconnected socket successfully removed from active connections.")

        server.stop()
        _ = wait(condition: { !server.isRunning })
        print("[+] All HamClockServerSecurityRegression tests passed successfully!")
    }
}
