// swiftc -parse-as-library Tests/CloudUploadBoundaryRegression.swift YAAM/UploadFileReader.swift -o /tmp/yaam-cloud-boundary && /tmp/yaam-cloud-boundary
import Foundation
@main struct CloudUploadBoundaryRegression {
    static func main() throws {
        precondition(CloudUploadNotice.outcome(accepted: 1, waiting: 0, rejected: 0) == .accepted)
        precondition(CloudUploadNotice.outcome(accepted: 0, waiting: 1, rejected: 0) == .waiting)
        precondition(CloudUploadNotice.outcome(accepted: 1, waiting: 1, rejected: 1) == .needsAttention)
        precondition(CloudUploadNotice.outcome(accepted: 0, waiting: 0, rejected: 0) != .accepted)
        precondition(CloudServiceResult.network(URLError(.notConnectedToInternet)).retryable)
        precondition(!CloudServiceResult.network(URLError(.timedOut)).retryable, "An uncertain submission needs review")
        precondition(!CloudServiceResult.network(NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "network upload failed"])).retryable, "Message wording cannot determine retry semantics")
        let responseURL = URL(string: "https://example.test")!
        precondition(CloudServiceResult.http(HTTPURLResponse(url: responseURL, statusCode: 429, httpVersion: nil, headerFields: nil)!).retryable)
        precondition(!CloudServiceResult.http(HTTPURLResponse(url: responseURL, statusCode: 401, httpVersion: nil, headerFields: nil)!).retryable)
        precondition(!CloudServiceResult.http(HTTPURLResponse(url: responseURL, statusCode: 500, httpVersion: nil, headerFields: nil)!).retryable)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("تماس آزمایشی & log.adi")
        let content = Data("<CALL:4>W1AW<EOR>".utf8); try content.write(to: file)
        let read = try UploadFileReader.read(file); precondition(read == content)
        precondition((try? Data(contentsOf: file)) == content)
        let placeholder = dir.appendingPathComponent(".log.adi.icloud"); try Data().write(to: placeholder)
        do { _ = try UploadFileReader.read(placeholder); preconditionFailure("A placeholder is not an empty accepted upload") } catch UploadFileReader.Failure.downloadRequired {}
        let missing = dir.appendingPathComponent("missing.adi")
        do { _ = try UploadFileReader.read(missing); preconditionFailure("Missing input cannot succeed") } catch {}
        print("PASS upload boundaries: typed partial/failure states, Unicode/spaced file paths, placeholder rejection and original preservation")
    }
}
