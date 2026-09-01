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

@MainActor
public final class EQSLService: ObservableObject {
    public static let shared = EQSLService()

    @Published public var isSyncing: Bool = false
    @Published public var lastSyncDate: Date? = nil
    @Published public var statusMessage: String = "Ready"
    @Published public var downloadedCardCount: Int = 0
    @Published public var lastError: String? = nil

    private let fileManager = FileManager.default
    private let urlSession: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
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

        // eQSL Get Graphic Card Image endpoint
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanDate = date.replacingOccurrences(of: "-", with: "")
        let cleanTime = time.replacingOccurrences(of: ":", with: "")

        let cardURLString = "https://www.eqsl.cc/qslcard/GeteQSL.cfm?SubMode=\(mode)&UserName=\(username)&Password=\(password)&CallsignFrom=\(cleanCall)&QSOYear=\(cleanDate.prefix(4))&QSOMonth=\(cleanDate.dropFirst(4).prefix(2))&QSODay=\(cleanDate.suffix(2))&QSOHour=\(cleanTime.prefix(2))&QSOMinute=\(cleanTime.suffix(2))"

        guard let imageFetchURL = URL(string: cardURLString) else {
            throw URLError(.badURL)
        }

        let (imageData, response) = try await urlSession.data(from: imageFetchURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode), imageData.count > 1000 else {
            throw NSError(domain: "EQSLService", code: 404, userInfo: [NSLocalizedDescriptionKey: "No graphical eQSL card found for this QSO"])
        }

        let destURL = cardsDirectoryURL.appendingPathComponent(localCardFilename(callsign: callsign, date: date, band: band, mode: mode))
        try imageData.write(to: destURL)

        self.downloadedCardCount += 1
        return destURL
    }
}
