import Foundation

// Standalone, no network and no access to the real Library:
//   swiftc -parse-as-library Tests/LoTWActivityDatabaseRegression.swift YAAM/LoTWActivityDatabase.swift -o /tmp/lotw && /tmp/lotw
// The home directory is pointed at a temporary folder, so the cache file lives in
// <temp>/Library/Application Support/YAAM, and every URL request is answered by a stub.

final class LoTWStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var requests = 0
    nonisolated(unsafe) static var plainResponse = false   // answer with a URLResponse that is not an HTTPURLResponse

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        let response: URLResponse = Self.plainResponse
            ? URLResponse(url: request.url!, mimeType: "text/plain", expectedContentLength: Self.body.count, textEncodingName: nil)
            : HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
struct LoTWActivityDatabaseRegression {
    @MainActor
    static func main() async {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print("\(ok ? "ok  " : "FAIL") \(name)")
            if !ok { failures += 1 }
        }

        // Keep the cache file out of the real Application Support folder.
        let home = NSTemporaryDirectory() + "lotw-regression-\(getpid())"
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        setenv("CFFIXED_USER_HOME", home, 1)
        setenv("HOME", home, 1)
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              appSupport.path.hasPrefix(home) else {
            print("Cannot redirect Application Support to the temporary folder; not running, to leave the real Library alone.")
            exit(2)
        }
        let yaamDir = appSupport.appendingPathComponent("YAAM", isDirectory: true)
        let cacheURL = yaamDir.appendingPathComponent("lotw-user-activity.csv")
        try? FileManager.default.createDirectory(at: yaamDir, withIntermediateDirectories: true)

        URLProtocol.registerClass(LoTWStubURLProtocol.self)

        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let seedCSV = Data("K1ABC,\(today),12:00:00\n".utf8)
        let goodCSV = Data("""
            Callsign,LastUpload,Time
            K1ABC1,\(today),10:00:00
            W1XYZ,\(today),11:00:00
            3B8ZZ,2023-01-10,08:00:00

            """.utf8)
        let newerCSV = Data("VK2ABC,\(today),09:00:00\nK1ABC,\(today),09:30:00\n".utf8)
        let maintenancePage = Data("<html><head><title>LoTW</title></head><body><h1>Down for maintenance, back soon</h1></body></html>".utf8)

