//
//  EQSLService.swift
//  YAAM
//
//  eQSL.cc Authentication, Inbox Synchronization, and Graphic QSL Card Image Downloader.
//  Downloads electronic QSL confirmation status and high-resolution QSL cards (.jpg/.png),
//  caching them locally in the application support directory.
//

import AppKit
import Combine
import Foundation

public struct EQSLCardInfo: Identifiable, Sendable {
    public let id: String
    public let callsign: String
    public let band: String
    public let mode: String
    public let qsoDate: String
    public let qsoTime: String
    public let imageURL: URL?
    public let localFileURL: URL?

    public init(
        id: String,
        callsign: String,
        band: String,
        mode: String,
        qsoDate: String,
        qsoTime: String,
        imageURL: URL? = nil,
        localFileURL: URL? = nil
    ) {
        self.id = id
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.qsoDate = qsoDate
        self.qsoTime = qsoTime
        self.imageURL = imageURL
        self.localFileURL = localFileURL
    }
}

public struct EQSLDownloadProgress: Sendable {
    public let current: Int
    public let total: Int
    public let currentCallsign: String

    public var percentage: Double {
        total > 0 ? Double(current) / Double(total) : 0
    }
}

public struct CachedEQSLCard: Identifiable, Sendable {
    public var id: String { fileURL.path }
    public let fileURL: URL
    public let callsign: String
    public let date: String
    public let band: String
    public let mode: String
}

@MainActor
public final class EQSLService: ObservableObject {
    public static let shared = EQSLService()

    @Published public var isSyncing: Bool = false
    @Published public var downloadProgress: EQSLDownloadProgress? = nil
    @Published public var lastSyncDate: Date? = nil
    @Published public var statusMessage: String = "Ready"
    @Published public var downloadedCardCount: Int = 0
    @Published public var lastError: String? = nil

