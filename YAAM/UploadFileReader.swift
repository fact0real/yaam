import Foundation

nonisolated enum UploadFileReader {
    enum Failure: LocalizedError {
        case downloadRequired
        var errorDescription: String? { "This iCloud file is not downloaded yet. Download it in Finder, then retry the upload. The original file has not been changed." }
    }
    static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if url.lastPathComponent.hasSuffix(".icloud") { throw Failure.downloadRequired }
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw Failure.downloadRequired
        }
        var result: Result<Data, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { resolved in
            result = Result { try Data(contentsOf: resolved) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
nonisolated enum CloudUploadNotice: Equatable, Sendable {
    case accepted, waiting, needsAttention
    static func outcome(accepted: Int, waiting: Int, rejected: Int) -> Self {
        if rejected > 0 { return .needsAttention }
        if waiting > 0 || accepted == 0 { return .waiting }
        return .accepted
    }
    var symbol: String {
        switch self { case .accepted: return "checkmark.icloud.fill"; case .waiting: return "tray.and.arrow.down.fill"; case .needsAttention: return "exclamationmark.icloud.fill" }
    }
}

nonisolated struct CloudServiceResult {
    let success: Bool
    let message: String
    var retryable = false
    static func http(_ response: URLResponse) -> Self {
        let code = (response as? HTTPURLResponse)?.statusCode
        return Self(success: false, message: code.map { "Service returned HTTP \($0)" } ?? "Invalid service response", retryable: code == 429)
    }
    static func network(_ error: Error) -> Self {
        let code = (error as? URLError)?.code
        let safeToRetry: Set<URLError.Code> = [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed]
        return Self(success: false, message: error.localizedDescription, retryable: code.map { safeToRetry.contains($0) } ?? false)
    }
}