        func cacheBytes() -> Data? { try? Data(contentsOf: cacheURL) }
        func settle() async { try? await Task.sleep(nanoseconds: 200_000_000) }
        func waitUntil(_ condition: () -> Bool) async -> Bool {
            for _ in 0..<100 {
                if condition() { return true }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return condition()
        }
        func update(_ db: LoTWActivityDatabase, status: Int, body: Data) async -> (count: Int?, threw: Bool) {
            LoTWStubURLProtocol.status = status
            LoTWStubURLProtocol.body = body
            do {
                let count = try await db.updateFromWeb()
                await settle()
                return (count, false)
            } catch {
                await settle()
                return (nil, true)
            }
        }

        // An earlier download is in the cache file when the app starts.
        try? seedCSV.write(to: cacheURL, options: .atomic)
        let db = LoTWActivityDatabase()
        check(await waitUntil { db.isUserActive("K1ABC") }, "starts from the cached file")

        // A good download replaces the map and the cache file.
        let first = await update(db, status: 200, body: goodCSV)
        check(!first.threw && first.count == 3, "good CSV: 3 rows installed (got \(first.count.map(String.init) ?? "error"))")
        check(db.isUserActive("K1ABC1") && db.isUserActive("W1XYZ"), "good CSV: K1ABC1 and W1XYZ are active")
        check(db.lastUploadDate(for: "3B8ZZ") != nil && !db.isUserActive("3B8ZZ"), "good CSV: 3B8ZZ is listed but inactive")
        check(db.lastUploadDate(for: "K1ABC") == nil, "good CSV: the previous map was replaced")
        check(cacheBytes() == goodCSV, "good CSV: cache file holds the download")
        check(db.userCount == 3 && db.lastErrorMessage == nil && db.lastDatabaseUpdate != nil, "good CSV: count 3, no error, update time set")

        // Replies that are not the CSV must change nothing.
        let badReplies: [(String, Int, Data, String)] = [
            ("HTML page with HTTP 200", 200, maintenancePage, "not the LoTW activity list"),
            ("empty body with HTTP 200", 200, Data(), "not the LoTW activity list"),
            ("HTML page with HTTP 503", 503, maintenancePage, "HTTP 503"),
            // Valid rows, but the status is not 2xx: only the status check can refuse this one.
            ("valid CSV with HTTP 301", 301, newerCSV, "HTTP 301"),
        ]
        for (name, status, body, messagePart) in badReplies {
            let restore = await update(db, status: 200, body: goodCSV)
            check(!restore.threw && restore.count == 3, "\(name): starting from the good CSV")

            let bad = await update(db, status: status, body: body)
            check(bad.threw, "\(name): update throws" + (bad.threw ? "" : " (it returned \(bad.count ?? -1) rows)"))
            check(db.lastErrorMessage != nil, "\(name): lastErrorMessage is set")
            check(db.lastErrorMessage?.contains(messagePart) == true, "\(name): lastErrorMessage mentions \"\(messagePart)\" (got \(db.lastErrorMessage ?? "nil"))")
            check(db.isUserActive("K1ABC1") && db.isUserActive("W1XYZ"), "\(name): active users are still known")
            check(db.userCount == 3, "\(name): userCount still 3 (got \(db.userCount))")
            check(cacheBytes() == goodCSV, "\(name): cache file is unchanged")

            // Next launch reads the cache file again.
            let restarted = LoTWActivityDatabase()
            check(await waitUntil { restarted.isLoaded }, "\(name): restarted instance finished loading")
            check(restarted.isUserActive("W1XYZ") && restarted.userCount == 3, "\(name): restarted instance still knows 3 users (got \(restarted.userCount))")
        }

        // A reply that is not an HTTP response at all is refused too, and the message says so.
        LoTWStubURLProtocol.plainResponse = true
        let plain = await update(db, status: 200, body: newerCSV)
        LoTWStubURLProtocol.plainResponse = false
        check(plain.threw, "non-HTTP reply: update throws")
        check(db.lastErrorMessage?.contains("no HTTP response") == true, "non-HTTP reply: lastErrorMessage says no HTTP response (got \(db.lastErrorMessage ?? "nil"))")
        check(db.userCount == 3 && cacheBytes() == goodCSV, "non-HTTP reply: count still 3 and cache file unchanged (got \(db.userCount))")

        // A good download works again afterwards and clears the error.
        let last = await update(db, status: 200, body: newerCSV)
        check(!last.threw && last.count == 2, "good CSV again: 2 rows installed (got \(last.count.map(String.init) ?? "error"))")
        check(db.isUserActive("VK2ABC") && db.isUserActive("K1ABC") && db.lastUploadDate(for: "W1XYZ") == nil, "good CSV again: map replaced")
        check(cacheBytes() == newerCSV, "good CSV again: cache file holds the download")
        check(db.userCount == 2 && db.lastErrorMessage == nil, "good CSV again: count 2, error cleared")

        // A short but valid-looking response must not erase a full local list.
        let fullCSV = Data((0..<10_000).map { "K\($0),\(today),12:00:00\n" }.joined().utf8)
        try? fullCSV.write(to: cacheURL, options: .atomic)
        check(db.parseCSVData(fullCSV) == 10_000, "full CSV: 10,000 users installed")
        let truncated = await update(db, status: 200, body: newerCSV)
        check(truncated.threw && db.lastErrorMessage?.contains("incomplete") == true,
              "truncated valid CSV: update refused")
        check(db.userCount == 10_000 && cacheBytes() == fullCSV,
              "truncated valid CSV: full list and cache preserved")

        let expectedRequests = 4 + 2 * badReplies.count   // first good, (restore + bad) per case, non-HTTP reply, last good, truncated
        check(LoTWStubURLProtocol.requests == expectedRequests, "all \(expectedRequests) requests were answered by the stub (got \(LoTWStubURLProtocol.requests))")

        try? FileManager.default.removeItem(atPath: home)
        if failures == 0 {
            print("LoTW activity database regression tests passed.")
        } else {
            print("\(failures) check(s) failed.")
            exit(1)
        }
    }
}