    private var isCancelled: Bool = false
    private let fileManager = FileManager.default
    private let urlSession: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20.0
        config.timeoutIntervalForResource = 45.0
        self.urlSession = URLSession(configuration: config)
        createStorageDirectoryIfNeeded()
    }

    // MARK: - Local Cache Directory

    public var cardsDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yaamDir = appSupport.appendingPathComponent("YAAM", isDirectory: true)
        return yaamDir.appendingPathComponent("eQSL_Cards", isDirectory: true)
    }

    private func createStorageDirectoryIfNeeded() {
        let dir = cardsDirectoryURL
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func localCardFilename(callsign: String, date: String, band: String, mode: String) -> String {
        let cleanCall = callsign.uppercased().replacingOccurrences(of: "/", with: "-")
        let cleanDate = date.replacingOccurrences(of: "-", with: "")
        let cleanBand = band.uppercased()
        let cleanMode = mode.uppercased()
        return "eQSL_\(cleanCall)_\(cleanDate)_\(cleanBand)_\(cleanMode).jpg"
    }

    public func cachedCardURL(callsign: String, date: String, band: String, mode: String) -> URL? {
        let filename = localCardFilename(callsign: callsign, date: date, band: band, mode: mode)
        let fileURL = cardsDirectoryURL.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    public func hasCachedCard(callsign: String, date: String, band: String, mode: String) -> Bool {
        return cachedCardURL(callsign: callsign, date: date, band: band, mode: mode) != nil
    }

    public func allCachedCards() -> [CachedEQSLCard] {
        createStorageDirectoryIfNeeded()
        guard let files = try? fileManager.contentsOfDirectory(at: cardsDirectoryURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var results: [CachedEQSLCard] = []
        for file in files where file.pathExtension.lowercased() == "jpg" || file.pathExtension.lowercased() == "png" {
            let filename = file.deletingPathExtension().lastPathComponent
            let parts = filename.components(separatedBy: "_")
            if parts.count >= 5 && parts[0] == "eQSL" {
                let call = parts[1]
                let date = parts[2]
                let band = parts[3]
                let mode = parts[4]
                results.append(CachedEQSLCard(fileURL: file, callsign: call, date: date, band: band, mode: mode))
            } else {
                results.append(CachedEQSLCard(fileURL: file, callsign: filename, date: "", band: "", mode: ""))
            }
        }
        return results
    }

    // MARK: - Cancellation

    public func cancelDownload() {
        isCancelled = true
        statusMessage = "Cancelling download..."
    }

    // MARK: - Sync Inbox

    public func syncInbox(username: String, password: String) async throws -> [String] {
        guard !username.isEmpty, !password.isEmpty else {
            throw NSError(domain: "EQSLService", code: 400, userInfo: [NSLocalizedDescriptionKey: "eQSL username or password is missing"])
        }

        self.isSyncing = true
        self.statusMessage = "Connecting to eQSL.cc..."
        self.lastError = nil

        defer {
            self.isSyncing = false
            self.lastSyncDate = Date()
        }

        // eQSL.cc DownloadInBox endpoint
        let endpoint = "https://www.eqsl.cc/qslcard/DownloadInBox.cfm"
        guard var components = URLComponents(string: endpoint) else {
            throw URLError(.badURL)
        }

        components.queryItems = [
            URLQueryItem(name: "UserName", value: username),
            URLQueryItem(name: "Password", value: password),
            URLQueryItem(name: "RcvdSince", value: "20000101"),
            URLQueryItem(name: "XML", value: "0")
        ]

        guard let url = components.url else { throw URLError(.badURL) }

        self.statusMessage = "Downloading eQSL Inbox..."
        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let rawString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "EQSLService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decode eQSL response"])
        }

        if rawString.contains("Error:") || rawString.contains("Login Failed") {
            throw NSError(domain: "EQSLService", code: 401, userInfo: [NSLocalizedDescriptionKey: "eQSL Authentication Failed: Invalid credentials"])
        }

        self.statusMessage = "eQSL Sync Complete."
        return [rawString]
    }

    // MARK: - Download Graphic QSL Card Image

    public func downloadCardImage(
        callsign: String,
        date: String,
        time: String,
        band: String,
        mode: String,
        username: String,
        password: String
    ) async throws -> URL {
        if let existing = cachedCardURL(callsign: callsign, date: date, band: band, mode: mode) {
            return existing
        }

        createStorageDirectoryIfNeeded()

        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanDate = date.replacingOccurrences(of: "-", with: "")
        let cleanTime = time.replacingOccurrences(of: ":", with: "")

        let year = String(cleanDate.prefix(4))
        let month = String(cleanDate.dropFirst(4).prefix(2))
        let day = String(cleanDate.suffix(2))
        let hour = String(cleanTime.prefix(2))
        let minute = String(cleanTime.suffix(2))

        var components = URLComponents(string: "https://www.eqsl.cc/qslcard/GeteQSL.cfm")!
        components.queryItems = [
            URLQueryItem(name: "SubMode", value: mode),
            URLQueryItem(name: "UserName", value: username),
            URLQueryItem(name: "Password", value: password),
            URLQueryItem(name: "CallsignFrom", value: cleanCall),
            URLQueryItem(name: "QSOYear", value: year),
            URLQueryItem(name: "QSOMonth", value: month),
            URLQueryItem(name: "QSODay", value: day),
            URLQueryItem(name: "QSOHour", value: hour),
            URLQueryItem(name: "QSOMinute", value: minute)
        ]

        guard let imageFetchURL = components.url else {
            throw URLError(.badURL)
        }

        let (initialData, response) = try await urlSession.data(from: imageFetchURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        var finalImageData: Data? = nil

        // Check if initialData is already an image (JPEG starts with FF D8 FF, PNG starts with 89 50 4E 47)
        if initialData.count > 4 &&
           (initialData.starts(with: [0xFF, 0xD8, 0xFF]) || initialData.starts(with: [0x89, 0x50, 0x4E, 0x47])) {
            finalImageData = initialData
        } else if let html = String(data: initialData, encoding: .utf8) ?? String(data: initialData, encoding: .isoLatin1) {
            if html.contains("Error:") || html.contains("No match") || html.contains("Login Failed") {
                throw NSError(domain: "EQSLService", code: 404, userInfo: [NSLocalizedDescriptionKey: "No graphical eQSL card found for this QSO"])
            }

            // Extract <img src="..."> using regex
            let pattern = #"(?i)<img[^>]+src=["']?([^"'>\s]+)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let srcRange = Range(match.range(at: 1), in: html) {
                let rawSrc = String(html[srcRange])
                let fullURLString: String
                if rawSrc.lowercased().hasPrefix("http://") || rawSrc.lowercased().hasPrefix("https://") {
                    fullURLString = rawSrc
                } else if rawSrc.hasPrefix("/") {
                    fullURLString = "https://www.eqsl.cc" + rawSrc
                } else {
                    fullURLString = "https://www.eqsl.cc/qslcard/" + rawSrc
                }

                if let realImageURL = URL(string: fullURLString) {
                    let (imgData, imgResponse) = try await urlSession.data(from: realImageURL)
                    if let imgHttp = imgResponse as? HTTPURLResponse, (200...299).contains(imgHttp.statusCode), imgData.count > 500 {
                        finalImageData = imgData
                    }
                }
            }
        }

        guard let validData = finalImageData, NSImage(data: validData) != nil else {
            throw NSError(domain: "EQSLService", code: 404, userInfo: [NSLocalizedDescriptionKey: "No graphical eQSL card found for this QSO"])
        }

        let destURL = cardsDirectoryURL.appendingPathComponent(localCardFilename(callsign: callsign, date: date, band: band, mode: mode))
        try validData.write(to: destURL)

        self.downloadedCardCount += 1
        return destURL
    }

    // MARK: - Download All Graphic QSL Cards From Inbox

    func downloadAllCards(
        username: String,
        password: String,
        qthNickname: String? = nil,
        appState: AppState
    ) async throws -> Int {
        guard !username.isEmpty, !password.isEmpty else {
            throw NSError(domain: "EQSLService", code: 400, userInfo: [NSLocalizedDescriptionKey: "eQSL username or password is missing. Please check Settings."])
        }

        isCancelled = false
        isSyncing = true
        downloadProgress = nil
        statusMessage = "Fetching eQSL.cc Inbox..."
        lastError = nil

        defer {
            isSyncing = false
            downloadProgress = nil
            lastSyncDate = Date()
        }

        // 1. Download full inbox ADIF using RcvdSince=20000101
        var components = URLComponents(string: "https://www.eqsl.cc/qslcard/DownloadInBox.cfm")!
        var queryItems = [
            URLQueryItem(name: "UserName", value: username),
            URLQueryItem(name: "Password", value: password),
            URLQueryItem(name: "RcvdSince", value: "20000101"),
            URLQueryItem(name: "XML", value: "0")
        ]
        if let nick = qthNickname, !nick.isEmpty {
            queryItems.append(URLQueryItem(name: "QTHNickname", value: nick))
        }
        components.queryItems = queryItems

        guard let inboxURL = components.url else { throw URLError(.badURL) }

        let (inboxData, inboxResponse) = try await urlSession.data(from: inboxURL)
        guard let httpResponse = inboxResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let rawString = String(data: inboxData, encoding: .utf8) ?? String(data: inboxData, encoding: .isoLatin1) else {
            throw NSError(domain: "EQSLService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to read eQSL response."])
        }

        if rawString.contains("Error: Bad password") || rawString.contains("Login Failed") || rawString.contains("Error: No such user") {
            throw NSError(domain: "EQSLService", code: 401, userInfo: [NSLocalizedDescriptionKey: "eQSL Authentication Failed: Invalid Username or Password."])
        }

        let parsed = parseADIF(content: rawString).records
        if parsed.isEmpty {
            statusMessage = "No cards found in eQSL inbox."
            return 0
        }

        var downloadedCount = 0
        let totalCount = parsed.count

        for (index, record) in parsed.enumerated() {
            if isCancelled {
                statusMessage = "Download stopped by user."
                break
            }

            let call = (record["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let date = (record["QSO_DATE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let time = (record["TIME_ON"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let band = (record["BAND"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let mode = (record["MODE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            guard !call.isEmpty, !date.isEmpty else { continue }

            downloadProgress = EQSLDownloadProgress(current: index + 1, total: totalCount, currentCallsign: call)
            statusMessage = "Card \(index + 1) of \(totalCount): \(call)..."

            // Link in local log
            if let localIdx = appState.qslConfirmationMatchIndex(record) {
                appState.qsoRecords[localIdx].fields["EQSL_QSL_RCVD"] = "Y"
                if let cached = cachedCardURL(callsign: call, date: date, band: band, mode: mode) {
                    appState.qsoRecords[localIdx].fields["QSL_MEDIA_PATH"] = cached.path
                }
            }

            // If already cached, continue
            if hasCachedCard(callsign: call, date: date, band: band, mode: mode) {
                continue
            }

            do {
                let cardURL = try await downloadCardImage(
                    callsign: call,
                    date: date,
                    time: time,
                    band: band,
                    mode: mode,
                    username: username,
                    password: password
                )
                downloadedCount += 1

                if let localIdx = appState.qslConfirmationMatchIndex(record) {
                    appState.qsoRecords[localIdx].fields["QSL_MEDIA_PATH"] = cardURL.path
                }

                // Rate limiting pause: 400ms buffer
                try? await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                // Continue to next card if this one failed
                continue
            }
        }

        appState.autoSaveActiveWorkspace()
        statusMessage = "eQSL download finished: \(downloadedCount) new card(s) saved."
        return downloadedCount
    }
}
