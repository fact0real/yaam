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
    private var storageDirectoryOverride: URL?
    private var graphicRequestSpacing: TimeInterval = 11
    private var nextGraphicRequest = Date.distantPast
    private let urlSession: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20.0
        config.timeoutIntervalForResource = 45.0
        self.urlSession = URLSession(configuration: config)
        createStorageDirectoryIfNeeded()
    }

    init(session: URLSession, storageDirectory: URL, graphicRequestSpacing: TimeInterval = 11) {
        self.urlSession = session
        self.storageDirectoryOverride = storageDirectory
        self.graphicRequestSpacing = graphicRequestSpacing
        createStorageDirectoryIfNeeded()
    }

    // MARK: - Local Cache Directory

    public var cardsDirectoryURL: URL {
        if let storageDirectoryOverride { return storageDirectoryOverride }
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

    public func localCardFilename(callsign: String, date: String, band: String, mode: String, time: String? = nil) -> String {
        let cleanCall = callsign.uppercased().replacingOccurrences(of: "/", with: "-")
        let cleanDate = date.replacingOccurrences(of: "-", with: "")
        let cleanBand = band.uppercased()
        let cleanMode = mode.uppercased()
        let timestamp = time.map { "_" + $0.filter(\.isNumber) } ?? ""
        return "eQSL_\(cleanCall)_\(cleanDate)_\(cleanBand)_\(cleanMode)\(timestamp).jpg"
    }

    public func cachedCardURL(callsign: String, date: String, band: String, mode: String, time: String? = nil, username: String? = nil) -> URL? {
        let filename = localCardFilename(callsign: callsign, date: date, band: band, mode: mode, time: time)
        let root = username.map { cardsDirectoryURL.appendingPathComponent($0.uppercased().replacingOccurrences(of: "/", with: "-"), isDirectory: true) } ?? cardsDirectoryURL
        let fileURL = root.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    public func hasCachedCard(callsign: String, date: String, band: String, mode: String, time: String? = nil) -> Bool {
        return cachedCardURL(callsign: callsign, date: date, band: band, mode: mode, time: time) != nil
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

        FormURLEncoding.setQuery([
            URLQueryItem(name: "UserName", value: username),
            URLQueryItem(name: "Password", value: password),
            URLQueryItem(name: "RcvdSince", value: "20000101"),
            URLQueryItem(name: "XML", value: "0")
        ], on: &components)

        guard let url = components.url else { throw URLError(.badURL) }

        self.statusMessage = "Downloading eQSL Inbox..."
        let rawString = try await EQSLInboxDownload.download(session: urlSession, url: url)

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
        if let existing = cachedCardURL(callsign: callsign, date: date, band: band, mode: mode, time: time, username: username) {
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
        let minute = String(cleanTime.dropFirst(2).prefix(2))

        guard cleanDate.count == 8, cleanTime.count >= 4, !band.isEmpty, !mode.isEmpty else {
            throw EQSLInboxDownload.error("A complete QSO date, time, band and mode are required to retrieve an eQSL card.")
        }
        var components = URLComponents(string: "https://www.eqsl.cc/qslcard/GeteQSL.cfm")!
        FormURLEncoding.setQuery([
            URLQueryItem(name: "QSOMode", value: mode),
            URLQueryItem(name: "QSOBand", value: band),
            URLQueryItem(name: "UserName", value: username),
            URLQueryItem(name: "Password", value: password),
            URLQueryItem(name: "CallsignFrom", value: cleanCall),
            URLQueryItem(name: "QSOYear", value: year),
            URLQueryItem(name: "QSOMonth", value: month),
            URLQueryItem(name: "QSODay", value: day),
            URLQueryItem(name: "QSOHour", value: hour),
            URLQueryItem(name: "QSOMinute", value: minute)
        ], on: &components)

        guard let imageFetchURL = components.url else {
            throw URLError(.badURL)
        }

        let delay = nextGraphicRequest.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        nextGraphicRequest = Date().addingTimeInterval(graphicRequestSpacing)
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
            if let message = EQSLInboxDownload.failure(in: html) {
                throw EQSLInboxDownload.error(message)
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

        let stationDirectory = cardsDirectoryURL.appendingPathComponent(username.uppercased().replacingOccurrences(of: "/", with: "-"), isDirectory: true)
        try fileManager.createDirectory(at: stationDirectory, withIntermediateDirectories: true)
        let destURL = stationDirectory.appendingPathComponent(localCardFilename(callsign: callsign, date: date, band: band, mode: mode, time: time))
        try validData.write(to: destURL, options: .atomic)

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

        guard !isSyncing else { throw EQSLInboxDownload.error("An eQSL download is already running.") }
        guard let owner = appState.activeStationProfileID else {
            throw EQSLInboxDownload.error("Select a station profile before downloading cards.")
        }
        let candidateIDs = appState.qsoRecords.map(\.id)
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

        // Scope this collection to the operator's six-month review.
        let since = Calendar(identifier: .gregorian).date(byAdding: .month, value: -6, to: Date()) ?? Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyyMMdd"
        let receivedSince = dateFormatter.string(from: since)
        var components = URLComponents(string: "https://www.eqsl.cc/qslcard/DownloadInBox.cfm")!
        var queryItems = [
            URLQueryItem(name: "UserName", value: username),
            URLQueryItem(name: "Password", value: password),
            URLQueryItem(name: "RcvdSince", value: receivedSince),
            URLQueryItem(name: "XML", value: "0")
        ]
        if let nick = qthNickname, !nick.isEmpty {
            queryItems.append(URLQueryItem(name: "QTHNickname", value: nick))
        }
        FormURLEncoding.setQuery(queryItems, on: &components)

        guard let inboxURL = components.url else { throw URLError(.badURL) }

        let rawString = try await EQSLInboxDownload.download(session: urlSession, url: inboxURL)

        let downloadedRecords = parseADIF(content: rawString).records
        let notices = QSLInboxEngine.shared.receivedCards.filter { $0.stationProfileID == owner && $0.source == .eqsl && $0.mediaFileURL == nil && $0.status != .rejected }
        let parsed = notices.isEmpty ? downloadedRecords : downloadedRecords.filter { record in
            notices.contains { notice in
                notice.callsign.uppercased() == (record["CALL"] ?? "").uppercased() &&
                notice.qsoDate == (record["QSO_DATE"] ?? "") &&
                notice.band.uppercased() == (record["BAND"] ?? "").uppercased() &&
                notice.qsoTime.prefix(4) == (record["TIME_ON"] ?? "").prefix(4)
            }
        }
        if parsed.isEmpty {
            if !notices.isEmpty && !downloadedRecords.isEmpty {
                throw EQSLInboxDownload.error("The eQSL inbox has no records matching the pending email notices. Check the station account and QTH nickname.")
            }
            statusMessage = "No cards found in eQSL inbox."
            return 0
        }

        var downloadedCount = 0
        var failureCount = 0
        var firstFailure: String?
        let totalCount = parsed.count
        var claimed = Set<Int>()
        let candidates = appState.qsoRecords.map(\.fields)

        for (index, record) in parsed.enumerated() {
            guard appState.activeStationProfileID == owner else {
                throw EQSLInboxDownload.error("The station profile changed. Download stopped; existing cards were kept.")
            }
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
            let matched = appState.eqslConfirmationMatchIndex(record, candidates: candidates, claimed: &claimed)
            let localID = matched.flatMap { candidateIDs.indices.contains($0) ? candidateIDs[$0] : nil }
            let localIdx = localID.flatMap { id in appState.qsoRecords.firstIndex { $0.id == id } }
            if let localIdx {
                appState.qsoRecords[localIdx].fields["EQSL_QSL_RCVD"] = "Y"
                if let cached = cachedCardURL(callsign: call, date: date, band: band, mode: mode, time: time, username: username) {
                    appState.qsoRecords[localIdx].fields["QSL_MEDIA_PATH"] = cached.path
                }
            }

            // If already cached, continue
            if let cached = cachedCardURL(callsign: call, date: date, band: band, mode: mode, time: time, username: username) {
                let archivedURL = try await QSLInboxEngine.shared.receiveEQSLCard(record: record, from: cached, profileID: owner, matchedQSOID: localID)
                if appState.activeStationProfileID == owner, let localID,
                   let current = appState.qsoRecords.firstIndex(where: { $0.id == localID }) {
                    appState.qsoRecords[current].fields["QSL_MEDIA_PATH"] = archivedURL.path
                }
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

                guard appState.activeStationProfileID == owner else {
                    throw EQSLInboxDownload.error("The station profile changed during the download.")
                }
                if let localID, let current = appState.qsoRecords.firstIndex(where: { $0.id == localID }) {
                    appState.qsoRecords[current].fields["QSL_MEDIA_PATH"] = cardURL.path
                }
                let archivedURL = try await QSLInboxEngine.shared.receiveEQSLCard(record: record, from: cardURL, profileID: owner, matchedQSOID: localID)
                if appState.activeStationProfileID == owner, let localID,
                   let current = appState.qsoRecords.firstIndex(where: { $0.id == localID }) {
                    appState.qsoRecords[current].fields["QSL_MEDIA_PATH"] = archivedURL.path
                }
            } catch {
                failureCount += 1
                if firstFailure == nil { firstFailure = error.localizedDescription }
                lastError = "\(failureCount) card(s) failed. \(firstFailure ?? "")"
                if downloadedCount == 0 && failureCount >= 3 {
                    throw EQSLInboxDownload.error(lastError ?? "eQSL card download failed.")
                }
                continue
            }
        }

        if appState.activeStationProfileID == owner { appState.autoSaveActiveWorkspace() }
        statusMessage = "eQSL: \(downloadedCount) new card(s) saved, \(failureCount) failed."
        return downloadedCount
    }
}
