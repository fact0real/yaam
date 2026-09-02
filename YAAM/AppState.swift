//  In the name of Allah
//  AppState.swift
//  YAAM
//
//  Created by factoreal on 7/30/26.
//

import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers
import WebKit

enum RankHistoryMetric: String, CaseIterable, Identifiable {
    case qso
    case bands
    case dxcc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qso: return "QSO Rank"
        case .bands: return "Bands Rank"
        case .dxcc: return "DXCC Rank"
        }
    }

    var icon: String {
        switch self {
        case .qso: return "antenna.radiowaves.left.and.right"
        case .bands: return "waveform.path.ecg"
        case .dxcc: return "globe.americas.fill"
        }
    }
}

struct QRZRankHistorySnapshot: Identifiable, Codable {
    let date: Date
    let callsign: String
    let countryIso: String?
    let qsoRank: Int?
    let bandRank: Int?
    let dxccRank: Int?
    let qsoScore: Int?
    let bandScore: Int?
    let dxccScore: Int?

    var id: String { "\(Self.dayKey(for: date))-\(callsign)" }

    init(date: Date = Date(), response: QRZRankResponse) {
        self.date = date
        callsign = response.callsign?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        countryIso = response.country_iso
        qsoRank = Self.parseRank(response.rank_qso)
        bandRank = Self.parseRank(response.rank_band)
        dxccRank = Self.parseRank(response.rank_countries)
        qsoScore = Self.parseRank(response.score_qso)
        bandScore = Self.parseRank(response.score_band)
        dxccScore = Self.parseRank(response.score_countries)
    }

    func rank(for metric: RankHistoryMetric) -> Int? {
        switch metric {
        case .qso: return qsoRank
        case .bands: return bandRank
        case .dxcc: return dxccRank
        }
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func parseRank(_ value: String?) -> Int? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(cleaned)
    }
}

struct RankTrendPoint: Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(rank)" }
    let date: Date
    let label: String
    let rank: Int
}

struct RankTrendSeries: Identifiable {
    var id: String { callsign }
    let callsign: String
    let countryIso: String?
    let isOwner: Bool
    let latestRank: Int?
    let latestGap: Int?
    let latestMovement: Int?
    let latestGapMovement: Int?
    let points: [RankTrendPoint]
}

// MARK: - Band Statistics Model
nonisolated struct BandStatModel: Identifiable, Sendable {
    let id = UUID()
    let band: String
    let qsoCount: Int
    let confirmedCount: Int
    let unconfirmedCount: Int
    let dxccCount: Int
    let confirmedDxccCount: Int
    let percentage: Double
}

// MARK: - Worked but Unconfirmed Country Statistics Model
nonisolated struct UnconfirmedBandCountryStatModel: Identifiable, Sendable {
    let id = UUID()
    let band: String
    let countries: [UnconfirmedCountryStatModel]
}

nonisolated struct UnconfirmedCountryStatModel: Identifiable, Sendable {
    let id: UUID
    let country: String
    let qsoCount: Int
    let latestQSODate: Date?
    let latestQSODateString: String
    let daysAgo: Int?
    let callsigns: [String]
    let emailsSentCount: Int
    let lastEmailDate: Date?

    init(
        id: UUID = UUID(),
        country: String,
        qsoCount: Int,
        latestQSODate: Date? = nil,
        latestQSODateString: String = "",
        daysAgo: Int? = nil,
        callsigns: [String] = [],
        emailsSentCount: Int = 0,
        lastEmailDate: Date? = nil
    ) {
        self.id = id
        self.country = country
        self.qsoCount = qsoCount
        self.latestQSODate = latestQSODate
        self.latestQSODateString = latestQSODateString
        self.daysAgo = daysAgo
        self.callsigns = callsigns
        self.emailsSentCount = emailsSentCount
        self.lastEmailDate = lastEmailDate
    }
}

struct UnconfirmedCallsignStatModel: Identifiable {
    let id = UUID()
    let callsign: String
    let qsoCount: Int
    let countries: String
    let bands: String
    let email: String
}

struct EmailHistoryEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let callsign: String
    let email: String
    let subject: String
    let status: String
}

struct BulkEmailRecipient: Identifiable {
    let id = UUID()
    let callsign: String
    let email: String
    let qsoCount: Int
    let bands: String
    let countries: String
    let qso: QSORecordModel?
    let unconfirmedQSOs: [QSORecordModel]
}

enum ActivitySound {
    case success
    case failure
    case notice
}

struct QRZEmailDebugReport {
    let callsign: String
    let email: String?
    let directory: URL?
    let files: [URL]
    let notes: [String]
}

nonisolated struct QRZStoredCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool

    init(cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresDate = cookie.expiresDate
        isSecure = cookie.isSecure
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path.isEmpty ? "/" : path,
            .secure: isSecure ? "TRUE" : "FALSE"
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        return HTTPCookie(properties: properties)
    }
}

enum QRZSessionStore {
    static func save(cookies: [HTTPCookie]) -> String {
        let qrzCookies = cookies.filter { $0.domain.contains("qrz.com") }
        let cookieHeader = qrzCookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        _ = CredentialVault.set(cookieHeader, for: .qrzCookieHeader)

        let storedCookies = qrzCookies.map(QRZStoredCookie.init(cookie:))
        if let data = try? JSONEncoder().encode(storedCookies) {
            _ = CredentialVault.set(data, for: .qrzCookieArchive)
        }

        return cookieHeader
    }

    static func savedCookieHeader(allowUserInteraction: Bool = true) -> String {
        let structuredHeader = validStoredCookies(allowUserInteraction: allowUserInteraction)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !structuredHeader.isEmpty {
            return structuredHeader
        }

        return allowUserInteraction
            ? CredentialVault.value(for: .qrzCookieHeader)
            : CredentialVault.valueIfAvailableWithoutPrompt(for: .qrzCookieHeader)
    }

    static func hasSavedSession(allowUserInteraction: Bool = true) -> Bool {
        !savedCookieHeader(allowUserInteraction: allowUserInteraction).isEmpty
    }

    static func restoreToWebKit(completion: (() -> Void)? = nil) {
        let cookies = validStoredCookies().compactMap(\.httpCookie)
        guard !cookies.isEmpty else {
            completion?()
            return
        }

        let cookieStore = QRZWebKitSession.websiteDataStore.httpCookieStore
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion?()
        }
    }

    static func clear() {
        _ = CredentialVault.delete(.qrzCookieHeader)
        _ = CredentialVault.delete(.qrzCookieArchive)
    }

    private static func validStoredCookies(allowUserInteraction: Bool = true) -> [QRZStoredCookie] {
        let archive = allowUserInteraction
            ? CredentialVault.data(for: .qrzCookieArchive)
            : CredentialVault.dataIfAvailableWithoutPrompt(for: .qrzCookieArchive)
        guard let data = archive,
              let cookies = try? JSONDecoder().decode([QRZStoredCookie].self, from: data) else {
            return []
        }

        let now = Date()
        let validCookies = cookies.filter { cookie in
            guard let expiresDate = cookie.expiresDate else { return true }
            return expiresDate > now
        }

        if allowUserInteraction, validCookies.count != cookies.count {
            if let data = try? JSONEncoder().encode(validCookies) {
                _ = CredentialVault.set(data, for: .qrzCookieArchive)
            }
            if validCookies.isEmpty {
                _ = CredentialVault.delete(.qrzCookieHeader)
            }
        }

        return validCookies
    }
}

enum ClubLogSessionStore {
    static func save(cookies: [HTTPCookie]) -> String {
        let clubLogCookies = cookies.filter { $0.domain.contains("clublog.org") }
        let cookieHeader = clubLogCookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        _ = CredentialVault.set(cookieHeader, for: .clubLogCookieHeader)

        let storedCookies = clubLogCookies.map(QRZStoredCookie.init(cookie:))
        if let data = try? JSONEncoder().encode(storedCookies) {
            _ = CredentialVault.set(data, for: .clubLogCookieArchive)
        }

        return cookieHeader
    }

    static func savedCookieHeader(allowUserInteraction: Bool = true) -> String {
        let structuredHeader = validStoredCookies(allowUserInteraction: allowUserInteraction)
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        if !structuredHeader.isEmpty {
            return structuredHeader
        }

        return allowUserInteraction
            ? CredentialVault.value(for: .clubLogCookieHeader)
            : CredentialVault.valueIfAvailableWithoutPrompt(for: .clubLogCookieHeader)
    }

    static func hasSavedSession(allowUserInteraction: Bool = true) -> Bool {
        !savedCookieHeader(allowUserInteraction: allowUserInteraction).isEmpty
    }

    static func restoreToWebKit(completion: (() -> Void)? = nil) {
        let cookies = validStoredCookies().compactMap(\.httpCookie)
        guard !cookies.isEmpty else {
            completion?()
            return
        }

        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion?()
        }
    }

    static func clear() {
        _ = CredentialVault.delete(.clubLogCookieHeader)
        _ = CredentialVault.delete(.clubLogCookieArchive)
    }

    private static func validStoredCookies(allowUserInteraction: Bool = true) -> [QRZStoredCookie] {
        let archive = allowUserInteraction
            ? CredentialVault.data(for: .clubLogCookieArchive)
            : CredentialVault.dataIfAvailableWithoutPrompt(for: .clubLogCookieArchive)
        guard let data = archive,
              let cookies = try? JSONDecoder().decode([QRZStoredCookie].self, from: data) else {
            return []
        }

        let now = Date()
        let validCookies = cookies.filter { cookie in
            guard let expiresDate = cookie.expiresDate else { return true }
            return expiresDate > now
        }

        if allowUserInteraction, validCookies.count != cookies.count {
            if let data = try? JSONEncoder().encode(validCookies) {
                _ = CredentialVault.set(data, for: .clubLogCookieArchive)
            }
            if validCookies.isEmpty {
                _ = CredentialVault.delete(.clubLogCookieHeader)
            }
        }

        return validCookies
    }
}

struct PropagationSnapshot {
    var updatedAt: Date?
    var solarFlux: String = "-"
    var aIndex: String = "-"
    var kIndex: String = "-"
    var xray: String = "-"
    var sunspots: String = "-"
    var signalNoise: String = "-"
    var geomagField: String = "-"
    var aurora: String = "-"
    var solarWind: String = "-"
    var bz: String = "-"
    var bands: [String: String] = [:]
    var vhfConditions: [String: String] = [:]
    var solarForecast: [SolarForecastPoint] = []
}

struct PSKReporterSignal: Identifiable {
    let id = UUID()
    let receiverCallsign: String
    let receiverLocator: String
    let senderCallsign: String
    let frequencyHz: Int
    let mode: String
    let snr: Int?
    let flowStart: Date

    var isSixMeters: Bool {
        (50_000_000...54_000_000).contains(frequencyHz)
    }

    var bandLabel: String {
        switch frequencyHz {
        case 50_000_000...54_000_000: return "6m"
        case 28_000_000...29_700_000: return "10m"
        case 24_890_000...24_990_000: return "12m"
        case 21_000_000...21_450_000: return "15m"
        case 18_068_000...18_168_000: return "17m"
        case 14_000_000...14_350_000: return "20m"
        case 7_000_000...7_300_000: return "40m"
        default:
            return String(format: "%.3f MHz", Double(frequencyHz) / 1_000_000)
        }
    }

    var snrText: String {
        snr.map { "\($0) dB" } ?? "-"
    }

    var snrColor: Color {
        guard let snr else { return .secondary }
        if snr >= -8 { return .green }
        if snr >= -18 { return .orange }
        return .red
    }

    var ageText: String {
        let minutes = max(0, Int(Date().timeIntervalSince(flowStart) / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }
}

struct SixMeterOpeningAssessment {
    let title: String
    let detail: String
    let evidence: String
    let icon: String
    let color: Color
    let isOpen: Bool
}

struct SolarForecastPoint: Identifiable {
    var id: String { dateLabel }
    let date: Date
    let dateLabel: String
    let solarFlux: Int
    let aIndex: Int
    let kpIndex: Int
}

// MARK: - Country Statistics Model
nonisolated struct CountryStatModel: Identifiable, Sendable {
    let id = UUID()
    let country: String
    let flag: String
    let qsoCount: Int
    let confirmedCount: Int
    let unconfirmedCount: Int
    
    var unconfirmedPercentage: Double {
        guard qsoCount > 0 else { return 0.0 }
        return Double(unconfirmedCount) / Double(qsoCount) * 100.0
    }
}

// Note: Country and DXCC flag lookup engine is implemented in CountryFlagEngine.swift

// MARK: - Filter Criteria Model
struct FilterCriteria {
    var useDate: Bool = false
    var startDate: Date = Date()
    var endDate: Date = Date()
    
    var useBand: Bool = false
    var band: String = "All"
    
    var useMode: Bool = false
    var mode: String = "All"
    
    var useCallsign: Bool = false
    var callsign: String = ""
    
    var useOperator: Bool = false
    var operatorStation: String = ""
    
    var useZone: Bool = false
    var zone: String = ""
    
    var useCountry: Bool = false
    var selectedCountries: Set<String> = []
    
    var useQSLSent: Bool = false
    var qslSent: String = "Y"
    
    var useQSLRcvd: Bool = false
    var qslRcvd: String = "Y"
    
    var useConfirmation: Bool = false
    var confirmationType: String = "Any Method"
    var confirmationState: String = "Confirmed (Y)"
    
    var useContinent: Bool = false
    var selectedContinents: Set<String> = []
    
    var isActive: Bool {
        useDate || useBand || useMode || useCallsign || useOperator || useZone || useCountry || useQSLSent || useQSLRcvd || useConfirmation || useContinent
    }
    
    mutating func reset() {
        self = FilterCriteria()
    }
}

// MARK: - Enhanced QSO Record Model (With Composite Unique Key)
nonisolated struct QSORecordModel: Identifiable, Sendable {
    let id: UUID
    var index: Int
    var fields: [String: String]
    private(set) var searchDocument: LogSearchDocument

    init(id: UUID = UUID(), index: Int, fields: [String: String]) {
        self.id = id
        self.index = index
        let normalized = CountryNameNormalizer.normalizedFields(fields).fields
        self.fields = normalized
        self.searchDocument = Self.makeSearchDocument(fields: normalized)
    }

    private static func makeSearchDocument(fields: [String: String]) -> LogSearchDocument {
        let cName = fields["COUNTRY"] ?? ""
        let country = cName.isEmpty ? "" : canonicalCountryName(cName)
        let flag = country.isEmpty ? "" : countryToFlag(country)
        let cont = fields["CONT"] ?? ""
        return LogSearchEngine.makeDocument(
            fields: fields,
            country: country,
            continent: cont,
            countryFlag: flag
        )
    }
    
    var isConfirmed: Bool {
        let confirmationValues = [
            "LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "QRZCOM_QSL_RCVD",
            "APP_QRZLOG_STATUS", "EQSL_QSL_RCVD", "QSL_RCVD"
        ].map { fields[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "" }
        return confirmationValues.contains { ["Y", "V", "C", "CONFIRMED", "VERIFIED"].contains($0) }
    }
    
    // SMART DEDUPLICATION KEY: Call + Date + Time + Band + Mode
    var uniqueKey: String {
        QSOIdentity.exactKey(fields: fields)
    }
    
    subscript(key: String) -> String {
        get {
            let value = fields[key] ?? ""
            return ["COUNTRY", "MY_COUNTRY"].contains(key.uppercased()) ? canonicalCountryName(value) : value
        }
        set {
            fields[key] = ["COUNTRY", "MY_COUNTRY"].contains(key.uppercased()) ? canonicalCountryName(newValue) : newValue
            searchDocument = Self.makeSearchDocument(fields: fields)
        }
    }

    public func toADIFRecordString() -> String {
        var adif = ""
        for (k, val) in fields {
            let clean = val.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                adif += "<\(k):\(clean.utf8.count)>\(clean) "
            }
        }
        adif += "<EOR>"
        return adif
    }
}

// MARK: - Shared QRZ WebKit Session
enum QRZWebKitSession {
    static let websiteDataStore = WKWebsiteDataStore.default()
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
    static let acceptLanguage = "en-US,en;q=0.9"
    static let acceptHeader = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"

    static func browserLikeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = websiteDataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let source = """
        try {
            Object.defineProperty(navigator, 'platform', { get: function() { return 'MacIntel'; } });
            Object.defineProperty(navigator, 'vendor', { get: function() { return 'Apple Computer, Inc.'; } });
            Object.defineProperty(navigator, 'languages', { get: function() { return ['en-US', 'en']; } });
        } catch(e) {}
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        return config
    }

    static func browserLikeRequest(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalAndRemoteCacheData,
        timeoutInterval: TimeInterval = 20
    ) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("?1", forHTTPHeaderField: "Sec-Fetch-User")
        return request
    }
}

// MARK: - Proven Native QRZ Scraper Engine (Simple & Reliable)
@MainActor
struct QRZEmailFetchResult {
    let email: String?
    let name: String?
    let qmailRaw: String
    let qmailDecoded: String
    let notFound: Bool

    init(email: String?, name: String? = nil, qmailRaw: String, qmailDecoded: String, notFound: Bool = false) {
        self.email = email
        self.name = name
        self.qmailRaw = qmailRaw
        self.qmailDecoded = qmailDecoded
        self.notFound = notFound
    }
}

@MainActor
class QRZWebKitScraper: NSObject, WKNavigationDelegate {
    static let shared = QRZWebKitScraper()
    private var webView: WKWebView!
    private var continuation: CheckedContinuation<QRZEmailFetchResult, Never>?
    private var debugContinuation: CheckedContinuation<QRZEmailDebugReport, Never>?
    private var emailRequestID: UUID?
    private var emailTimeoutTask: Task<Void, Never>?
    private var activeCallsign: String = ""
    private var isDebugFetch = false
    private var debugDirectoryForScreenshot: URL?

    override init() {
        super.init()
        let config = QRZWebKitSession.browserLikeConfiguration()
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        self.webView.customUserAgent = QRZWebKitSession.userAgent
        self.webView.allowsBackForwardNavigationGestures = false
        self.webView.navigationDelegate = self
    }

    func hasQRZCookies(allowCredentialPrompt: Bool = true) async -> Bool {
        await withCheckedContinuation { continuation in
            QRZWebKitSession.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let hasWebKitCookies = cookies.contains { cookie in
                    cookie.domain.contains("qrz.com")
                }
                continuation.resume(
                    returning: hasWebKitCookies || QRZSessionStore.hasSavedSession(allowUserInteraction: allowCredentialPrompt)
                )
            }
        }
    }

    func fetchEmail(for callsign: String) async -> QRZEmailFetchResult {
        guard let url = URL(string: "https://www.qrz.com/db/\(callsign)") else {
            return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
        }

        return await withCheckedContinuation { continuation in
            let requestID = UUID()
            finishEmailFetch(returning: QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: ""))

            self.continuation = continuation
            self.emailRequestID = requestID
            self.activeCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            self.isDebugFetch = false
            self.emailTimeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)

                guard !Task.isCancelled, self.emailRequestID == requestID else { return }
                self.webView.stopLoading()
                self.finishEmailFetch(returning: QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: ""))
            }

            let request = QRZWebKitSession.browserLikeRequest(url: url, timeoutInterval: 15)
            self.webView.load(request)
        }
    }

    func debugFetchEmail(for callsign: String) async -> QRZEmailDebugReport {
        guard let url = URL(string: "https://www.qrz.com/db/\(callsign)") else {
            return QRZEmailDebugReport(callsign: callsign, email: nil, directory: nil, files: [], notes: ["Invalid QRZ URL"])
        }

        return await withCheckedContinuation { continuation in
            let requestID = UUID()
            finishEmailFetch(returning: QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: ""))

            self.debugContinuation = continuation
            self.emailRequestID = requestID
            self.activeCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            self.isDebugFetch = true
            self.emailTimeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 35_000_000_000)

                guard !Task.isCancelled, self.emailRequestID == requestID else { return }
                self.captureTimeoutDebugArtifacts(
                    callsign: self.activeCallsign,
                    url: self.webView.url?.absoluteString ?? url.absoluteString
                ) { report in
                    self.webView.stopLoading()
                    self.finishDebugFetch(report: report)
                }
            }

            let request = QRZWebKitSession.browserLikeRequest(url: url, timeoutInterval: 20)
            self.webView.load(request)
        }
    }

    private func finishEmailFetch(returning result: QRZEmailFetchResult) {
        emailTimeoutTask?.cancel()
        emailTimeoutTask = nil
        emailRequestID = nil
        isDebugFetch = false

        let cont = continuation
        continuation = nil
        cont?.resume(returning: result)
    }

    private func finishDebugFetch(report: QRZEmailDebugReport) {
        emailTimeoutTask?.cancel()
        emailTimeoutTask = nil
        emailRequestID = nil
        isDebugFetch = false

        let cont = debugContinuation
        debugContinuation = nil
        cont?.resume(returning: report)
    }

    // MARK: - WKNavigationDelegate
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if self.isDebugFetch {
                self.runDebugEmailExtraction(in: webView)
                return
            }

            let jsScript = QRZWebKitScraper.emailRevealPromiseScript(debug: false)

            webView.evaluateJavaScript(jsScript) { [weak self] result, _ in
                let payload = result as? [String: Any] ?? [:]
                let extracted = payload["email"] as? String ?? ""
                let email = extracted.isEmpty ? nil : extracted
                let extractedName = payload["name"] as? String ?? ""
                let name = extractedName.isEmpty ? nil : extractedName
                let qmailRaw = payload["qmailRaw"] as? String ?? ""
                let qmailDecoded = payload["qmailDecoded"] as? String ?? ""

                Task { @MainActor in
                    self?.finishEmailFetch(
                        returning: QRZEmailFetchResult(
                            email: email,
                            name: name,
                            qmailRaw: qmailRaw,
                            qmailDecoded: qmailDecoded
                        )
                    )
                }
            }
        }
    }

    private func runDebugEmailExtraction(in webView: WKWebView) {
        let beforeScript = QRZWebKitScraper.debugSnapshotScript(label: "before")
        webView.evaluateJavaScript(beforeScript) { [weak self] beforeResult, beforeError in
            guard let self else { return }
            let before = beforeResult as? [String: Any] ?? [:]

            let revealScript = QRZWebKitScraper.debugRevealScript()
            webView.evaluateJavaScript(revealScript) { [weak self] revealResult, revealError in
                guard let self else { return }
                let reveal = revealResult as? [String: Any] ?? [:]

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let afterScript = QRZWebKitScraper.debugSnapshotScript(label: "after")
                    webView.evaluateJavaScript(afterScript) { [weak self] afterResult, afterError in
                        guard let self else { return }
                        let after = afterResult as? [String: Any] ?? [:]
                        let report = self.writeDebugArtifacts(
                            callsign: self.activeCallsign,
                            before: before,
                            reveal: reveal,
                            after: after,
                            errors: [
                                beforeError.map { "Before snapshot error: \($0.localizedDescription)" },
                                revealError.map { "Reveal script error: \($0.localizedDescription)" },
                                afterError.map { "After snapshot error: \($0.localizedDescription)" }
                            ].compactMap { $0 }
                        )
                        self.finishDebugFetch(report: report)
                    }
                }
            }
        }
    }

    private static func debugSnapshotScript(label: String) -> String {
        """
        (function() {
            function cleanEmail(value) {
                if (!value) { return ""; }
                var decoded = String(value)
                    .replace(/mailto:/ig, " ")
                    .replace(/<[^>]+>/g, " ")
                    .replace(/\\s+/g, " ")
                    .trim();
                var match = decoded.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}(?=\\b|\\s|<|&|$)/i);
                if (!match) { return ""; }
                return match[0].replace(/mailto$/i, "").replace(/[.,;:]+$/g, "");
            }
            var qem = document.getElementById("qem");
            var rect = qem ? qem.getBoundingClientRect() : null;
            var mailtos = Array.from(document.querySelectorAll('a[href^="mailto:"]')).map(function(a) {
                return a.getAttribute("href") || "";
            });
            var html = document.documentElement ? document.documentElement.outerHTML : "";
            return {
                label: "\(label)",
                url: window.location.href || "",
                title: document.title || "",
                bodyText: document.body ? document.body.innerText : "",
                html: html,
                qemExists: !!qem,
                qemText: qem ? (qem.innerText || qem.textContent || "") : "",
                qemHTML: qem ? (qem.outerHTML || "") : "",
                qemRect: rect ? { x: rect.x, y: rect.y, width: rect.width, height: rect.height, top: rect.top, left: rect.left } : null,
                showqemType: typeof window.showqem,
                showqemSource: (typeof window.showqem === "function") ? String(window.showqem).slice(0, 4000) : "",
                userAgent: navigator.userAgent,
                platform: navigator.platform,
                webdriver: navigator.webdriver,
                mailtos: mailtos,
                extractedEmail: cleanEmail((qem ? (qem.innerText || qem.textContent || qem.innerHTML || "") : "") + " " + mailtos.join(" ") + " " + html)
            };
        })();
        """
    }

    private static func debugRevealScript() -> String {
        emailRevealPromiseScript(debug: true)
    }

    private static func emailRevealPromiseScript(debug: Bool) -> String {
        """
        new Promise(function(resolve) {
            var steps = [];

            function log(name, detail) {
                steps.push(detail ? (name + ": " + detail) : name);
            }

            function cleanEmail(value) {
                if (!value) { return ""; }
                var decoded = String(value)
                    .replace(/mailto:/ig, " ")
                    .replace(/<[^>]+>/g, " ")
                    .replace(/^mailto:/i, "")
                    .split("?")[0]
                    .replace(/\\s+/g, " ")
                    .trim();
                var match = decoded.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}(?=\\b|\\s|<|&|$)/i);
                if (!match) { return ""; }
                var email = match[0];
                email = email.replace(/mailto$/i, "").replace(/[.,;:]+$/g, "");
                if (/qrz\\.com|support|example/i.test(email)) { return ""; }
                return email;
            }

            function qmailDetails(source) {
                var encoded = "";
                try {
                    if (typeof window.qmail === "string") {
                        encoded = window.qmail;
                    }
                } catch(e) {}

                if (!encoded && source) {
                    var match = String(source).match(/\\bqmail\\s*=\\s*['"]([^'"]+)['"]/);
                    encoded = match ? match[1] : "";
                }

                if (!encoded) { return { raw: "", decoded: "", email: "" }; }

                var countText = "";
                var decoded = "";
                var i = encoded.length - 1;

                while (i > 0) {
                    var c = encoded.charAt(i);
                    if (c !== "!") {
                        countText += c;
                    } else {
                        break;
                    }
                    i -= 1;
                }

                i -= 1;
                var count = parseInt(countText, 10);
                if (!isFinite(count) || count <= 0) {
                    return { raw: encoded, decoded: "", email: "" };
                }

                for (var x = 0; x < count && i >= 0; x += 1) {
                    decoded += encoded.charAt(i);
                    i -= 2;
                }

                return { raw: encoded, decoded: decoded, email: cleanEmail(decoded) };
            }

            function decodeQmail(source) {
                return qmailDetails(source).email;
            }

            function extractEmail() {
                var html = document.documentElement ? document.documentElement.innerHTML : "";
                var qmailEmail = decodeQmail(html);
                if (qmailEmail) { return qmailEmail; }

                var qem = document.getElementById("qem");
                if (qem) {
                    var qemEmail = cleanEmail(qem.innerText || qem.textContent || "");
                    if (qemEmail) { return qemEmail; }
                    qemEmail = cleanEmail(qem.innerHTML || "");
                    if (qemEmail) { return qemEmail; }
                }

                var mailtoAnchor = document.querySelector('a[href^="mailto:"]');
                if (mailtoAnchor) {
                    var mailtoEmail = cleanEmail(mailtoAnchor.getAttribute("href"));
                    if (mailtoEmail) { return mailtoEmail; }
                }

                return cleanEmail(html);
            }

            function cleanName(value) {
                if (!value) { return ""; }
                var text = String(value)
                    .replace(/<[^>]+>/g, " ")
                    .replace(/&nbsp;/ig, " ")
                    .replace(/&amp;/ig, "&")
                    .replace(/&#39;/g, "'")
                    .replace(/&quot;/ig, "\"")
                    .replace(/\\s+/g, " ")
                    .trim();
                text = text.replace(/\\s*-\\s*QRZ\\.com.*$/i, "").trim();
                if (!text || /@/.test(text) || text.length > 80) { return ""; }
                if (/callsign lookup|qrz ham radio|ham radio/i.test(text)) { return ""; }
                if (/^world$/i.test(text)) { return ""; }
                if (/produced no results|search for.*no results|callsign not found|not found in the qrz database/i.test(text)) { return ""; }
                return text;
            }

            function extractName() {
                var pageCallsign = (window.location.pathname || "").split("/").filter(Boolean).pop() || "";
                var escapedCallsign = pageCallsign.replace(/[^A-Z0-9]/ig, "");

                function nameFromDescription(value) {
                    var text = cleanName(value);
                    if (!text) { return ""; }
                    text = text.replace(/\\s+personal biography\\b.*$/i, "").trim();
                    var commaIndex = text.indexOf(",");
                    if (commaIndex >= 0) { text = text.slice(0, commaIndex).trim(); }
                    if (escapedCallsign) {
                        text = text.replace(new RegExp("\\b" + escapedCallsign + "\\b", "ig"), "").replace(/\\s+/g, " ").trim();
                    }
                    return cleanName(text);
                }

                var description = document.querySelector('meta[property="og:description"], meta[name="description"]');
                if (description) {
                    var descriptionName = nameFromDescription(description.getAttribute("content") || "");
                    if (descriptionName) { return descriptionName; }
                }

                return "";
            }

            function eventInit(qem, rect) {
                var x = Math.max(1, Math.floor((rect.left || 0) + Math.max(2, (rect.width || 10) / 2)));
                var y = Math.max(1, Math.floor((rect.top || 0) + Math.max(2, (rect.height || 10) / 2)));
                return {
                    bubbles: true,
                    cancelable: true,
                    composed: true,
                    view: window,
                    detail: 1,
                    screenX: x + 80,
                    screenY: y + 120,
                    clientX: x,
                    clientY: y,
                    pageX: x + window.scrollX,
                    pageY: y + window.scrollY,
                    button: 0,
                    buttons: 1,
                    relatedTarget: null,
                    pointerId: 1,
                    width: 1,
                    height: 1,
                    pressure: 0.5,
                    pointerType: "mouse",
                    isPrimary: true
                };
            }

            function dispatch(qem, name, init) {
                try {
                    var event;
                    if (name.indexOf("pointer") === 0 && typeof PointerEvent === "function") {
                        event = new PointerEvent(name, init);
                    } else {
                        event = new MouseEvent(name, init);
                    }
                    qem.dispatchEvent(event);
                    log("dispatch " + name, "ok");
                } catch(e) {
                    log("dispatch " + name, e.message);
                }
            }

            function triggerReveal() {
                var qem = document.getElementById("qem");
                if (!qem) {
                    log("span#qem", "not found");
                    return false;
                }

                try {
                    qem.scrollIntoView({ block: "center", inline: "center" });
                    log("scrollIntoView", "ok");
                } catch(e) {
                    log("scrollIntoView", e.message);
                }

                var rect = qem.getBoundingClientRect();
                var init = eventInit(qem, rect);
                log("qemRect", JSON.stringify({ left: rect.left, top: rect.top, width: rect.width, height: rect.height }));

                [
                    "pointerover", "pointerenter", "mouseover", "mouseenter", "pointermove", "mousemove",
                    "pointerdown", "mousedown", "pointerup", "mouseup", "click"
                ].forEach(function(name) {
                    dispatch(qem, name, init);
                });

                try {
                    if (typeof qem.onmouseover === "function") {
                        qem.onmouseover.call(qem, new MouseEvent("mouseover", init));
                        log("qem.onmouseover", "ok");
                    }
                } catch(e) { log("qem.onmouseover", e.message); }

                try {
                    if (typeof qem.onclick === "function") {
                        qem.onclick.call(qem, new MouseEvent("click", init));
                        log("qem.onclick", "ok");
                    }
                } catch(e) { log("qem.onclick", e.message); }

                try {
                    if (typeof window.showqem === "function") {
                        window.showqem.call(qem);
                        log("window.showqem.call(qem)", "ok");
                    }
                } catch(e) { log("window.showqem.call(qem)", e.message); }

                try {
                    if (typeof showqem === "function") {
                        showqem.call(qem);
                        log("showqem.call(qem)", "ok");
                    }
                } catch(e) { log("showqem.call(qem)", e.message); }

                try {
                    qem.focus({ preventScroll: true });
                    log("focus", "ok");
                } catch(e) { log("focus", e.message); }

                return true;
            }

            var firstEmail = extractEmail();
            if (firstEmail) {
                var firstDetails = qmailDetails(document.documentElement ? document.documentElement.innerHTML : "");
                resolve(\(debug ? "{ email: firstEmail, name: extractName(), qmailRaw: firstDetails.raw, qmailDecoded: firstDetails.decoded, steps: steps, immediate: true }" : "{ email: firstEmail, name: extractName(), qmailRaw: firstDetails.raw, qmailDecoded: firstDetails.decoded }"));
                return;
            }

            triggerReveal();

            var attempts = 0;
            var timer = setInterval(function() {
                attempts += 1;
                var email = extractEmail();
                if (email || attempts >= 16) {
                    clearInterval(timer);
                    var qem = document.getElementById("qem");
                    var payload = {
                        email: email || "",
                        name: extractName(),
                        qmailRaw: qmailDetails(document.documentElement ? document.documentElement.innerHTML : "").raw,
                        qmailDecoded: qmailDetails(document.documentElement ? document.documentElement.innerHTML : "").decoded,
                        steps: steps,
                        attempts: attempts,
                        qemExists: !!qem,
                        qemTextAfterPolling: qem ? (qem.innerText || qem.textContent || "") : "",
                        qemHTMLAfterPolling: qem ? (qem.outerHTML || "") : "",
                        showqemType: typeof window.showqem,
                        showqemSource: (typeof window.showqem === "function") ? String(window.showqem).slice(0, 4000) : ""
                    };
                    resolve(payload);
                    return;
                }
                triggerReveal();
            }, 250);
        });
        """
    }

    private func writeDebugArtifacts(
        callsign: String,
        before: [String: Any],
        reveal: [String: Any],
        after: [String: Any],
        errors: [String]
    ) -> QRZEmailDebugReport {
        let fm = FileManager.default
        let safeCallsign = callsign.isEmpty ? "UNKNOWN" : callsign
        let timestamp = Int(Date().timeIntervalSince1970)
        let baseURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YAAM/QRZDebug/\(safeCallsign)-\(timestamp)")

        guard let directory = baseURL else {
            return QRZEmailDebugReport(callsign: safeCallsign, email: nil, directory: nil, files: [], notes: ["Unable to locate Application Support directory"] + errors)
        }

        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        debugDirectoryForScreenshot = directory
        var files: [URL] = []
        var notes = errors

        func writeText(_ name: String, _ value: String) {
            let url = directory.appendingPathComponent(name)
            do {
                try value.write(to: url, atomically: true, encoding: .utf8)
                files.append(url)
            } catch {
                notes.append("Failed writing \(name): \(error.localizedDescription)")
            }
        }

        func jsonString(_ object: Any) -> String {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
                  let string = String(data: data, encoding: .utf8) else {
                return "\(object)"
            }
            return string
        }

        writeText("01-before.html", before["html"] as? String ?? "")
        writeText("01-before-body.txt", before["bodyText"] as? String ?? "")
        writeText("01-before-summary.json", jsonString(before.filter { $0.key != "html" && $0.key != "bodyText" }))
        writeText("02-reveal-steps.json", jsonString(reveal))
        writeText("03-after.html", after["html"] as? String ?? "")
        writeText("03-after-body.txt", after["bodyText"] as? String ?? "")
        writeText("03-after-summary.json", jsonString(after.filter { $0.key != "html" && $0.key != "bodyText" }))
        captureDebugScreenshot(to: directory.appendingPathComponent("04-webview-screenshot.png"))

        let email = (after["extractedEmail"] as? String).flatMap { $0.isEmpty ? nil : $0 } ??
            (before["extractedEmail"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let summary = """
        QRZ email debug for \(safeCallsign)
        URL before: \(before["url"] as? String ?? "-")
        URL after: \(after["url"] as? String ?? "-")
        qem before: \(before["qemText"] as? String ?? "-")
        qem after: \(after["qemText"] as? String ?? "-")
        showqem type before: \(before["showqemType"] as? String ?? "-")
        extracted email: \(email ?? "-")
        notes:
        \(notes.isEmpty ? "-" : notes.joined(separator: "\n"))
        """
        writeText("00-debug-summary.txt", summary)

        return QRZEmailDebugReport(callsign: safeCallsign, email: email, directory: directory, files: files, notes: notes)
    }

    private func captureDebugScreenshot(to url: URL) {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: webView.bounds.size)
        webView.takeSnapshot(with: configuration) { image, _ in
            guard let image,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
        }
    }

    private func writeTimeoutDebugArtifacts(callsign: String, url: String) -> QRZEmailDebugReport {
        let fm = FileManager.default
        let safeCallsign = callsign.isEmpty ? "UNKNOWN" : callsign
        let timestamp = Int(Date().timeIntervalSince1970)
        guard let directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YAAM/QRZDebug/\(safeCallsign)-\(timestamp)-timeout") else {
            return QRZEmailDebugReport(callsign: safeCallsign, email: nil, directory: nil, files: [], notes: ["Timed out while loading QRZ page"])
        }

        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let summaryURL = directory.appendingPathComponent("00-timeout.txt")
        let cookieURL = directory.appendingPathComponent("01-cookie-summary.txt")
        let summary = """
        QRZ email debug timed out before the page finished loading.

        Callsign: \(safeCallsign)
        Last URL: \(url)
        Timeout: 35 seconds

        This means WKWebView did not reach didFinish, so YAAM could not save before/after DOM snapshots.
        Likely causes: QRZ blocked/hung navigation, session challenge, network stall, or a WebKit load that never completes.
        """

        var files: [URL] = []
        try? summary.write(to: summaryURL, atomically: true, encoding: .utf8)
        if fm.fileExists(atPath: summaryURL.path) { files.append(summaryURL) }

        QRZWebKitSession.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let text = cookies
                .filter { $0.domain.contains("qrz.com") }
                .map { "\($0.name)=<redacted>; domain=\($0.domain); path=\($0.path); expires=\($0.expiresDate?.description ?? "session")" }
                .joined(separator: "\n")
            try? (text.isEmpty ? "No qrz.com cookies found." : text).write(to: cookieURL, atomically: true, encoding: .utf8)
        }

        files.append(cookieURL)
        return QRZEmailDebugReport(callsign: safeCallsign, email: nil, directory: directory, files: files, notes: ["Timed out while loading QRZ page"])
    }

    private func captureTimeoutDebugArtifacts(
        callsign: String,
        url: String,
        completion: @escaping (QRZEmailDebugReport) -> Void
    ) {
        let snapshotScript = QRZWebKitScraper.debugSnapshotScript(label: "timeout-partial")
        webView.evaluateJavaScript(snapshotScript) { [weak self] snapshotResult, snapshotError in
            guard let self else { return }
            let snapshot = snapshotResult as? [String: Any] ?? [:]
            self.fetchRawQRZHTML(callsign: callsign) { rawHTML, rawInfo in
                let report = self.writeTimeoutDebugArtifacts(
                    callsign: callsign,
                    url: url,
                    partialSnapshot: snapshot,
                    rawHTML: rawHTML,
                    rawInfo: rawInfo,
                    errors: snapshotError.map { ["Partial DOM snapshot error: \($0.localizedDescription)"] } ?? []
                )
                completion(report)
            }
        }
    }

    private func writeTimeoutDebugArtifacts(
        callsign: String,
        url: String,
        partialSnapshot: [String: Any],
        rawHTML: String?,
        rawInfo: String,
        errors: [String]
    ) -> QRZEmailDebugReport {
        let fm = FileManager.default
        let safeCallsign = callsign.isEmpty ? "UNKNOWN" : callsign
        let timestamp = Int(Date().timeIntervalSince1970)
        guard let directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YAAM/QRZDebug/\(safeCallsign)-\(timestamp)-timeout") else {
            return QRZEmailDebugReport(callsign: safeCallsign, email: nil, directory: nil, files: [], notes: ["Timed out while loading QRZ page"] + errors)
        }

        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [URL] = []
        var notes = ["Timed out while loading QRZ page"] + errors

        func writeText(_ name: String, _ value: String) {
            let fileURL = directory.appendingPathComponent(name)
            do {
                try value.write(to: fileURL, atomically: true, encoding: .utf8)
                files.append(fileURL)
            } catch {
                notes.append("Failed writing \(name): \(error.localizedDescription)")
            }
        }

        func jsonString(_ object: Any) -> String {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
                  let string = String(data: data, encoding: .utf8) else {
                return "\(object)"
            }
            return string
        }

        let partialHTML = partialSnapshot["html"] as? String ?? ""
        let partialBody = partialSnapshot["bodyText"] as? String ?? ""
        writeText("01-timeout-partial-dom.html", partialHTML)
        writeText("01-timeout-partial-body.txt", partialBody)
        writeText("01-timeout-partial-summary.json", jsonString(partialSnapshot.filter { $0.key != "html" && $0.key != "bodyText" }))
        writeText("02-urlsession-raw.html", rawHTML ?? "")
        writeText("02-urlsession-info.txt", rawInfo)

        QRZWebKitSession.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let text = cookies
                .filter { $0.domain.contains("qrz.com") }
                .map { "\($0.name)=<redacted>; domain=\($0.domain); path=\($0.path); expires=\($0.expiresDate?.description ?? "session")" }
                .joined(separator: "\n")
            try? (text.isEmpty ? "No qrz.com cookies found." : text).write(to: directory.appendingPathComponent("03-cookie-summary.txt"), atomically: true, encoding: .utf8)
        }
        files.append(directory.appendingPathComponent("03-cookie-summary.txt"))

        let email = (partialSnapshot["extractedEmail"] as? String).flatMap { $0.isEmpty ? nil : $0 } ??
            rawHTML.flatMap { html in
                let normalized = html.replacingOccurrences(of: "mailto:", with: " ")
                return normalized.range(of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}(?=\b|\s|<|&|$)"#, options: [.regularExpression, .caseInsensitive]).map { String(normalized[$0]) }
            }

        let summary = """
        QRZ email debug timed out before the page finished loading.

        Callsign: \(safeCallsign)
        Last URL: \(url)
        Timeout: 35 seconds
        Partial DOM bytes: \(partialHTML.utf8.count)
        Raw URLSession HTML bytes: \(rawHTML?.utf8.count ?? 0)
        Extracted email: \(email ?? "-")

        Files:
        01-timeout-partial-dom.html - DOM currently visible in WKWebView at timeout
        02-urlsession-raw.html - raw HTML fetched with URLSession using QRZ cookies and Safari-like headers
        03-cookie-summary.txt - qrz.com cookies present in WebKit

        Notes:
        \(notes.joined(separator: "\n"))
        """
        writeText("00-timeout-summary.txt", summary)

        return QRZEmailDebugReport(callsign: safeCallsign, email: email, directory: directory, files: files, notes: notes)
    }

    private func fetchRawQRZHTML(callsign: String, completion: @escaping (String?, String) -> Void) {
        guard let url = URL(string: "https://www.qrz.com/db/\(callsign)") else {
            completion(nil, "Invalid raw fetch URL")
            return
        }

        QRZWebKitSession.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            var request = QRZWebKitSession.browserLikeRequest(url: url, timeoutInterval: 20)
            let cookieHeader = cookies
                .filter { $0.domain.contains("qrz.com") }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            if !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let finalURL = response?.url?.absoluteString ?? url.absoluteString
                let mime = response?.mimeType ?? "-"
                let encoding = response?.textEncodingName ?? "-"
                let html = data.flatMap { String(data: $0, encoding: .utf8) } ??
                    data.flatMap { String(data: $0, encoding: .isoLatin1) }
                let info = """
                Raw URLSession fetch
                URL: \(url.absoluteString)
                Final URL: \(finalURL)
                HTTP status: \(status)
                MIME: \(mime)
                Encoding: \(encoding)
                Data bytes: \(data?.count ?? 0)
                Cookie header sent: \(cookieHeader.isEmpty ? "no" : "yes")
                Error: \(error?.localizedDescription ?? "-")
                """
                DispatchQueue.main.async {
                    completion(html, info)
                }
            }.resume()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            if self.isDebugFetch {
                self.finishDebugFetch(report: QRZEmailDebugReport(callsign: self.activeCallsign, email: nil, directory: nil, files: [], notes: ["Navigation failed: \(error.localizedDescription)"]))
            } else {
                self.finishEmailFetch(returning: QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: ""))
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            if self.isDebugFetch {
                self.finishDebugFetch(report: QRZEmailDebugReport(callsign: self.activeCallsign, email: nil, directory: nil, files: [], notes: ["Provisional navigation failed: \(error.localizedDescription)"]))
            } else {
                self.finishEmailFetch(returning: QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: ""))
            }
        }
    }
}

// MARK: - Global Application State Manager (Workspace Architecture)
class AppState: NSObject, ObservableObject {
    private static let adifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.14.4"
    }
    
    // UI & Status States
    @Published var logText: String = "YAAM Master Logbook Engine Initialized.\n"
    @Published var isCheckingUpdates: Bool = false
    @Published var isLoading: Bool = false
    @Published var isSyncingAPI: Bool = false
    @Published var propagationSnapshot = PropagationSnapshot()
    @Published var isFetchingPropagation: Bool = false
    @Published var pskReporterSignals: [PSKReporterSignal] = []
    @Published var isFetchingPSKReporter: Bool = false
    @Published var pskReporterStatus: String = ""
    @Published var pskReporterLastUpdated: Date?
    @Published var contestCalendarEntries: [ContestCalendarEntry] = []
    @Published var contestCalendarStatus: String = "Calendar not loaded yet"
    @Published var contestCalendarLastUpdated: Date?
    @Published var isFetchingContestCalendar: Bool = false
    @Published var dxpeditionEntries: [DXpeditionEntry] = []
    @Published var dxpeditionStatus: String = "DXpedition watch not loaded yet"
    @Published var dxpeditionLastUpdated: Date?
    @Published var isFetchingDXpeditions: Bool = false
    
    // Row Selection State
    @Published var selectedRecordIDs: Set<UUID> = []
    
    // Email, SMTP & Enrichment States
    @Published var isEnriching: Bool = false
    private var enrichmentTask: Task<Void, Never>? = nil
    private var sdrControlSyncTimer: Timer?
    private var isSDRControlSyncRunning = false
    private var externalADIFSyncTimer: Timer?
    private var isExternalADIFSyncRunning = false
    private var qrzEmailBackfillTimer: Timer?
    private var qrzEmailBackfillBatchNumber = 0
    private var isQRZEmailBackfillRunning = false
    private var hamqthSessionID: String?
    
    @Published var showEmailComposer: Bool = false
    @Published var showIncomingEmailComposer: Bool = false
    @Published var showSMTPSettings: Bool = false
    @Published var selectedEmailCallsign: String = ""
    @Published var selectedEmailAddress: String = ""
    @Published var selectedEmailQSO: QSORecordModel? = nil
    @Published var selectedEmailTemplate: String? = nil
    @Published var selectedEmailUnconfirmedQSOs: [QSORecordModel] = []
    @Published var selectedEmailIncomingRequest: QRZIncomingConfirmation? = nil
    @Published var incomingEmailDraftNotice: String = ""
    @Published var emailHistory: [EmailHistoryEntry] = []
    @Published var showQSLCardComposer: Bool = false
    @Published var selectedQSLCardQSO: QSORecordModel? = nil
    @Published var isSendingBatchMail: Bool = false
    @Published var batchMailStatus: String = ""

    func openQRZRankCongratulationsEmailComposer(for record: QSORecordModel) {
        let email = record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            alertTitle = "Email Address Needed"
            alertMessage = "Enrich this contact first, then YAAM can prepare a QRZ congratulations and confirmation email."
            showAlert = true
            return
        }

        selectedEmailCallsign = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        selectedEmailAddress = email
        selectedEmailQSO = record
        selectedEmailTemplate = "QRZ Rank Congratulations & QSL"
        selectedEmailUnconfirmedQSOs = []
        selectedEmailIncomingRequest = nil
        showEmailComposer = true
    }
    
    // QRZ Rank & Login States
    @Published var isFetchingRank: Bool = false
    @Published var qrzRankData: QRZRankResponse? = nil
    @Published var qrzComparisonRankData: [QRZRankResponse] = []
    @Published var leaderboardSearchCallsign: String = ""
    @Published var ownerRankData: QRZRankResponse? = nil
    @Published var trackedRankCallsigns: [String] = []
    @Published var rankHistorySnapshots: [QRZRankHistorySnapshot] = []
    @Published var isRefreshingRankHistory: Bool = false
    @Published var rankHistoryStatus: String = ""
    @Published var rankServiceStatus: String = ""
    @Published private(set) var rankDailyQuota = QRZRankDailyQuota()
    @Published private(set) var rankServerQuota: QRZRankAPIQuota?
    @Published var isDailyRankBackfillRunning: Bool = false
    @Published var dailyRankBackfillStatus: String = ""
    @Published var dailyRankBackfillCompleted: Int = 0
    @Published var dailyRankBackfillTotal: Int = 0
    @Published var qrzAwardSummaries: [QRZAwardSummary] = []
    @Published var isFetchingQRZAwards: Bool = false
    @Published var qrzAwardsStatus: String = ""
    @Published var qrzAwardsLastUpdated: Date? = nil
    @Published var qrzIncomingRequests: [QRZIncomingConfirmation] = []
    @Published var isFetchingQRZIncoming = false
    @Published var incomingEmailLookupCallsign: String? = nil
    @Published var qrzIncomingStatus = "No QRZ incoming requests loaded"
    @Published var showQRZIncomingSheet = false
    @Published var showConfirmationReconciliationSheet = false
    @Published var confirmationReconciliation = ConfirmationReconciliationSnapshot.empty
    @Published var showLogAssistantSheet = false

    private let trackedRankCallsignsKey = "trackedRankCallsigns"
    private let qrzRankHistorySnapshotsKey = "qrzRankHistorySnapshots"
    private let qrzRankDailyQuotaKey = "qrzRankDailyQuota.v1"

    @Published var showQRZLoginSheet: Bool = false
    @Published var showClubLogLoginSheet: Bool = false
    
    // Search & Smart Sorting States
    @Published var searchText: String = "" {
        didSet {
            filteredRecordsCache = nil
            filteredChronologicalOrdinals.removeAll(keepingCapacity: true)
        }
    }
    @Published var logSearchMode: LogSearchMode = .quick {
        didSet {
            filteredRecordsCache = nil
            filteredChronologicalOrdinals.removeAll(keepingCapacity: true)
        }
    }
    @Published var sortHeader: String? = "QSO_DATE" {
        didSet {
            filteredRecordsCache = nil
            filteredChronologicalOrdinals.removeAll(keepingCapacity: true)
        }
    }
    @Published var sortAscending: Bool = false {
        didSet {
            filteredRecordsCache = nil
            filteredChronologicalOrdinals.removeAll(keepingCapacity: true)
        }
    }
    
    // Workspace File Tracking
    @Published var loadedFileURL: URL? = nil
    @Published var loadedFileName: String = ""
    @Published var isMasterMode: Bool = true

    var logbookDatabase: LogbookDatabase?
    @Published var stationProfiles: [StationProfile] = []
    @Published var activeStationProfileID: UUID?
    @Published var backupSnapshots: [BackupSnapshot] = []
    @Published var recentDatabaseAuditEvents: [DatabaseAuditEvent] = []
    @Published var databaseStatus: String = "Preparing protected local logbook..."
    @Published var pendingImportReview: PendingImportReview?
    @Published var showImportReviewSheet: Bool = false
    @Published var duplicateReview: DuplicateReview?
    @Published var showDuplicateReviewSheet: Bool = false
    @Published var isAnalyzingDuplicates: Bool = false
    let workspaceSaveQueue = DispatchQueue(label: "app.yaam.workspace-save", qos: .utility)
    var lastDestructiveCheckpointDate: Date?
    var loadedWorkspaceProfileID: UUID?

    // Operator Desk
    @Published var operatorDeskSection = min(9, max(0, UserDefaults.standard.integer(forKey: "operatorDeskSection")))
    @Published var quickLogDraft = QuickLogDraft()
    @Published var quickLogLookup: CallsignLookupResult?
    @Published var quickLogAssessment = QuickLogAssessment()
    @Published var isLookingUpQuickLogCallsign = false
    @Published var quickLogStatus = "Ready"
    @Published var quickLogLastSaved: QSORecordModel?
    @Published var wsjtxPendingQSOs: [WSJTXPendingQSO] = []
    @Published var currentContestSession: ContestSession?
    @Published var contestStatus = "No active contest session"
    @Published var qslQueueJobs: [QSLQueueJob] = []
    @Published var qslHubStatus = "QSL queue ready"
    @Published var isProcessingQSLQueue = false
    @Published var awardProgress: [AwardProgress] = []
    @Published var awardClaims: [AwardClaim] = []
    @Published var portableActivitySummaries: [PortableActivitySummary] = []
    @Published var awardEngineStatus = "Local award engine ready"
    @Published var cloudSyncStatus = "Cloud folder not configured"
    @Published var cloudSyncLastRun: Date?
    @Published var isCloudSyncRunning = false
    @Published var mobileCompanionStatus = "Mobile companion is off"
    @Published var mobileCompanionURL = ""
    @Published var isMobileCompanionRunning = false
    let callsignLookupService = CallsignLookupService()
    let qslHubClient = QSLHubClient()
    let cloudFileCoordinator = CloudFileCoordinator()
    let mobileCompanionServer = MobileCompanionServer()
    let dxClusterClient = DXClusterClient()
    let rigControlClient = RigControlClient()
    let wsjtxListener = WSJTXListener()
    let icomNetworkRadio = IcomNetworkRadio()
    let ft8Engine = FT8EngineService()
    var operatorFeatureCancellables: Set<AnyCancellable> = []
    var cloudSyncTimer: Timer?

    // Unified synchronization health
    @Published var syncServiceStatuses: [SyncServiceStatus] = SyncSource.allCases.map { SyncServiceStatus(source: $0) }
    @Published var syncHistory: [SyncHistoryEntry] = []
    @Published var isUnifiedSyncRunning = false
    var unifiedSyncTimer: Timer?
    var syncStartedAt: [SyncSource: Date] = [:]
    
    @Published private(set) var qsoRecordsRevision = 0
    private var filteredRecordsCache: [QSORecordModel]?
    private var filteredChronologicalOrdinals: [UUID: Int] = [:]
    private var availableCountriesCache: [String]?
    private var confirmationOpportunityIndexCache: ConfirmationOpportunityIndex?
    private var rankCandidateCacheDay = ""
    private var rankCandidateCacheRevision = -1
    private var rankCandidateCacheAvailable = 0

    @Published var tableHeaders: [String] = []
    @Published var qsoRecords: [QSORecordModel] = [] {
        didSet {
            qsoRecordsRevision &+= 1
            filteredRecordsCache = nil
            filteredChronologicalOrdinals.removeAll(keepingCapacity: true)
            availableCountriesCache = nil
            confirmationOpportunityIndexCache = nil
        }
    }
    @Published var recentLogFiles: [URL] = []
    @Published var selectedTab: Int = min(5, max(0, UserDefaults.standard.integer(forKey: "selectedTab")))
    @Published var convertSource: Int = 0 // 0: External File, 1: YAAM Database
    @Published var convertDatabaseProfileID: UUID? = nil // nil: All Station Profiles / Full Database
    
    // Persistent Local Confirmations Memory Database Cache
    private var localConfirmedKeys: Set<String> = []
    
    // Filter & Modal Sheet States
    @Published var filterCriteria = FilterCriteria() {
        didSet {
            filteredRecordsCache = nil
            filteredChronologicalOrdinals.removeAll(keepingCapacity: true)
        }
    }
    @Published var showFilterSheet: Bool = false
    @Published var showStatsSheet: Bool = false
    
    // Global User Alerts
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""

    @Published var showAboutSheet: Bool = false

    override init() {
        super.init()
        migrateEmailTemplateReferences()
        configurePersistentStorage()
        loadMasterLogbook()
        loadRankHistory()
        loadQRZIncomingCache()
        loadDailyRankQuota()
        loadPersistentConfirmationCache()
        loadRecentLogsFromDatabase()
        loadEmailHistory()
        configureExternalADIFAutoSync()
        configureSDRControlPeriodicSync()
        configureQRZEmailBackfillTimer()
        loadSyncCenterState()
        configureUnifiedSyncSchedule()
        loadContestSession()
        loadQSLHubState()
        loadConnectivityState()
        loadContestCalendarCache()
        loadDXpeditionCache()
        loadQRZAwardsCache()
        configureOperatorFeatureBridges()
        DispatchQueue.main.async {
            CredentialVault.prewarm()
            CredentialVault.migrateLegacyCredentials()
            self.restoreSavedClubLogSessionCookies()
        }
    }

    private func migrateEmailTemplateReferences() {
        let key = "qslCardDeliveryEmailBody"
        guard let storedTemplate = UserDefaults.standard.string(forKey: key), storedTemplate.contains("yaam.app") else { return }

        let updatedTemplate = storedTemplate
            .replacingOccurrences(of: "https://yaam.app", with: "https://github.com/fact0real/yaam")
            .replacingOccurrences(of: "yaam.app", with: "YAAM")
        UserDefaults.standard.set(updatedTemplate, forKey: key)
    }

    func playActivitySound(_ sound: ActivitySound) {
        DispatchQueue.main.async {
            let soundNames: [NSSound.Name]
            switch sound {
            case .success:
                soundNames = [NSSound.Name("Glass"), NSSound.Name("Ping"), NSSound.Name("Hero")]
            case .failure:
                soundNames = [NSSound.Name("Basso"), NSSound.Name("Funk"), NSSound.Name("Sosumi")]
            case .notice:
                soundNames = [NSSound.Name("Pop"), NSSound.Name("Tink"), NSSound.Name("Submarine")]
            }

            if let systemSound = soundNames.compactMap({ NSSound(named: $0) }).first {
                systemSound.play()
            } else {
                NSSound.beep()
            }
        }
    }

    var availableCountries: [String] {
        if let availableCountriesCache { return availableCountriesCache }
        let countries = Set(qsoRecords.compactMap { $0["COUNTRY"].isEmpty ? nil : $0["COUNTRY"] })
        let result = Array(countries).sorted()
        availableCountriesCache = result
        return result
    }

    var confirmationOpportunityIndex: ConfirmationOpportunityIndex {
        if let confirmationOpportunityIndexCache {
            return confirmationOpportunityIndexCache
        }

        let index = ConfirmationOpportunityIndex(records: qsoRecords)
        confirmationOpportunityIndexCache = index
        return index
    }

    var activeModesCount: Int {
        Set(qsoRecords.compactMap { $0["MODE"].isEmpty ? nil : $0["MODE"] }).count
    }

    var uniqueCallsignCount: Int {
        Set(qsoRecords.compactMap { $0["CALL"].isEmpty ? nil : $0["CALL"].uppercased() }).count
    }

    var totalConfirmedCount: Int {
        qsoRecords.filter { $0.isConfirmed }.count
    }

    var totalUnconfirmedCount: Int {
        qsoRecords.count - totalConfirmedCount
    }

    var bandStatistics: [BandStatModel] {
        guard !qsoRecords.isEmpty else { return [] }
        
        var bandMap: [String: (total: Int, confirmed: Int, countries: Set<String>, confirmedCountries: Set<String>)] = [:]
        let total = Double(qsoRecords.count)
        
        for record in qsoRecords {
            let band = record["BAND"].isEmpty ? "UNKNOWN" : record["BAND"].uppercased()
            let country = record["COUNTRY"]
            let confirmed = record.isConfirmed
            
            if bandMap[band] == nil {
                bandMap[band] = (total: 0, confirmed: 0, countries: Set<String>(), confirmedCountries: Set<String>())
            }
            bandMap[band]?.total += 1
            if confirmed { bandMap[band]?.confirmed += 1 }
            if !country.isEmpty { bandMap[band]?.countries.insert(country) }
            if confirmed && !country.isEmpty { bandMap[band]?.confirmedCountries.insert(country) }
        }
        
        return bandMap.map { (bandKey, data) in
            let pct = (Double(data.total) / total) * 100.0
            let unconf = data.total - data.confirmed
            return BandStatModel(
                band: bandKey,
                qsoCount: data.total,
                confirmedCount: data.confirmed,
                unconfirmedCount: unconf,
                dxccCount: data.countries.count,
                confirmedDxccCount: data.confirmedCountries.count,
                percentage: pct
            )
        }.sorted { $0.qsoCount > $1.qsoCount }
    }

    var countryStatistics: [CountryStatModel] {
        guard !qsoRecords.isEmpty else { return [] }
        
        var countryMap: [String: (total: Int, confirmed: Int)] = [:]
        
        for record in qsoRecords {
            let c = record["COUNTRY"].isEmpty ? "Unknown" : record["COUNTRY"]
            if countryMap[c] == nil { countryMap[c] = (total: 0, confirmed: 0) }
            countryMap[c]?.total += 1
            if record.isConfirmed { countryMap[c]?.confirmed += 1 }
        }
        
        return countryMap.map { (cName, data) in
            let unconf = data.total - data.confirmed
            return CountryStatModel(country: cName, flag: countryToFlag(cName), qsoCount: data.total, confirmedCount: data.confirmed, unconfirmedCount: unconf)
        }.sorted { $0.qsoCount > $1.qsoCount }
    }

    var unconfirmedBandCountryStatistics: [UnconfirmedBandCountryStatModel] {
        guard !qsoRecords.isEmpty else { return [] }

        var bandCountryMap: [String: [String: (total: Int, confirmed: Int)]] = [:]

        for record in qsoRecords {
            let band = record["BAND"].isEmpty ? "UNKNOWN" : record["BAND"].uppercased()
            let country = record["COUNTRY"].isEmpty ? "Unknown" : record["COUNTRY"]

            if bandCountryMap[band] == nil {
                bandCountryMap[band] = [:]
            }
            if bandCountryMap[band]?[country] == nil {
                bandCountryMap[band]?[country] = (total: 0, confirmed: 0)
            }

            bandCountryMap[band]?[country]?.total += 1
            if record.isConfirmed {
                bandCountryMap[band]?[country]?.confirmed += 1
            }
        }

        return bandCountryMap.compactMap { band, countryMap in
            let countries = countryMap.compactMap { country, data -> UnconfirmedCountryStatModel? in
                guard data.total > 0, data.confirmed == 0 else { return nil }
                return UnconfirmedCountryStatModel(country: country, qsoCount: data.total)
            }
            .sorted {
                if $0.qsoCount == $1.qsoCount {
                    return $0.country < $1.country
                }
                return $0.qsoCount > $1.qsoCount
            }

            guard !countries.isEmpty else { return nil }
            return UnconfirmedBandCountryStatModel(band: band, countries: countries)
        }
        .sorted { $0.band.localizedStandardCompare($1.band) == .orderedAscending }
    }

    var callsignsWithNoConfirmedQSOs: [UnconfirmedCallsignStatModel] {
        let grouped = Dictionary(grouping: qsoRecords) { record in
            record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }

        return grouped.compactMap { callsign, records in
            guard !callsign.isEmpty, !records.contains(where: { $0.isConfirmed }) else { return nil }

            let countries = Set(records.map { $0["COUNTRY"] }.filter { !$0.isEmpty }).sorted().joined(separator: ", ")
            let bands = Set(records.map { $0["BAND"].uppercased() }.filter { !$0.isEmpty }).sorted().joined(separator: ", ")
            let email = records.first { !$0["EMAIL"].isEmpty }?["EMAIL"] ?? ""

            return UnconfirmedCallsignStatModel(
                callsign: callsign,
                qsoCount: records.count,
                countries: countries,
                bands: bands,
                email: email
            )
        }
        .sorted {
            if $0.qsoCount == $1.qsoCount {
                return $0.callsign < $1.callsign
            }
            return $0.qsoCount > $1.qsoCount
        }
    }

    var filteredRecords: [QSORecordModel] {
        if let filteredRecordsCache { return filteredRecordsCache }
        var records = qsoRecords
        
        if filterCriteria.isActive {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            
            let startStr = formatter.string(from: filterCriteria.startDate)
            let endStr = formatter.string(from: filterCriteria.endDate)
            
            records = records.filter { record in
                if filterCriteria.useDate {
                    let qsoDate = record["QSO_DATE"]
                    if qsoDate < startStr || qsoDate > endStr { return false }
                }
                if filterCriteria.useBand && filterCriteria.band != "All" {
                    if record["BAND"].uppercased() != filterCriteria.band.uppercased() { return false }
                }
                if filterCriteria.useMode && filterCriteria.mode != "All" {
                    let recMode = record["MODE"].uppercased()
                    let recSubmode = record["SUBMODE"].uppercased()
                    let target = filterCriteria.mode.uppercased()
                    if recMode != target && recSubmode != target { return false }
                }
                if filterCriteria.useCallsign, !filterCriteria.callsign.isEmpty {
                    if !record["CALL"].localizedCaseInsensitiveContains(filterCriteria.callsign.trimmingCharacters(in: .whitespaces)) { return false }
                }
                if filterCriteria.useOperator, !filterCriteria.operatorStation.isEmpty {
                    let op = record["OPERATOR"].isEmpty ? record["STATION_CALLSIGN"] : record["OPERATOR"]
                    if !op.localizedCaseInsensitiveContains(filterCriteria.operatorStation.trimmingCharacters(in: .whitespaces)) { return false }
                }
                if filterCriteria.useZone, !filterCriteria.zone.isEmpty {
                    if record["CQZ"] != filterCriteria.zone.trimmingCharacters(in: .whitespaces) { return false }
                }
                if filterCriteria.useCountry, !filterCriteria.selectedCountries.isEmpty {
                    if !filterCriteria.selectedCountries.contains(record["COUNTRY"]) { return false }
                }
                if filterCriteria.useQSLSent {
                    let val = record["QSL_SENT"].uppercased()
                    if filterCriteria.qslSent == "Blank" && !val.isEmpty { return false }
                    if filterCriteria.qslSent != "Blank" && val != filterCriteria.qslSent { return false }
                }
                if filterCriteria.useQSLRcvd {
                    let val = record["QSL_RCVD"].uppercased()
                    if filterCriteria.qslRcvd == "Blank" && !val.isEmpty { return false }
                    if filterCriteria.qslRcvd != "Blank" && val != filterCriteria.qslRcvd { return false }
                }
                if filterCriteria.useConfirmation {
                    let wantConfirmed = (filterCriteria.confirmationState == "Confirmed (Y)")
                    if wantConfirmed != record.isConfirmed { return false }
                }
                if filterCriteria.useContinent, !filterCriteria.selectedContinents.isEmpty {
                    if !filterCriteria.selectedContinents.contains(record["CONT"].uppercased()) { return false }
                }
                return true
            }
        }
        
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let mode = logSearchMode
            let text = searchText
            records = records.filter { record in
                LogSearchEngine.matches(record.searchDocument, query: text, mode: mode)
            }
        }

        if filterCriteria.isActive {
            let chronologicalRecords = records.sorted { lhs, rhs in
                let left = "\(lhs["QSO_DATE"])\(lhs["TIME_ON"])"
                let right = "\(rhs["QSO_DATE"])\(rhs["TIME_ON"])"
                if left != right { return left > right }
                return lhs.index > rhs.index
            }
            filteredChronologicalOrdinals = Dictionary(
                uniqueKeysWithValues: chronologicalRecords.enumerated().map { ($0.element.id, $0.offset + 1) }
            )
        } else {
            filteredChronologicalOrdinals.removeAll(keepingCapacity: true)
        }
        
        if let sortKey = sortHeader {
            records.sort { r1, r2 in
                let v1 = r1[sortKey].trimmingCharacters(in: .whitespaces)
                let v2 = r2[sortKey].trimmingCharacters(in: .whitespaces)

                if sortKey == "QSO_DATE" {
                    let t1 = r1["TIME_ON"].trimmingCharacters(in: .whitespaces)
                    let t2 = r2["TIME_ON"].trimmingCharacters(in: .whitespaces)
                    let first = "\(v1)\(t1)"
                    let second = "\(v2)\(t2)"
                    guard first != second else { return false }
                    return sortAscending ? first < second : first > second
                } else if let d1 = Double(v1), let d2 = Double(v2) {
                    guard d1 != d2 else { return false }
                    return sortAscending ? d1 < d2 : d1 > d2
                } else if sortKey == "TIME_ON" || sortKey == "TIME_OFF" {
                    guard v1 != v2 else { return false }
                    return sortAscending ? v1 < v2 : v1 > v2
                } else {
                    let comparison = v1.localizedCaseInsensitiveCompare(v2)
                    guard comparison != .orderedSame else { return false }
                    return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
                }
            }
        }

        filteredRecordsCache = records
        return records
    }

    func filteredChronologicalOrdinal(for recordID: UUID) -> Int? {
        guard filterCriteria.isActive else { return nil }
        if filteredRecordsCache == nil {
            _ = filteredRecords
        }
        return filteredChronologicalOrdinals[recordID]
    }

    func toggleRecordSelection(_ id: UUID) {
        if selectedRecordIDs.contains(id) {
            selectedRecordIDs.remove(id)
        } else {
            selectedRecordIDs.insert(id)
        }
    }
    
    func clearSelection() {
        selectedRecordIDs.removeAll()
    }
    
    func enrichSelectedRecords() {
        guard !selectedRecordIDs.isEmpty else { return }

        let selectedCallsigns = Set(qsoRecords.filter { selectedRecordIDs.contains($0.id) }
            .compactMap { $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty })
        
        if !selectedCallsigns.isEmpty {
            enrichLogData(targetCallsigns: selectedCallsigns)
        }
    }

    func toggleSort(for header: String) {
        if sortHeader == header {
            if sortAscending {
                sortAscending = false
            } else {
                sortHeader = nil
                sortAscending = true
            }
        } else {
            sortHeader = header
            sortAscending = true
        }
    }

    func appendLog(_ text: String) {
        DispatchQueue.main.async {
            self.logText += "\(text)\n"
            let maxLogLines = 800
            let lines = self.logText.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > maxLogLines {
                self.logText = lines.suffix(maxLogLines).joined(separator: "\n") + "\n"
            }
        }
    }

    func clearActivityLog() {
        DispatchQueue.main.async {
            self.logText = "YAAM activity log cleared.\n"
        }
    }
    
    func saveQRZSessionCookies(_ cookies: [HTTPCookie]) {
        let cookieHeader = QRZSessionStore.save(cookies: cookies)
        if cookieHeader.isEmpty {
            appendLog("⚠️ QRZ session save requested, but no qrz.com cookies were found.")
        } else {
            QRZSessionStore.restoreToWebKit()
            appendLog("✅ QRZ session saved for future app launches.")
        }
    }

    func saveClubLogSessionCookies(_ cookies: [HTTPCookie]) {
        let cookieHeader = ClubLogSessionStore.save(cookies: cookies)
        if cookieHeader.isEmpty {
            appendLog("⚠️ Club Log session save requested, but no clublog.org cookies found.")
        } else {
            ClubLogSessionStore.restoreToWebKit()
            appendLog("✅ Club Log session saved securely in Keychain.")
        }
    }

    func restoreSavedClubLogSessionCookies() {
        guard ClubLogSessionStore.hasSavedSession() else { return }
        ClubLogSessionStore.restoreToWebKit()
        appendLog("🔑 Restored saved Club Log session cookies.")
    }

    func restoreSavedQRZSessionCookies() {
        guard QRZSessionStore.hasSavedSession() else { return }
        QRZSessionStore.restoreToWebKit()
        appendLog("🔑 Restored saved QRZ session cookies.")
    }

    func forceQRZReLogin() {
        restoreSavedQRZSessionCookies()
        appendLog("🔑 Opening QRZ.com Authenticator...")
        showQRZLoginSheet = true
    }

    func fetchQRZAwards() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.fetchQRZAwards()
            }
            return
        }

        let username = UserDefaults.standard.string(forKey: "qrzUsername")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = CredentialVault.value(for: .qrzPassword)
        guard !username.isEmpty, !password.isEmpty else {
            qrzAwardsStatus = "Enter QRZ username and password in Settings first."
            appendLog("QRZ Awards skipped: missing QRZ username/password in Settings.")
            return
        }

        isFetchingQRZAwards = true
        qrzAwardsStatus = "Opening QRZ Logbook Awards..."
        appendLog("QRZ Awards: fetching award progress from QRZ Logbook.")

        Task { @MainActor in
            let result = await QRZAwardsScraper.shared.fetchAwards(username: username, password: password)
            if !result.awards.isEmpty {
                self.qrzAwardSummaries = result.awards
                if let data = try? JSONEncoder().encode(result.awards) {
                    UserDefaults.standard.set(data, forKey: "cachedQRZAwards")
                }
            }
            self.qrzAwardsStatus = result.message
            self.qrzAwardsLastUpdated = result.awards.isEmpty ? self.qrzAwardsLastUpdated : Date()
            self.isFetchingQRZAwards = false
            self.appendLog("QRZ Awards: \(result.message)")
        }
    }

    private func loadQRZAwardsCache() {
        if let data = UserDefaults.standard.data(forKey: "cachedQRZAwards"),
           let cached = try? JSONDecoder().decode([QRZAwardSummary].self, from: data) {
            self.qrzAwardSummaries = cached
        }
    }
    
    func fetchQRZLeaderboard(for searchedCallsign: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.fetchQRZLeaderboard(for: searchedCallsign)
            }
            return
        }

        let ownerCall = currentStationCallsign
        let targetCall = searchedCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        guard !targetCall.isEmpty else { return }
        let credentials = rankServiceCredentials()
        
        isFetchingRank = true
        rankServiceStatus = "Refreshing QRZ rankings..."
        
        let group = DispatchGroup()
        
        if ownerRankData == nil || ownerRankData?.callsign?.uppercased() != ownerCall {
            group.enter()
            fetchSingleRank(callsign: ownerCall, credentials: credentials) { [weak self] result in
                Task { @MainActor in
                    if case .success(let response) = result {
                        self?.ownerRankData = response
                        self?.saveRankResponseSnapshot(response)
                    }
                    group.leave()
                }
            }
        }
        
        group.enter()
        fetchSingleRank(callsign: targetCall, credentials: credentials) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let response):
                    self?.qrzRankData = response
                    self?.rankServiceStatus = "Live QRZ ranking loaded."
                    self?.saveRankResponseSnapshot(response)
                case .failure(let error):
                    if let cached = self?.cachedRankResponse(for: targetCall) {
                        self?.qrzRankData = cached
                        self?.rankServiceStatus = "Showing the last saved ranking. \(error.localizedDescription)"
                    } else {
                        self?.qrzRankData = .placeholder(callsign: targetCall)
                        self?.rankServiceStatus = error.localizedDescription
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.isFetchingRank = false
            if let target = self?.qrzRankData?.callsign {
                self?.appendLog("Leaderboard Comparison loaded: \(ownerCall) VS \(target)")
            }
        }
    }

    func fetchQRZLeaderboardComparisons(for callsigns: [String]) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.fetchQRZLeaderboardComparisons(for: callsigns)
            }
            return
        }

        let ownerCall = currentStationCallsign
        var seen = Set<String>()
        let targets = callsigns.compactMap { raw -> String? in
            let callsign = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !callsign.isEmpty, callsign != ownerCall, seen.insert(callsign).inserted else { return nil }
            return callsign
        }.prefix(8)

        guard !targets.isEmpty else { return }
        let credentials = rankServiceCredentials()

        isFetchingRank = true
        rankServiceStatus = "Refreshing \(targets.count) QRZ rankings..."

        let group = DispatchGroup()
        var results = Dictionary(uniqueKeysWithValues: targets.map { callsign in
            (callsign, cachedRankResponse(for: callsign) ?? .placeholder(callsign: callsign))
        })
        var failures: [QRZRankFetchFailure] = []
        let lock = NSLock()

        if ownerRankData == nil || ownerRankData?.callsign?.uppercased() != ownerCall {
            group.enter()
            fetchSingleRank(callsign: ownerCall, credentials: credentials) { [weak self] result in
                Task { @MainActor in
                    if case .success(let response) = result {
                        self?.ownerRankData = response
                        self?.saveRankResponseSnapshot(response)
                    }
                    group.leave()
                }
            }
        }

        for callsign in targets {
            group.enter()
            fetchSingleRank(callsign: callsign, credentials: credentials) { result in
                switch result {
                case .success(let response):
                    lock.lock()
                    results[callsign] = response
                    lock.unlock()
                case .failure(let error):
                    lock.lock()
                    failures.append(error)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.qrzComparisonRankData = targets.compactMap { results[$0] }
            self.qrzRankData = self.qrzComparisonRankData.first
            self.qrzComparisonRankData.filter(\.hasRankingValue).forEach { self.saveRankResponseSnapshot($0) }
            self.isFetchingRank = false
            if let firstFailure = failures.first {
                let cachedCount = self.qrzComparisonRankData.filter(\.hasRankingValue).count
                self.rankServiceStatus = cachedCount > 0
                    ? "Showing \(cachedCount) saved/live rankings. \(firstFailure.localizedDescription)"
                    : firstFailure.localizedDescription
            } else {
                self.rankServiceStatus = "Loaded \(results.values.filter(\.hasRankingValue).count) live QRZ rankings."
            }
            self.appendLog("Leaderboard multi comparison loaded for \(results.values.filter(\.hasRankingValue).count) callsigns; \(failures.count) failed.")
        }
    }

    func refreshOwnerQRZRankIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshOwnerQRZRankIfNeeded()
            }
            return
        }

        let ownerCall = currentStationCallsign
        guard !ownerCall.isEmpty else { return }
        guard ownerRankData == nil || ownerRankData?.callsign?.uppercased() != ownerCall else { return }

        fetchSingleRank(callsign: ownerCall, credentials: rankServiceCredentials()) { [weak self] result in
            Task { @MainActor in
                if case .success(let response) = result {
                    self?.ownerRankData = response
                    self?.saveRankResponseSnapshot(response)
                }
            }
        }
    }

    func addTrackedRankCallsigns(_ callsigns: [String]) {
        let ownerCall = currentStationCallsign
        let normalized = callsigns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && $0 != ownerCall }

        guard !normalized.isEmpty else { return }

        let merged = Array(Set(trackedRankCallsigns + normalized)).sorted()
        trackedRankCallsigns = Array(merged.prefix(8))
        saveTrackedRankCallsigns()
        hydrateLeaderboardFromSavedRankHistory()
        refreshTrackedRankHistoryIfNeeded(force: true)
    }

    func removeTrackedRankCallsign(_ callsign: String) {
        let normalized = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        trackedRankCallsigns.removeAll { $0 == normalized }
        saveTrackedRankCallsigns()
        hydrateLeaderboardFromSavedRankHistory()
    }

    func refreshTrackedRankHistoryIfNeeded(force: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshTrackedRankHistoryIfNeeded(force: force)
            }
            return
        }

        let ownerCall = currentStationCallsign
        let allCallsigns = Array(Set(([ownerCall] + trackedRankCallsigns).filter { !$0.isEmpty && $0 != "DEFAULT" })).sorted()
        guard !allCallsigns.isEmpty else {
            rankHistoryStatus = "Set your station callsign first."
            return
        }

        let today = QRZRankHistorySnapshot.dayKey(for: Date())
        let missingToday = allCallsigns.filter { callsign in
            !rankHistorySnapshots.contains { snapshot in
                snapshot.callsign == callsign && QRZRankHistorySnapshot.dayKey(for: snapshot.date) == today
            }
        }
        let targets = force ? allCallsigns : missingToday

        guard !targets.isEmpty else {
            rankHistoryStatus = "Rank history is current for today."
            return
        }
        let credentials = rankServiceCredentials()

        isRefreshingRankHistory = true
        rankHistoryStatus = "Refreshing \(targets.count) QRZ rank snapshots..."

        let group = DispatchGroup()
        var snapshots: [QRZRankHistorySnapshot] = []
        var failures: [QRZRankFetchFailure] = []
        let lock = NSLock()

        for callsign in targets {
            group.enter()
            fetchSingleRank(callsign: callsign, credentials: credentials) { result in
                switch result {
                case .success(let response):
                    let snapshot = QRZRankHistorySnapshot(response: response)
                    if !snapshot.callsign.isEmpty {
                        lock.lock()
                        snapshots.append(snapshot)
                        lock.unlock()
                    }
                case .failure(let error):
                    lock.lock()
                    failures.append(error)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            for snapshot in snapshots {
                self.upsertRankHistorySnapshot(snapshot)
                if snapshot.callsign == ownerCall {
                    self.ownerRankData = QRZRankResponse(snapshot: snapshot)
                }
            }
            self.rankHistorySnapshots.sort { $0.date < $1.date }
            self.saveRankHistorySnapshots()
            self.hydrateLeaderboardFromSavedRankHistory()
            self.isRefreshingRankHistory = false
            if let firstFailure = failures.first {
                self.rankHistoryStatus = snapshots.isEmpty
                    ? "Saved rivals are still available offline. \(firstFailure.localizedDescription)"
                    : "Saved \(snapshots.count) snapshots; \(failures.count) could not refresh. \(firstFailure.localizedDescription)"
                self.rankServiceStatus = self.rankHistoryStatus
            } else {
                self.rankHistoryStatus = "Saved \(snapshots.count) rank snapshots for today."
                self.rankServiceStatus = self.rankHistoryStatus
            }
            self.appendLog("QRZ rank history refreshed: \(snapshots.count) snapshots saved.")
        }
    }

    func rankTrendSeries(metric: RankHistoryMetric) -> [RankTrendSeries] {
        let ownerCall = currentStationCallsign
        let ownerSnapshots = rankHistorySnapshots
            .filter { $0.callsign == ownerCall }
            .sorted { $0.date < $1.date }
        let ownerByDay = Dictionary(
            ownerSnapshots.map { (QRZRankHistorySnapshot.dayKey(for: $0.date), $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        func makeSeries(callsign: String, isOwner: Bool) -> RankTrendSeries {
            let snapshots = rankHistorySnapshots
                .filter { $0.callsign == callsign }
                .sorted { $0.date < $1.date }
            let points = snapshots.compactMap { snapshot -> RankTrendPoint? in
                guard let rank = snapshot.rank(for: metric) else { return nil }
                return RankTrendPoint(
                    date: snapshot.date,
                    label: shortRankHistoryDateFormatter.string(from: snapshot.date),
                    rank: rank
                )
            }
            let latestRank = points.last?.rank
            let latestMovement = points.count >= 2
                ? points[points.count - 2].rank - points[points.count - 1].rank
                : nil

            let comparisonGaps: [Int] = isOwner ? [] : snapshots.compactMap { snapshot in
                let day = QRZRankHistorySnapshot.dayKey(for: snapshot.date)
                guard let ownerRank = ownerByDay[day]?.rank(for: metric),
                      let rivalRank = snapshot.rank(for: metric) else { return nil }
                return rivalRank - ownerRank
            }
            let latestGap = comparisonGaps.last
            let latestGapMovement = comparisonGaps.count >= 2
                ? comparisonGaps[comparisonGaps.count - 1] - comparisonGaps[comparisonGaps.count - 2]
                : nil

            return RankTrendSeries(
                callsign: callsign,
                countryIso: snapshots.last?.countryIso,
                isOwner: isOwner,
                latestRank: latestRank,
                latestGap: latestGap,
                latestMovement: latestMovement,
                latestGapMovement: latestGapMovement,
                points: points
            )
        }

        var result: [RankTrendSeries] = []
        if !ownerCall.isEmpty, ownerCall != "DEFAULT" {
            result.append(makeSeries(callsign: ownerCall, isOwner: true))
        }
        result.append(contentsOf: trackedRankCallsigns.map { makeSeries(callsign: $0, isOwner: false) })
        return result
    }

    private func loadRankHistory() {
        var seen = Set<String>()
        trackedRankCallsigns = (UserDefaults.standard.stringArray(forKey: trackedRankCallsignsKey) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(8)
            .map { $0 }
        if let data = UserDefaults.standard.data(forKey: qrzRankHistorySnapshotsKey),
           let snapshots = try? JSONDecoder().decode([QRZRankHistorySnapshot].self, from: data) {
            rankHistorySnapshots = snapshots.sorted { $0.date < $1.date }
        }
        if !trackedRankCallsigns.isEmpty {
            leaderboardSearchCallsign = trackedRankCallsigns.joined(separator: ", ")
        }
        hydrateLeaderboardFromSavedRankHistory()
    }

    private func saveTrackedRankCallsigns() {
        UserDefaults.standard.set(trackedRankCallsigns, forKey: trackedRankCallsignsKey)
    }

    private func saveRankHistorySnapshots() {
        if let data = try? JSONEncoder().encode(rankHistorySnapshots) {
            UserDefaults.standard.set(data, forKey: qrzRankHistorySnapshotsKey)
        }
    }

    private func upsertRankHistorySnapshot(_ snapshot: QRZRankHistorySnapshot) {
        let day = QRZRankHistorySnapshot.dayKey(for: snapshot.date)
        rankHistorySnapshots.removeAll {
            $0.callsign == snapshot.callsign && QRZRankHistorySnapshot.dayKey(for: $0.date) == day
        }
        rankHistorySnapshots.append(snapshot)
    }

    private func saveRankResponseSnapshot(_ response: QRZRankResponse) {
        guard response.hasRankingValue else { return }
        let snapshot = QRZRankHistorySnapshot(response: response)
        guard !snapshot.callsign.isEmpty else { return }
        let retainedCallsigns = Set(trackedRankCallsigns + [currentStationCallsign])
        guard retainedCallsigns.contains(snapshot.callsign) else { return }
        upsertRankHistorySnapshot(snapshot)
        rankHistorySnapshots.sort { $0.date < $1.date }
        saveRankHistorySnapshots()
    }

    private func cachedRankResponse(for callsign: String) -> QRZRankResponse? {
        let normalized = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return rankHistorySnapshots
            .filter { $0.callsign == normalized }
            .max(by: { $0.date < $1.date })
            .map(QRZRankResponse.init(snapshot:))
    }

    private func hydrateLeaderboardFromSavedRankHistory() {
        let ownerCall = currentStationCallsign
        if let cachedOwner = cachedRankResponse(for: ownerCall) {
            ownerRankData = cachedOwner
        }
        qrzComparisonRankData = trackedRankCallsigns.map { callsign in
            cachedRankResponse(for: callsign) ?? .placeholder(callsign: callsign)
        }
        qrzRankData = qrzComparisonRankData.first
        if !trackedRankCallsigns.isEmpty, rankServiceStatus.isEmpty {
            let cachedCount = qrzComparisonRankData.filter(\.hasRankingValue).count
            rankServiceStatus = cachedCount > 0
                ? "Restored \(trackedRankCallsigns.count) tracked rivals with \(cachedCount) saved rankings."
                : "Restored \(trackedRankCallsigns.count) tracked rivals. Refresh to load rankings."
            rankHistoryStatus = rankServiceStatus
        }
    }

    private var shortRankHistoryDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }

    var dailyRankRequestsRemaining: Int {
        guard let quota = rankServerQuota else { return Int.max }
        if quota.isUnlimited { return Int.max }
        if let remaining = quota.effectiveRemaining { return max(0, remaining) }
        return quota.allowsRequest ? Int.max : 0
    }

    var dailyRankBackfillCandidateCount: Int {
        let checkedDay = Self.adifDateFormatter.string(from: Date())
        if rankCandidateCacheDay != checkedDay || rankCandidateCacheRevision != qsoRecordsRevision {
            rankCandidateCacheAvailable = QRZRankBackfillPlanner.candidateCallsigns(
                from: qsoRecords,
                checkedDay: checkedDay,
                limit: Int.max,
                value: { record, field in record[field] }
            ).count
            rankCandidateCacheDay = checkedDay
            rankCandidateCacheRevision = qsoRecordsRevision
        }
        let serverRemaining = dailyRankRequestsRemaining
        return serverRemaining == Int.max
            ? rankCandidateCacheAvailable
            : min(rankCandidateCacheAvailable, serverRemaining)
    }

    private func loadDailyRankQuota() {
        if let data = UserDefaults.standard.data(forKey: qrzRankDailyQuotaKey),
           var savedQuota = try? JSONDecoder().decode(QRZRankDailyQuota.self, from: data) {
            savedQuota.resetIfNeeded()
            rankDailyQuota = savedQuota
        } else {
            rankDailyQuota = QRZRankDailyQuota()
        }
        saveDailyRankQuota()
    }

    private func saveDailyRankQuota() {
        guard let data = try? JSONEncoder().encode(rankDailyQuota) else { return }
        UserDefaults.standard.set(data, forKey: qrzRankDailyQuotaKey)
    }

    private func refreshDailyRankQuotaIfNeeded() {
        var quota = rankDailyQuota
        quota.resetIfNeeded()
        guard quota != rankDailyQuota else { return }
        rankDailyQuota = quota
        saveDailyRankQuota()
    }

    private func recordDailyRankRequestAttempt() {
        var quota = rankDailyQuota
        quota.recordAttempt()
        rankDailyQuota = quota
        saveDailyRankQuota()
    }

    private func recordDailyRankSuccess() {
        var quota = rankDailyQuota
        quota.recordSuccess()
        rankDailyQuota = quota
        saveDailyRankQuota()
    }

    private func fetchRankWithDailyQuota(
        callsign: String,
        credentials: QRZRankServiceCredentials
    ) async -> Result<QRZRankResponse, QRZRankFetchFailure> {
        if let quota = rankServerQuota, !quota.allowsRequest {
            do {
                rankServerQuota = try await QRZRankService.shared.fetchQuota(
                    token: credentials.token,
                    userAgent: "YAAM-macOS/\(currentVersion)"
                )
            } catch let failure as QRZRankFetchFailure {
                return .failure(failure)
            } catch {
                return .failure(.transport(error.localizedDescription))
            }
            if let refreshedQuota = rankServerQuota, !refreshedQuota.allowsRequest {
                return .failure(.rateLimited(rankQuotaExhaustedMessage(refreshedQuota)))
            }
        }
        recordDailyRankRequestAttempt()

        do {
            let response = try await QRZRankService.shared.fetchRank(
                callsign: callsign,
                token: credentials.token,
                userAgent: "YAAM-macOS/\(currentVersion)"
            )
            rankServerQuota = await QRZRankService.shared.latestQuota
            recordDailyRankSuccess()
            return .success(response)
        } catch let failure as QRZRankFetchFailure {
            rankServerQuota = await QRZRankService.shared.latestQuota
            return .failure(failure)
        } catch {
            rankServerQuota = await QRZRankService.shared.latestQuota
            return .failure(.transport(error.localizedDescription))
        }
    }

    private func rankQuotaExhaustedMessage(_ quota: QRZRankAPIQuota) -> String {
        var message = "The QRZ Rank allowance assigned by the server has been exhausted."
        if let resetsAt = quota.resetsAt, !resetsAt.isEmpty {
            message += " It resets at \(resetsAt)."
        }
        return message
    }

    private var rankQuotaAvailabilityDescription: String {
        guard let quota = rankServerQuota else { return "server allowance not checked" }
        if quota.isUnlimited { return "unlimited server allowance" }
        if let remaining = quota.effectiveRemaining {
            return "\(remaining) server request(s) remaining"
        }
        return quota.allowsRequest ? "server allowance available" : "server allowance exhausted"
    }

    private func fetchSingleRank(
        callsign: String,
        credentials: QRZRankServiceCredentials,
        completion: @escaping (Result<QRZRankResponse, QRZRankFetchFailure>) -> Void
    ) {
        Task { @MainActor in
            completion(await fetchRankWithDailyQuota(callsign: callsign, credentials: credentials))
        }
    }

    private func rankServiceCredentials() -> QRZRankServiceCredentials {
        return QRZRankServiceCredentials(
            token: CredentialVault.value(for: .qrzRankAPIToken)
        )
    }
    
    private var internalDatabaseURL: URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dbURL = appSupport.appendingPathComponent("YAAM/Logs")
        if !fm.fileExists(atPath: dbURL.path) {
            try? fm.createDirectory(at: dbURL, withIntermediateDirectories: true)
        }
        return dbURL
    }
    
    func loadRecentLogsFromDatabase() {
        guard let dbURL = internalDatabaseURL else { return }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: dbURL, includingPropertiesForKeys: [.creationDateKey]) {
            let sortedFiles = files.filter { $0.pathExtension == "adi" || $0.pathExtension == "adif" }
                .sorted {
                    let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return d1 > d2
                }
            DispatchQueue.main.async {
                self.recentLogFiles = sortedFiles
            }
        }
    }
    
    private func archiveLogToDatabase(originalURL: URL) {
        guard let dbURL = internalDatabaseURL else { return }
        if originalURL.deletingLastPathComponent().path == dbURL.path {
            loadRecentLogsFromDatabase()
            return
        }
        let fm = FileManager.default
        let destination = dbURL.appendingPathComponent(originalURL.lastPathComponent)
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: originalURL, to: destination)
            loadRecentLogsFromDatabase()
        } catch {
            print("Database archiving failed: \(error)")
        }
    }
    
    var currentStationCallsign: String {
        let profileCall = activeStationProfile?.normalizedCallsign ?? ""
        if !profileCall.isEmpty { return profileCall }

        let operatorCall = UserDefaults.standard.string(forKey: "operatorCallsign")?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let stationCall = UserDefaults.standard.string(forKey: "stationCallsign")?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let call = operatorCall.isEmpty ? stationCall : operatorCall
        return call.isEmpty ? "DEFAULT" : call
    }
    
    private var masterLogbookURL: URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("YAAM/MasterLogs")
        if !fm.fileExists(atPath: dir.path) { try? fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir.appendingPathComponent("MasterLogbook_\(currentStationCallsign).adi")
    }
    
    func loadMasterLogbook() {
        if let database = logbookDatabase, let profileID = activeStationProfileID {
            do {
                let workspace = try database.loadWorkspace(profileID: profileID)
                let storedCount = try database.qsoCount(profileID: profileID)
                guard storedCount == workspace.records.count else {
                    throw LogbookDatabaseError.unavailable(
                        "The database contains \(storedCount) QSOs, but only \(workspace.records.count) could be decoded. Loading was stopped to protect your log."
                    )
                }
                isMasterMode = true
                loadedFileURL = nil
                loadedFileName = "Master Log · \(currentStationCallsign)"
                selectedRecordIDs.removeAll()
                tableHeaders = workspace.headers.isEmpty
                    ? ["QSO_DATE", "TIME_ON", "CALL", "BAND", "MODE", "FREQ", "RST_SENT", "RST_RCVD", "COUNTRY", "COMMENT"]
                    : workspace.headers
                qsoRecords = workspace.records.enumerated().map { offset, record in
                    QSORecordModel(id: record.id, index: offset + 1, fields: record.fields)
                }
                loadedWorkspaceProfileID = profileID
                refreshEmailHistoryColumns()
                appendLog("Loaded \(qsoRecords.count) QSOs for station profile \(currentStationCallsign) from the protected database.")
                return
            } catch {
                loadedWorkspaceProfileID = nil
                databaseStatus = error.localizedDescription
                appendLog("Database workspace load failed: \(error.localizedDescription)")
            }
        }

        guard let url = masterLogbookURL else { return }
        self.isMasterMode = true
        self.loadedWorkspaceProfileID = nil
        self.loadedFileURL = url
        self.loadedFileName = "Master Log (\(currentStationCallsign))"
        self.selectedRecordIDs.removeAll()
        
        if FileManager.default.fileExists(atPath: url.path) {
            appendLog("Loading Master Logbook for \(currentStationCallsign)...")
            guard let content = (try? String(contentsOfFile: url.path, encoding: .utf8)) ?? (try? String(contentsOfFile: url.path, encoding: .isoLatin1)) else { return }
            let (headers, records) = parseADIF(content: content)
            self.tableHeaders = headers
            self.qsoRecords = records.enumerated().map { QSORecordModel(index: $0 + 1, fields: $1) }
            self.refreshEmailHistoryColumns()
            self.appendLog("Master Logbook loaded successfully: \(self.qsoRecords.count) QSOs.")
        } else {
            self.qsoRecords = []
            self.tableHeaders = ["QSO_DATE", "TIME_ON", "CALL", "BAND", "MODE", "FREQ", "RST_SENT", "RST_RCVD", "COUNTRY", "COMMENT"]
            self.refreshEmailHistoryColumns()
            self.appendLog("Created new empty Master Logbook for \(currentStationCallsign).")
        }
    }
    
    func autoSaveActiveWorkspace(
        allowEmptyReplacement: Bool = false,
        replaceMissingRecords: Bool = false
    ) {
        if isMasterMode, let database = logbookDatabase, let profileID = activeStationProfileID {
            guard loadedWorkspaceProfileID == profileID else {
                databaseStatus = YAAMPersistenceError.workspaceNotLoaded.localizedDescription
                appendLog("Automatic save skipped because the protected workspace is not fully loaded.")
                return
            }
            let headers = tableHeaders
            let records = qsoRecords.map { PersistedQSO(id: $0.id, index: $0.index, fields: $0.fields) }
            workspaceSaveQueue.async { [weak self] in
                do {
                    try database.saveWorkspace(
                        profileID: profileID,
                        headers: headers,
                        records: records,
                        allowEmptyReplacement: allowEmptyReplacement,
                        replaceMissingRecords: replaceMissingRecords
                    )
                } catch {
                    DispatchQueue.main.async {
                        self?.databaseStatus = error.localizedDescription
                        self?.appendLog("Automatic database save failed: \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        guard let url = loadedFileURL, !qsoRecords.isEmpty else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let recordsDicts = self.qsoRecords.map { $0.fields }
            let adifOutput = generateADIF(originalContent: "", records: recordsDicts)
            try? adifOutput.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func importLogDialog() {
        let panel = NSOpenPanel()
        var types: [UTType] = []
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        if let adifType = UTType(filenameExtension: "adif") { types.append(adifType) }
        if let smartSDRType = UTType(filenameExtension: "smartsdrlog") { types.append(smartSDRType) }

        panel.title = "Import Log File"
        panel.message = "Choose an ADIF log or an SDR Control SmartSDR log."
        panel.prompt = "Choose Log"
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            let isSmartSDR = url.pathExtension.caseInsensitiveCompare("smartsdrlog") == .orderedSame
            let alert = NSAlert()
            alert.messageText = isSmartSDR ? "Import SDR Control Log" : "Import ADIF Log"
            alert.informativeText = "Review and merge contacts into the \(currentStationCallsign) Master Log, or open them separately as a Guest Log.\(isSmartSDR ? " Deleted SDR Control entries are ignored and the source file remains unchanged." : "")"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Merge into Master Log")
            alert.addButton(withTitle: "Open as Guest Log")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                prepareImportReview(from: url)
            } else if response == .alertSecondButtonReturn {
                loadGuestLog(from: url)
            }
        }
    }

    func importADIFDialog() {
        importLogDialog()
    }

    func syncSDRControlLogbook() {
        syncSDRControlLogbookIfNeeded()
    }

    func chooseSDRControlLogbookFile() {
        _ = promptForSDRControlLogbookSource()
    }

    func configureSDRControlPeriodicSync() {
        sdrControlSyncTimer?.invalidate()
        sdrControlSyncTimer = nil

        guard UserDefaults.standard.bool(forKey: "sdrControlPeriodicSyncEnabled") else { return }

        let storedIntervalMinutes = UserDefaults.standard.double(forKey: "sdrControlPeriodicSyncIntervalMinutes")
        let intervalMinutes = storedIntervalMinutes > 0 ? storedIntervalMinutes : 15
        let interval = max(intervalMinutes, 1) * 60

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncSDRControlLogbookIfNeeded(isAutomatic: true)
            }
        }
        timer.tolerance = min(30, max(2, interval * 0.05))
        RunLoop.main.add(timer, forMode: .common)
        sdrControlSyncTimer = timer
    }

    func syncSDRControlLogbookIfNeeded(
        isAutomatic: Bool = false,
        completion: ((Result<MergeSummary, Error>) -> Void)? = nil
    ) {
        guard !isSDRControlSyncRunning else {
            completion?(.failure(NSError(
                domain: "YAAM.SDRControl",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "An SDR-Control import is already running."]
            )))
            return
        }
        guard !isLoading, !isSyncingAPI, !isExternalADIFSyncRunning else {
            completion?(.failure(NSError(
                domain: "YAAM.SDRControl",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Another import or confirmation sync is already running."]
            )))
            return
        }
        guard let source = sdrControlLogbookSource() ?? (isAutomatic ? nil : promptForSDRControlLogbookSource()) else {
            completion?(.failure(NSError(
                domain: "YAAM.SDRControl",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "SDR-Control logbook is not configured."]
            )))
            return
        }

        beginSyncStatus(.sdrControl, detail: "Reading SDR-Control logbook...")

        let resourceValues = try? source.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let lastModified = resourceValues?.contentModificationDate
        let sourceSignature = "\(resourceValues?.fileSize ?? 0)|\(lastModified?.timeIntervalSince1970 ?? 0)"
        // iCloud-backed property lists may replace their content without changing
        // the metadata observed by this process. Parse each scheduled run and let
        // the keyed merge decide whether anything is new.
        isSDRControlSyncRunning = true

        mergeSDRControlLogbook(from: source, allowPermissionPrompt: !isAutomatic) { result in
            self.isSDRControlSyncRunning = false
            if case .success = result {
                if let lastModified {
                    UserDefaults.standard.set(lastModified, forKey: "sdrControlLastSyncedModificationDate")
                }
                UserDefaults.standard.set(sourceSignature, forKey: "sdrControlLastSyncedSignature")
                UserDefaults.standard.set(Date(), forKey: "sdrControlLastSyncRunDate")
            }
            self.completeSyncStatus(.sdrControl, result: result, unchangedText: "No new SDR-Control QSOs")
            completion?(result)
        }
    }

    private struct SDRControlLogbookSource {
        let url: URL
        let securityScoped: Bool
    }

    private func sdrControlLogbookSource() -> SDRControlLogbookSource? {
        if let bookmarkData = UserDefaults.standard.data(forKey: "sdrControlLogbookBookmark") {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if FileManager.default.fileExists(atPath: url.path) {
                    if isStale {
                        saveSDRControlSecurityBookmark(for: url)
                    }
                    return SDRControlLogbookSource(url: url, securityScoped: true)
                }
            } catch {
                UserDefaults.standard.removeObject(forKey: "sdrControlLogbookBookmark")
            }
        }

        guard let url = defaultSDRControlLogbookURL() else {
            return nil
        }

        return SDRControlLogbookSource(url: url, securityScoped: false)
    }

    private func defaultSDRControlLogbookURL() -> URL? {
        let fileManager = FileManager.default
        if let savedPath = UserDefaults.standard.string(forKey: "sdrControlLogbookPath") {
            let savedURL = URL(fileURLWithPath: savedPath)
            if fileManager.fileExists(atPath: savedURL.path) {
                return savedURL
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let realHome = URL(fileURLWithPath: "/Users/\(NSUserName())")
        let mobileDocumentRoots = [
            home.appendingPathComponent("Library/Mobile Documents"),
            realHome.appendingPathComponent("Library/Mobile Documents")
        ]

        let candidates = mobileDocumentRoots.flatMap { mobileDocuments in
            [
                mobileDocuments.appendingPathComponent("iCloud~de~roskosch~RadioApp~SmartSDR/Documents/SmartSDR.smartsdrlog"),
                mobileDocuments.appendingPathComponent("com~apple~CloudDocs/SmartSDR/SmartSDR.smartsdrlog"),
                mobileDocuments.appendingPathComponent("SmartSDR/SmartSDR.smartsdrlog")
            ]
        }

        if let existing = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return existing
        }

        guard let mobileDocuments = mobileDocumentRoots.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return nil
        }

        guard let enumerator = fileManager.enumerator(
            at: mobileDocuments,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == "SmartSDR.smartsdrlog" else { continue }
            let pathComponents = url.pathComponents
            if pathComponents.contains("SmartSDR") || url.path.contains("RadioApp~SmartSDR") {
                return url
            }
        }

        return nil
    }

    private func promptForSDRControlLogbookSource() -> SDRControlLogbookSource? {
        let panel = NSOpenPanel()
        panel.title = "Select SmartSDR.smartsdrlog"
        panel.message = "Select SmartSDR.smartsdrlog from iCloud Drive > SmartSDR so YAAM can read it."
        panel.prompt = "Import SDR-Control Log"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let plistType = UTType(filenameExtension: "smartsdrlog") {
            panel.allowedContentTypes = [plistType]
        }

        let realHome = URL(fileURLWithPath: "/Users/\(NSUserName())")
        let suggestedURL = realHome
            .appendingPathComponent("Library/Mobile Documents/iCloud~de~roskosch~RadioApp~SmartSDR/Documents")
        if FileManager.default.fileExists(atPath: suggestedURL.path) {
            panel.directoryURL = suggestedURL
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        UserDefaults.standard.set(url.path, forKey: "sdrControlLogbookPath")
        saveSDRControlSecurityBookmark(for: url)
        return SDRControlLogbookSource(url: url, securityScoped: true)
    }

    private func saveSDRControlSecurityBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: "sdrControlLogbookBookmark")
            UserDefaults.standard.set(url.path, forKey: "sdrControlLogbookPath")
        } catch {
            appendLog("Unable to save SDR-Control file permission bookmark: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func mergeIncomingRecordsSafely(
        incomingFields: [[String: String]],
        profileID: UUID?,
        sourceName: String
    ) async throws -> SDRControlMergeResult {
        for attempt in 1...3 {
            guard activeStationProfileID == profileID else {
                throw NSError(
                    domain: "YAAM.LogMerge",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "\(sourceName) import stopped because the active station changed."]
                )
            }

            let startingRevision = qsoRecordsRevision
            let localRecords = qsoRecords
            let allowRoundedSDRMatches = sourceName == "SDR-Control"
            let result = await Task.detached(priority: .userInitiated) {
                SDRControlMergeEngine.merge(
                    localRecords: localRecords,
                    incomingFields: incomingFields,
                    allowRoundedSDRMatches: allowRoundedSDRMatches
                )
            }.value

            guard activeStationProfileID == profileID else {
                throw NSError(
                    domain: "YAAM.LogMerge",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "\(sourceName) import stopped because the active station changed."]
                )
            }
            if qsoRecordsRevision == startingRevision {
                return result
            }
            if attempt < 3 { await Task.yield() }
        }

        throw NSError(
            domain: "YAAM.LogMerge",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "The log changed while \(sourceName) was being imported. YAAM kept the newer contacts; run the import again."]
        )
    }

    /// Publishes only fields changed by a background workflow. Contacts imported
    /// while that workflow was awaiting network responses remain untouched.
    @MainActor
    @discardableResult
    private func applySafeFieldDeltas(
        from baseRecords: [QSORecordModel],
        to updatedRecords: [QSORecordModel]
    ) -> Int {
        let baseByID = Dictionary(uniqueKeysWithValues: baseRecords.map { ($0.id, $0.fields) })
        let updatedByID = Dictionary(uniqueKeysWithValues: updatedRecords.map { ($0.id, $0.fields) })
        var mergedRecords = qsoRecords
        let currentIndexByID = Dictionary(uniqueKeysWithValues: mergedRecords.indices.map {
            (mergedRecords[$0].id, $0)
        })
        var changedFieldCount = 0

        for (id, updatedFields) in updatedByID {
            guard let baseFields = baseByID[id], let currentIndex = currentIndexByID[id] else { continue }
            let changedKeys = Set(baseFields.keys).union(updatedFields.keys).filter {
                baseFields[$0] != updatedFields[$0]
            }
            guard !changedKeys.isEmpty else { continue }

            var currentFields = mergedRecords[currentIndex].fields
            var changedRecord = false
            for key in changedKeys {
                // A simultaneous operation wins if it changed the same field.
                guard currentFields[key] == baseFields[key] else { continue }
                if let updatedValue = updatedFields[key] {
                    currentFields[key] = updatedValue
                } else {
                    currentFields.removeValue(forKey: key)
                }
                changedFieldCount += 1
                changedRecord = true
            }
            if changedRecord {
                mergedRecords[currentIndex].fields = currentFields
            }
        }

        if changedFieldCount > 0 {
            qsoRecords = mergedRecords
        }
        return changedFieldCount
    }

    private func mergeSDRControlLogbook(
        from source: SDRControlLogbookSource,
        allowPermissionPrompt: Bool = true,
        completion: ((Result<MergeSummary, Error>) -> Void)? = nil
    ) {
        isLoading = true
        let url = source.url
        appendLog("Reading SDR-Control logbook: \(url.path)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let didStartAccess = source.securityScoped ? url.startAccessingSecurityScopedResource() : false
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let parsed = try LogFileReader.load(from: url)
                guard parsed.format == .smartSDR else {
                    throw LogFileReaderError.unsupportedFormat(url.lastPathComponent)
                }
                let records = parsed.records.filter { record in
                    !(record["CALL"] ?? "").isEmpty && (record["QSO_DATE"] ?? "").filter(\.isNumber).count == 8
                }

                DispatchQueue.main.async {
                    if !self.isMasterMode {
                        self.loadMasterLogbook()
                    }

                    let missingHeaders = parsed.headers.filter { !self.tableHeaders.contains($0) }
                    if !missingHeaders.isEmpty {
                        self.tableHeaders.append(contentsOf: missingHeaders)
                    }

                    let profileID = self.activeStationProfileID
                    let taggedRecords = records.map { self.stationTaggedFields($0) }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        do {
                            let mergeResult = try await self.mergeIncomingRecordsSafely(
                                incomingFields: taggedRecords,
                                profileID: profileID,
                                sourceName: "SDR-Control"
                            )

                            let summary = mergeResult.summary
                            if mergeResult.removedDuplicates > 0 {
                                guard self.createDestructiveCheckpointIfNeeded(
                                    reason: "Before consolidating duplicate QSOs during SDR-Control import"
                                ) else {
                                    throw NSError(
                                        domain: "YAAM.SDRControlImport",
                                        code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "YAAM could not create the required recovery checkpoint, so no duplicate records were removed."]
                                    )
                                }
                            }
                            if summary.added > 0 || summary.updated > 0 || mergeResult.removedDuplicates > 0 {
                                self.qsoRecords = mergeResult.records
                                self.autoSaveActiveWorkspace(
                                    replaceMissingRecords: mergeResult.removedDuplicates > 0
                                )
                            }
                            self.isLoading = false
                            var details = "SDR-Control sync complete: \(summary.added) new QSOs added, \(summary.updated) existing QSOs enriched, \(summary.skipped) duplicates skipped"
                            if mergeResult.removedDuplicates > 0 {
                                details += ", \(mergeResult.removedDuplicates) duplicate SDR-Control row(s) consolidated"
                            }
                            if parsed.ignoredDeletedRecordCount > 0 {
                                details += ", \(parsed.ignoredDeletedRecordCount) deleted entries ignored"
                            }
                            if parsed.validationIssueCount > 0 {
                                details += ", \(parsed.validationIssueCount) invalid entries ignored"
                            }
                            self.appendLog(details + ".")
                            self.playActivitySound(.success)
                            completion?(.success(summary))
                        } catch {
                            self.isLoading = false
                            self.appendLog("SDR-Control sync stopped safely: \(error.localizedDescription)")
                            self.playActivitySound(.failure)
                            completion?(.failure(error))
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    if allowPermissionPrompt, self.isFilePermissionError(error), !source.securityScoped {
                        UserDefaults.standard.removeObject(forKey: "sdrControlLogbookPath")
                        if let selectedSource = self.promptForSDRControlLogbookSource() {
                            self.mergeSDRControlLogbook(
                                from: selectedSource,
                                allowPermissionPrompt: false,
                                completion: completion
                            )
                        } else {
                            completion?(.failure(error))
                        }
                        return
                    }

                    self.showNativeAlert(
                        title: "SDR-Control Sync Failed",
                        message: error.localizedDescription
                    )
                    self.playActivitySound(.failure)
                    completion?(.failure(error))
                }
            }
        }
    }

    private func isFilePermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain &&
            (nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileReadNoSuchFileError)
    }

    func loadGuestLog(from url: URL) {
        isLoading = true
        appendLog("Opening Guest Log: \(url.lastPathComponent)...")

        if ["adi", "adif"].contains(url.pathExtension.lowercased()) {
            archiveLogToDatabase(originalURL: url)
        }

        Task { @MainActor in
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try LogFileReader.loadWithSecurityScopedAccess(from: url)
                }.value
                var qsoModels = parsed.records.enumerated().map { QSORecordModel(index: $0 + 1, fields: $1) }
                let offlineMatched = applyPersistentConfirmationCache(to: &qsoModels)

                isMasterMode = false
                loadedFileURL = parsed.format == .adif ? url : nil
                loadedFileName = parsed.format == .adif
                    ? "Guest: \(url.lastPathComponent)"
                    : "Guest: \(url.deletingPathExtension().lastPathComponent) (SDR Control)"
                selectedRecordIDs.removeAll()
                tableHeaders = parsed.headers
                qsoRecords = qsoModels
                refreshEmailHistoryColumns()
                isLoading = false
                var details = "Loaded \(parsed.records.count) \(parsed.format.title) QSO(s) in Guest Mode"
                if parsed.ignoredDeletedRecordCount > 0 {
                    details += "; \(parsed.ignoredDeletedRecordCount) deleted record(s) ignored"
                }
                appendLog(details + ".")
                if offlineMatched > 0 {
                    appendLog("Offline Database Engine: Matched \(offlineMatched) confirmations instantly from local storage.")
                }
            } catch {
                isLoading = false
                showNativeAlert(title: "Unable to Open Log", message: error.localizedDescription)
                appendLog("Guest log failed: \(error.localizedDescription)")
                playActivitySound(.failure)
            }
        }
    }
    
    private func mergeADIFIntoMaster(
        from url: URL,
        completion: ((Result<MergeSummary, Error>) -> Void)? = nil
    ) {
        isLoading = true
        appendLog("Analyzing & Merging '\(url.lastPathComponent)' into Master Logbook...")
        archiveLogToDatabase(originalURL: url)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try LogFileReader.loadWithSecurityScopedAccess(from: url)
                }.value
                guard parsed.format == .adif else {
                    throw LogFileReaderError.unsupportedFormat(url.lastPathComponent)
                }

                if !self.isMasterMode { self.loadMasterLogbook() }
                let missingHeaders = parsed.headers.filter { !self.tableHeaders.contains($0) }
                if !missingHeaders.isEmpty {
                    self.tableHeaders.append(contentsOf: missingHeaders)
                }

                let profileID = self.activeStationProfileID
                let taggedRecords = parsed.records.map { self.stationTaggedFields($0) }
                let mergeResult = try await self.mergeIncomingRecordsSafely(
                    incomingFields: taggedRecords,
                    profileID: profileID,
                    sourceName: "ADIF"
                )

                let summary = mergeResult.summary
                if mergeResult.removedDuplicates > 0 {
                    guard self.createDestructiveCheckpointIfNeeded(
                        reason: "Before consolidating exact duplicate QSOs during ADIF import"
                    ) else {
                        throw NSError(
                            domain: "YAAM.ADIFImport",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "YAAM could not create the required recovery checkpoint, so no duplicate records were removed."]
                        )
                    }
                }
                if summary.added > 0 || summary.updated > 0 || mergeResult.removedDuplicates > 0 {
                    self.qsoRecords = mergeResult.records
                    self.autoSaveActiveWorkspace(
                        replaceMissingRecords: mergeResult.removedDuplicates > 0
                    )
                }
                self.isLoading = false
                self.appendLog("Merge complete: \(summary.added) new QSOs added, \(summary.updated) existing QSOs enriched, \(summary.skipped) duplicates skipped, \(mergeResult.removedDuplicates) exact duplicate row(s) consolidated.")
                self.playActivitySound(.success)
                completion?(.success(summary))
            } catch {
                self.isLoading = false
                self.appendLog("External ADIF sync failed: \(error.localizedDescription)")
                self.playActivitySound(.failure)
                completion?(.failure(error))
            }
        }
    }

    func selectExternalADIFLogFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = []
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        if let adifType = UTType(filenameExtension: "adif") { types.append(adifType) }

        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Select External ADIF Log"
        panel.message = "Choose a .adi or .adif file from WSJT-X, JTDX, GridTracker, Log4OM, N1MM, SDR-Control export, or another logger."

        if panel.runModal() == .OK, let url = panel.url {
            guard isADIFFile(url) else {
                showNativeAlert(
                    title: "ADIF Export Required",
                    message: "YAAM can sync external logs only from .adi or .adif files."
                )
                return
            }

            UserDefaults.standard.set(url.path, forKey: "externalADIFLogPath")
            UserDefaults.standard.set(url.path, forKey: "sdrControlLogPath")
            appendLog("External ADIF log selected: \(url.lastPathComponent)")
            configureExternalADIFAutoSync()
        }
    }

    func selectSDRControlLogFile() {
        selectExternalADIFLogFile()
    }

    private func isADIFFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "adi" || ext == "adif"
    }

    func configureExternalADIFAutoSync() {
        externalADIFSyncTimer?.invalidate()
        externalADIFSyncTimer = nil

        let isEnabled = UserDefaults.standard.bool(forKey: "externalADIFAutoSyncEnabled") ||
            UserDefaults.standard.bool(forKey: "sdrControlAutoSyncEnabled")
        guard isEnabled else { return }

        let newInterval = UserDefaults.standard.double(forKey: "externalADIFSyncIntervalMinutes")
        let oldInterval = UserDefaults.standard.double(forKey: "sdrControlSyncIntervalMinutes")
        let storedIntervalMinutes = newInterval > 0 ? newInterval : oldInterval
        let intervalMinutes = storedIntervalMinutes > 0 ? storedIntervalMinutes : 15
        let interval = max(intervalMinutes, 1) * 60

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncExternalADIFLogIfNeeded(isAutomatic: true)
            }
        }
        timer.tolerance = min(30, max(2, interval * 0.05))
        RunLoop.main.add(timer, forMode: .common)
        externalADIFSyncTimer = timer
    }

    func configureSDRControlAutoSync() {
        configureExternalADIFAutoSync()
    }

    func syncExternalADIFLogIfNeeded(
        isAutomatic: Bool = false,
        completion: ((Result<MergeSummary, Error>) -> Void)? = nil
    ) {
        guard !isExternalADIFSyncRunning else {
            completion?(.failure(NSError(
                domain: "YAAM.ExternalADIF",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "An external ADIF import is already running."]
            )))
            return
        }
        guard !isLoading, !isSyncingAPI, !isSDRControlSyncRunning else {
            completion?(.failure(NSError(
                domain: "YAAM.ExternalADIF",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Another import or confirmation sync is already running."]
            )))
            return
        }

        let path = (
            UserDefaults.standard.string(forKey: "externalADIFLogPath") ??
            UserDefaults.standard.string(forKey: "sdrControlLogPath") ??
            ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            if !isAutomatic {
                showNativeAlert(
                    title: "External ADIF Log Not Selected",
                    message: "Please select a .adi/.adif log file from Preferences first."
                )
                playActivitySound(.failure)
            }
            completion?(.failure(NSError(
                domain: "YAAM.ExternalADIF",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "External ADIF log is not configured."]
            )))
            return
        }

        let url = URL(fileURLWithPath: path)
        guard isADIFFile(url) else {
            appendLog("External ADIF sync skipped: select a .adi or .adif file.")
            if !isAutomatic {
                showNativeAlert(
                    title: "ADIF Export Required",
                    message: "The saved external log path is not an ADIF file. Select a .adi or .adif file in Preferences."
                )
                playActivitySound(.failure)
            }
            completion?(.failure(NSError(
                domain: "YAAM.ExternalADIF",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The configured source is not an ADIF file."]
            )))
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            appendLog("External ADIF sync skipped: file not found at saved path.")
            if !isAutomatic { playActivitySound(.failure) }
            completion?(.failure(NSError(
                domain: "YAAM.ExternalADIF",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "The configured ADIF file could not be found."]
            )))
            return
        }

        beginSyncStatus(.externalADIF, detail: "Reading external ADIF log...")

        let lastModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        appendLog("External ADIF sync started...")
        isExternalADIFSyncRunning = true
        mergeADIFIntoMaster(from: url) { result in
            self.isExternalADIFSyncRunning = false
            if case .success = result {
                if let lastModified {
                    UserDefaults.standard.set(lastModified, forKey: "externalADIFLastSyncedModificationDate")
                }
                UserDefaults.standard.set(Date(), forKey: "externalADIFLastSyncRunDate")
            }
            self.completeSyncStatus(.externalADIF, result: result, unchangedText: "No new ADIF QSOs")
            completion?(result)
        }
    }

    func syncSDRControlLogIfNeeded(isAutomatic: Bool = false) {
        syncSDRControlLogbookIfNeeded(isAutomatic: isAutomatic)
    }

    func fetchPropagationSnapshot() {
        guard !isFetchingPropagation else { return }

        isFetchingPropagation = true

        var snapshot = PropagationSnapshot(updatedAt: Date())
        let group = DispatchGroup()
        let lock = NSLock()

        if let hamQSLURL = URL(string: "https://www.hamqsl.com/solarxml.php") {
            group.enter()
            URLSession.shared.dataTask(with: URLRequest(url: hamQSLURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)) { [weak self] data, _, _ in
                defer { group.leave() }
                guard let self, let data, let xml = String(data: data, encoding: .utf8) else { return }

                lock.lock()
                snapshot.solarFlux = self.xmlValue("solarflux", in: xml) ?? "-"
                snapshot.aIndex = self.xmlValue("aindex", in: xml) ?? "-"
                snapshot.kIndex = self.xmlValue("kindex", in: xml) ?? "-"
                snapshot.xray = self.xmlValue("xray", in: xml) ?? "-"
                snapshot.sunspots = self.xmlValue("sunspots", in: xml) ?? "-"
                snapshot.signalNoise = self.xmlValue("signalnoise", in: xml) ?? "-"
                snapshot.geomagField = self.xmlValue("geomagfield", in: xml) ?? "-"
                snapshot.aurora = self.xmlValue("aurora", in: xml) ?? "-"
                snapshot.solarWind = self.xmlValue("solarwind", in: xml) ?? "-"
                snapshot.bz = self.xmlValue("bfield", in: xml) ?? self.xmlValue("bz", in: xml) ?? "-"
                snapshot.bands = self.parseBandConditions(from: xml)
                snapshot.vhfConditions = self.parseVHFConditions(from: xml)
                lock.unlock()
            }.resume()
        }

        if let noaaURL = URL(string: "https://services.swpc.noaa.gov/text/27-day-outlook.txt") {
            group.enter()
            URLSession.shared.dataTask(with: URLRequest(url: noaaURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)) { [weak self] data, _, _ in
                defer { group.leave() }
                guard let self, let data, let text = String(data: data, encoding: .utf8) else { return }

                lock.lock()
                snapshot.solarForecast = self.parseNOAA27DayOutlook(from: text)
                lock.unlock()
            }.resume()
        }

        group.notify(queue: .main) {
            self.propagationSnapshot = snapshot
            self.isFetchingPropagation = false
        }
    }

    var sixMeterSignalCount: Int {
        pskReporterSignals.filter(\.isSixMeters).count
    }

    var middleEastSixMeterSignalCount: Int {
        pskReporterSignals.filter { $0.isSixMeters && isMiddleEastLocator($0.receiverLocator) }.count
    }

    var bestSixMeterSNRText: String {
        pskReporterSignals
            .filter(\.isSixMeters)
            .compactMap(\.snr)
            .max()
            .map { "\($0) dB" } ?? "-"
    }

    var sixMeterAssessment: SixMeterOpeningAssessment {
        let sixMeter = pskReporterSignals.filter(\.isSixMeters)
        let regional = sixMeter.filter { isMiddleEastLocator($0.receiverLocator) }
        let strong = sixMeter.filter { ($0.snr ?? -99) >= -12 }
        let euESkip = propagationSnapshot.vhfConditions["E-Skip|Europe 6m"] ?? propagationSnapshot.vhfConditions["E-Skip|Europe"] ?? "-"
        let eSkipLooksOpen = euESkip.localizedCaseInsensitiveContains("good") ||
            euESkip.localizedCaseInsensitiveContains("fair") ||
            euESkip.localizedCaseInsensitiveContains("open")

        if !regional.isEmpty || sixMeter.count >= 4 || (!sixMeter.isEmpty && eSkipLooksOpen) {
            return SixMeterOpeningAssessment(
                title: "6m may be opening now",
                detail: "There is fresh reception evidence on 50 MHz. Check 50.313 FT8, local beacons, and DX Cluster spots before the opening fades.",
                evidence: "\(sixMeter.count) recent 6m report(s), \(regional.count) near Middle East locators, best SNR \(bestSixMeterSNRText), E-skip: \(euESkip).",
                icon: "bolt.circle.fill",
                color: .orange,
                isOpen: true
            )
        }

        if !strong.isEmpty {
            return SixMeterOpeningAssessment(
                title: "6m has weak positive signs",
                detail: "A few stronger reports exist, but the regional evidence is not convincing yet.",
                evidence: "\(sixMeter.count) 6m report(s), \(strong.count) stronger than -12 dB, E-skip: \(euESkip).",
                icon: "waveform.path.ecg",
                color: .yellow,
                isOpen: false
            )
        }

        return SixMeterOpeningAssessment(
            title: "6m looks quiet",
            detail: "No strong regional evidence is visible in the recent PSK Reporter sample.",
            evidence: "\(sixMeter.count) recent 6m report(s), \(regional.count) regional report(s), E-skip: \(euESkip).",
            icon: "moon.zzz.fill",
            color: .secondary,
            isOpen: false
        )
    }

    func fetchPSKReporterSignals() {
        guard !isFetchingPSKReporter else { return }
        let callsign = currentStationCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !callsign.isEmpty, callsign != "DEFAULT", callsign != "NOCALL" else {
            pskReporterStatus = "Set an active station callsign before querying PSK Reporter."
            return
        }
        if let last = pskReporterLastUpdated, Date().timeIntervalSince(last) < 240 {
            pskReporterStatus = "PSK Reporter was refreshed recently; wait a minute before querying again."
            return
        }

        isFetchingPSKReporter = true
        pskReporterStatus = "Querying PSK Reporter for \(callsign)..."

        guard var components = URLComponents(string: "https://retrieve.pskreporter.info/query") else {
            isFetchingPSKReporter = false
            pskReporterStatus = "Invalid PSK Reporter endpoint."
            return
        }
        components.queryItems = [
            URLQueryItem(name: "senderCallsign", value: callsign),
            URLQueryItem(name: "flowStartSeconds", value: "-21600"),
            URLQueryItem(name: "rptlimit", value: "120"),
            URLQueryItem(name: "rronly", value: "1")
        ]
        guard let url = components.url else {
            isFetchingPSKReporter = false
            pskReporterStatus = "Unable to create PSK Reporter request."
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.setValue("YAAM-macOS/\(currentVersion) factoreal", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            DispatchQueue.main.async {
                defer { self.isFetchingPSKReporter = false }
                if let error {
                    self.pskReporterStatus = error.localizedDescription
                    self.playActivitySound(.failure)
                    return
                }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                    self.pskReporterStatus = "PSK Reporter did not return a successful response."
                    self.playActivitySound(.failure)
                    return
                }
                let signals = self.parsePSKReporterSignals(data)
                    .sorted { $0.flowStart > $1.flowStart }
                self.pskReporterSignals = signals
                self.pskReporterLastUpdated = Date()
                self.pskReporterStatus = "Loaded \(signals.count) recent reception report(s) from PSK Reporter."
                if self.sixMeterAssessment.isOpen {
                    self.playActivitySound(.notice)
                }
            }
        }.resume()
    }

    private func parsePSKReporterSignals(_ data: Data) -> [PSKReporterSignal] {
        let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let pattern = #"<receptionReport\b([^>]*)/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.matches(in: xml, range: range).compactMap { match in
            guard let attributeRange = Range(match.range(at: 1), in: xml) else { return nil }
            let attributes = pskReporterAttributes(String(xml[attributeRange]))
            let frequency = attributes["frequency"].flatMap(Int.init) ?? 0
            guard frequency > 0 else { return nil }
            let startSeconds = attributes["flowStartSeconds"].flatMap(TimeInterval.init) ?? Date().timeIntervalSince1970
            return PSKReporterSignal(
                receiverCallsign: attributes["receiverCallsign"] ?? "UNKNOWN",
                receiverLocator: attributes["receiverLocator"] ?? "",
                senderCallsign: attributes["senderCallsign"] ?? currentStationCallsign,
                frequencyHz: frequency,
                mode: attributes["mode"] ?? "-",
                snr: attributes["sNR"].flatMap(Int.init) ?? attributes["snr"].flatMap(Int.init),
                flowStart: Date(timeIntervalSince1970: startSeconds)
            )
        }
    }

    private func pskReporterAttributes(_ raw: String) -> [String: String] {
        let pattern = #"([A-Za-z0-9_]+)\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var values: [String: String] = [:]
        for match in regex.matches(in: raw, range: range) where match.numberOfRanges == 3 {
            guard let keyRange = Range(match.range(at: 1), in: raw),
                  let valueRange = Range(match.range(at: 2), in: raw) else { continue }
            values[String(raw[keyRange])] = String(raw[valueRange])
        }
        return values
    }

    private func isMiddleEastLocator(_ locator: String) -> Bool {
        let normalized = locator.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count >= 2 else { return false }
        let prefix = String(normalized.prefix(2))
        return ["LL", "LM", "LK", "KL", "KM"].contains(prefix)
    }

    private func xmlValue(_ tag: String, in xml: String) -> String? {
        let pattern = "<\(tag)>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: xml) else {
            return nil
        }

        return String(xml[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseBandConditions(from xml: String) -> [String: String] {
        let pattern = #"<band[^>]*name="([^"]+)"[^>]*time="([^"]+)"[^>]*>(.*?)</band>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return [:]
        }

        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, range: range)

        var conditions: [String: String] = [:]
        for match in matches where match.numberOfRanges > 3 {
            guard let nameRange = Range(match.range(at: 1), in: xml),
                  let timeRange = Range(match.range(at: 2), in: xml),
                  let valueRange = Range(match.range(at: 3), in: xml) else { continue }

            let name = String(xml[nameRange]).uppercased()
            let time = String(xml[timeRange]).lowercased()
            let value = String(xml[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            conditions["\(name)_\(time)"] = value
        }

        return conditions
    }

    private func parseVHFConditions(from xml: String) -> [String: String] {
        let pattern = #"<phenomenon[^>]*name="([^"]+)"[^>]*location="([^"]+)"[^>]*>(.*?)</phenomenon>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return [:]
        }

        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, range: range)

        var conditions: [String: String] = [:]
        for match in matches where match.numberOfRanges > 3 {
            guard let nameRange = Range(match.range(at: 1), in: xml),
                  let locationRange = Range(match.range(at: 2), in: xml),
                  let valueRange = Range(match.range(at: 3), in: xml) else { continue }

            let name = String(xml[nameRange])
            let location = String(xml[locationRange])
            let value = String(xml[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            conditions["\(name)|\(location)"] = value
            conditions["\(normalizedVHFName(name))|\(normalizedVHFLocation(location))"] = value
        }

        return conditions
    }

    private func parseNOAA27DayOutlook(from text: String) -> [SolarForecastPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy MMM dd"

        let labelFormatter = DateFormatter()
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")
        labelFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        labelFormatter.dateFormat = "MMM-dd"

        return text
            .split(separator: "\n")
            .compactMap { line -> SolarForecastPoint? in
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard parts.count == 6,
                      let solarFlux = Int(parts[3]),
                      let aIndex = Int(parts[4]),
                      let kpIndex = Int(parts[5]),
                      let date = formatter.date(from: "\(parts[0]) \(parts[1]) \(parts[2])") else {
                    return nil
                }

                return SolarForecastPoint(
                    date: date,
                    dateLabel: labelFormatter.string(from: date),
                    solarFlux: solarFlux,
                    aIndex: aIndex,
                    kpIndex: kpIndex
                )
            }
    }

    private func normalizedVHFName(_ rawName: String) -> String {
        switch rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "vhf-aurora", "vhf aurora":
            return "VHF Aurora"
        case "e-skip", "eskip":
            return "E-Skip"
        default:
            return rawName
        }
    }

    private func normalizedVHFLocation(_ rawLocation: String) -> String {
        switch rawLocation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "northern_hemi", "northern hemisphere":
            return "Northern Hemisphere"
        case "north_america", "north america":
            return "North America"
        case "europe_6m", "europe 6m":
            return "Europe 6m"
        case "europe_4m", "europe 4m":
            return "Europe 4m"
        case "europe":
            return "Europe"
        default:
            return rawLocation
        }
    }
    
    func loadADIFFile(from url: URL) {
        loadGuestLog(from: url)
    }

    private var cloudLogbookFileURL: URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("YAAM/CloudLog")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("MyCloudLogbook.adi")
    }

    func confirmAndFetchCloudLogbook() {
        let lotwUser = UserDefaults.standard.string(forKey: "lotwUsername")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lotwPass = CredentialVault.value(for: .lotwPassword)
        
        if lotwUser.isEmpty || lotwPass.isEmpty {
            self.alertTitle = "Credentials Required 🔑"
            self.alertMessage = "Please enter your LoTW Username and Password in Preferences (Cmd+,) to fetch your Cloud Logbook."
            self.showAlert = true
            self.playActivitySound(.failure)
            return
        }
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Download Entire LoTW Cloud Logbook? ☁️"
            alert.informativeText = "This action will download your COMPLETE historical logbook (all QSOs ever uploaded, both confirmed and unconfirmed) directly from ARRL LoTW servers.\n\nAfter downloading, new QSOs will be safely merged into your active Master Logbook (\(self.currentStationCallsign)) without creating duplicates."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Download & Merge All")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.fetchAndManageCloudLogbook()
            }
        }
    }

    private func fetchAndManageCloudLogbook() {
        let lotwUser = UserDefaults.standard.string(forKey: "lotwUsername")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lotwPass = CredentialVault.value(for: .lotwPassword)
        
        isLoading = true
        appendLog("☁️ Connecting to ARRL LoTW servers for Full Historical Cloud Download...")
        
        guard let encodedUser = lotwUser.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedPass = lotwPass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let endpoint = URL(string: "https://lotw.arrl.org/lotwuser/lotwreport.adi?login=\(encodedUser)&password=\(encodedPass)&qso_query=1&qso_qsosince=1900-01-01") else {
            self.isLoading = false
            self.appendLog("Error: Invalid LoTW query URL.")
            self.playActivitySound(.failure)
            return
        }
        
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        request.setValue("YAAM-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.alertTitle = "Cloud Fetch Failed 🔴"
                    self.alertMessage = error.localizedDescription
                    self.showAlert = true
                    self.playActivitySound(.failure)
                }
                return
            }
            
            guard let data = data, let fetchedADIF = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            
            if fetchedADIF.lowercased().contains("invalid password") || fetchedADIF.lowercased().contains("access denied") {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.alertTitle = "Authentication Failed 🔴"
                    self.alertMessage = "LoTW rejected credentials. Please check your Username and Password in Preferences (Cmd+,)."
                    self.showAlert = true
                    self.playActivitySound(.failure)
                }
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cloudFileURL = self.cloudLogbookFileURL else { return }
                do {
                    try fetchedADIF.write(to: cloudFileURL, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        UserDefaults.standard.set(Date(), forKey: "lastCloudLogbookFetch")
                        self.appendLog("☁️ Cloud Logbook downloaded successfully. Merging into Master Logbook...")
                        self.playActivitySound(.success)
                        self.mergeADIFIntoMaster(from: cloudFileURL)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.playActivitySound(.failure)
                    }
                }
            }
        }.resume()
    }

    func stopEnrichment() {
        let wasDailyRankBackfill = isDailyRankBackfillRunning
        enrichmentTask?.cancel()
        enrichmentTask = nil
        isEnriching = false
        isDailyRankBackfillRunning = false
        if wasDailyRankBackfill {
            dailyRankBackfillStatus = "Stopped after \(dailyRankBackfillCompleted) of \(dailyRankBackfillTotal) callsigns."
        }
        autoSaveActiveWorkspace()
        appendLog("🛑 Enrichment process stopped by user. Saved completed results.")
    }

    func enrichLogData(targetCallsigns: Set<String>? = nil) {
        guard !qsoRecords.isEmpty, !isEnriching else { return }

        let newHeaders = [
            "RANK_QSO", "RANK_BAND", "RANK_DXCC", "NAME", "EMAIL", "QRZ_URL",
            "APP_YAAM_ENRICHED", "APP_YAAM_EMAIL_CHECKED", "APP_YAAM_RANK_CHECKED",
            "APP_YAAM_RANK_STATUS"
        ]
        for header in newHeaders {
            if !tableHeaders.contains(header) {
                tableHeaders.append(header)
            }
        }
        self.objectWillChange.send()
        
        var callsignsToEnrich = Set<String>()
        if let targets = targetCallsigns {
            callsignsToEnrich = targets
        } else {
            let today = Self.adifDateFormatter.string(from: Date())
            for record in qsoRecords {
                guard record["QSO_DATE"].trimmingCharacters(in: .whitespacesAndNewlines) == today else { continue }
                let c = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !c.isEmpty { callsignsToEnrich.insert(c) }
            }
        }
        
        let uniqueCallsigns = callsignsToEnrich.sorted()
        guard !uniqueCallsigns.isEmpty else {
            if targetCallsigns == nil {
                appendLog("ℹ️ No QSOs found for today to enrich.")
            } else {
                appendLog("✅ All target records in this workspace are already enriched!")
            }
            selectedRecordIDs.removeAll()
            return
        }
        
        let rankCredentials = rankServiceCredentials()
        var recordIndicesByCallsign: [String: [Int]] = [:]
        for index in qsoRecords.indices {
            let callsign = qsoRecords[index]["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !callsign.isEmpty { recordIndicesByCallsign[callsign, default: []].append(index) }
        }
        isEnriching = true
        appendLog("🚀 Enrichment: Processing \(uniqueCallsigns.count) callsign(s)...")
        
        enrichmentTask = Task { @MainActor in
            var rankBatchBlocker: QRZRankFetchFailure?
            var workingRecords = self.qsoRecords
            var publishedRecords = workingRecords
            var hasUnsavedChanges = false
            for (idx, callsign) in uniqueCallsigns.enumerated() {
                if Task.isCancelled { break }

                var rankQSO = ""
                var rankBand = ""
                var rankDXCC = ""
                var shouldMarkRankLookup = false
                var rankStatus = ""

                if rankBatchBlocker == nil {
                    let rankResult = await self.fetchRankWithDailyQuota(
                        callsign: callsign,
                        credentials: rankCredentials
                    )
                    switch rankResult {
                    case .success(let response):
                        rankQSO = response.rank_qso ?? ""
                        rankBand = response.rank_band ?? ""
                        rankDXCC = response.rank_countries ?? ""
                        shouldMarkRankLookup = true
                        rankStatus = "FOUND"
                        self.saveRankResponseSnapshot(response)
                    case .failure(let failure):
                        shouldMarkRankLookup = failure.shouldRecordLookupOutcome
                        switch failure {
                        case .callsignNotFound:
                            rankStatus = "NOT_FOUND"
                        case .invalidCallsign:
                            rankStatus = "INVALID"
                        default:
                            rankStatus = "ERROR"
                        }
                        self.rankServiceStatus = failure.localizedDescription
                        if failure.shouldStopBatch {
                            rankBatchBlocker = failure
                            self.appendLog("QRZ Rank requests paused for the rest of this enrichment run: \(failure.localizedDescription)")
                        }
                    }
                }
                
                if Task.isCancelled { break }

                let fetchedContact = await self.fetchContactInfo(for: callsign, allowQRZWebKitFallback: false)

                if idx < uniqueCallsigns.count - 1 {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                }

                if Task.isCancelled { break }

                for i in recordIndicesByCallsign[callsign] ?? [] where workingRecords.indices.contains(i) {
                        if !rankQSO.isEmpty { workingRecords[i].fields["RANK_QSO"] = rankQSO }
                        if !rankBand.isEmpty { workingRecords[i].fields["RANK_BAND"] = rankBand }
                        if !rankDXCC.isEmpty { workingRecords[i].fields["RANK_DXCC"] = rankDXCC }
                        if shouldMarkRankLookup {
                            workingRecords[i].fields["APP_YAAM_RANK_CHECKED"] = Self.adifDateFormatter.string(from: Date())
                            workingRecords[i].fields["APP_YAAM_RANK_STATUS"] = rankStatus
                        }
                        if let name = fetchedContact.name, !name.isEmpty {
                            let currentName = workingRecords[i]["NAME"].trimmingCharacters(in: .whitespacesAndNewlines)
                            if currentName.isEmpty || self.isGenericQRZName(currentName) {
                                workingRecords[i].fields["NAME"] = name
                            } else {
                                workingRecords[i].fields["NAME"] = self.appendedDistinctValue(currentName, newValue: name)
                            }
                        } else if self.isGenericQRZName(workingRecords[i]["NAME"]) {
                            workingRecords[i].fields["NAME"] = ""
                        }
                        if let email = fetchedContact.email, !email.isEmpty { workingRecords[i].fields["EMAIL"] = email }

                        workingRecords[i].fields["QRZ_URL"] = "https://www.qrz.com/db/\(callsign)"
                        if fetchedContact.name != nil || fetchedContact.email != nil || !rankQSO.isEmpty || !rankBand.isEmpty || !rankDXCC.isEmpty {
                            workingRecords[i].fields["APP_YAAM_ENRICHED"] = "Y"
                        }
                        workingRecords[i].fields["APP_YAAM_EMAIL_CHECKED"] = Self.adifDateFormatter.string(from: Date())
                        hasUnsavedChanges = true
                }

                let completed = idx + 1
                if completed.isMultiple(of: 10) || completed == uniqueCallsigns.count {
                    self.rankServiceStatus = "Enriched \(completed) of \(uniqueCallsigns.count) callsigns."
                }
                if completed.isMultiple(of: 100) || completed == uniqueCallsigns.count {
                    self.applySafeFieldDeltas(from: publishedRecords, to: workingRecords)
                    publishedRecords = workingRecords
                    self.autoSaveActiveWorkspace()
                    hasUnsavedChanges = false
                }
            }
            
            let wasCancelled = Task.isCancelled
            if hasUnsavedChanges {
                self.applySafeFieldDeltas(from: publishedRecords, to: workingRecords)
                self.autoSaveActiveWorkspace()
            }
            self.isEnriching = false
            self.isDailyRankBackfillRunning = false
            self.enrichmentTask = nil
            
            self.selectedRecordIDs.removeAll()
            if wasCancelled {
                self.appendLog("🛑 Enrichment stopped.")
            } else {
                self.appendLog("✅ Enrichment complete & Workspace Auto-Saved!")
            }
        }
    }

    func fetchDailyQRZRankBackfill() {
        guard !qsoRecords.isEmpty, !isEnriching else { return }
        refreshDailyRankQuotaIfNeeded()

        let credentials = rankServiceCredentials()
        guard credentials.isConfigured else {
            dailyRankBackfillStatus = "Add a QRZ Rank API token in Settings first."
            alertTitle = "QRZ Rank API Token Required"
            alertMessage = "Daily Rank Backfill uses the personal token generated in your QRZ Rank user panel. Save it in Settings > Rank Service, then try again."
            showAlert = true
            return
        }

        let propagatedRows = propagateExistingRankValues()
        let checkedDay = Self.adifDateFormatter.string(from: Date())
        let callsigns = QRZRankBackfillPlanner.candidateCallsigns(
            from: qsoRecords,
            checkedDay: checkedDay,
            limit: Int.max,
            value: { record, field in record[field] }
        )
        guard !callsigns.isEmpty else {
            dailyRankBackfillStatus = "No unchecked callsigns with missing QRZ rankings remain for today."
            rankServiceStatus = dailyRankBackfillStatus
            if propagatedRows > 0 {
                objectWillChange.send()
                autoSaveActiveWorkspace()
            }
            return
        }

        for header in [
            "RANK_QSO", "RANK_BAND", "RANK_DXCC", "APP_YAAM_ENRICHED",
            "APP_YAAM_RANK_CHECKED", "APP_YAAM_RANK_STATUS"
        ] where !tableHeaders.contains(header) {
            tableHeaders.append(header)
        }

        var recordIndicesByCallsign: [String: [Int]] = [:]
        for index in qsoRecords.indices {
            let callsign = qsoRecords[index]["CALL"]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard !callsign.isEmpty else { continue }
            recordIndicesByCallsign[callsign, default: []].append(index)
        }

        isEnriching = true
        isDailyRankBackfillRunning = true
        dailyRankBackfillCompleted = 0
        dailyRankBackfillTotal = callsigns.count
        dailyRankBackfillStatus = "Checking the server allowance for \(callsigns.count) missing QRZ rankings..."
        rankServiceStatus = dailyRankBackfillStatus
        appendLog("QRZ Rank daily backfill is checking the server allowance for \(callsigns.count) unique callsign(s).")

        enrichmentTask = Task { @MainActor in
            do {
                self.rankServerQuota = try await QRZRankService.shared.fetchQuota(
                    token: credentials.token,
                    userAgent: "YAAM-macOS/\(self.currentVersion)"
                )
            } catch let failure as QRZRankFetchFailure {
                self.isEnriching = false
                self.isDailyRankBackfillRunning = false
                self.enrichmentTask = nil
                self.dailyRankBackfillStatus = "Daily rank backfill could not start: \(failure.localizedDescription)"
                self.rankServiceStatus = self.dailyRankBackfillStatus
                self.appendLog("QRZ Rank daily backfill: \(self.dailyRankBackfillStatus)")
                return
            } catch {
                self.isEnriching = false
                self.isDailyRankBackfillRunning = false
                self.enrichmentTask = nil
                self.dailyRankBackfillStatus = "Daily rank backfill could not start: \(error.localizedDescription)"
                self.rankServiceStatus = self.dailyRankBackfillStatus
                self.appendLog("QRZ Rank daily backfill: \(self.dailyRankBackfillStatus)")
                return
            }

            if let quota = self.rankServerQuota, !quota.allowsRequest {
                self.isEnriching = false
                self.isDailyRankBackfillRunning = false
                self.enrichmentTask = nil
                self.dailyRankBackfillStatus = self.rankQuotaExhaustedMessage(quota)
                self.rankServiceStatus = self.dailyRankBackfillStatus
                self.appendLog("QRZ Rank daily backfill did not start: \(self.dailyRankBackfillStatus)")
                return
            }

            self.dailyRankBackfillStatus = "Starting \(callsigns.count) callsign(s), \(self.rankQuotaAvailabilityDescription)."
            self.rankServiceStatus = self.dailyRankBackfillStatus
            var successfulCallsigns = 0
            var unavailableCallsigns = 0
            var consecutiveTransientFailures = 0
            var stoppingFailure: QRZRankFetchFailure?
            var workingRecords = self.qsoRecords
            var publishedRecords = workingRecords
            var hasUnsavedChanges = false

            for (offset, callsign) in callsigns.enumerated() {
                if Task.isCancelled { break }
                if let quota = self.rankServerQuota, !quota.allowsRequest {
                    stoppingFailure = .rateLimited(self.rankQuotaExhaustedMessage(quota))
                    break
                }

                let result = await self.fetchRankWithDailyQuota(callsign: callsign, credentials: credentials)
                if Task.isCancelled { break }

                switch result {
                case .success(let response):
                    consecutiveTransientFailures = 0
                    successfulCallsigns += 1
                    self.applyRankResponse(
                        response,
                        callsign: callsign,
                        checkedDay: checkedDay,
                        recordIndices: recordIndicesByCallsign[callsign] ?? [],
                        records: &workingRecords
                    )
                    hasUnsavedChanges = true
                    self.saveRankResponseSnapshot(response)

                case .failure(let failure):
                    unavailableCallsigns += 1

                    switch failure {
                    case .callsignNotFound:
                        consecutiveTransientFailures = 0
                        self.markRankLookup(
                            callsign: callsign,
                            checkedDay: checkedDay,
                            status: "NOT_FOUND",
                            recordIndices: recordIndicesByCallsign[callsign] ?? [],
                            records: &workingRecords
                        )
                        hasUnsavedChanges = true
                    case .invalidCallsign:
                        consecutiveTransientFailures = 0
                        self.markRankLookup(
                            callsign: callsign,
                            checkedDay: checkedDay,
                            status: "INVALID",
                            recordIndices: recordIndicesByCallsign[callsign] ?? [],
                            records: &workingRecords
                        )
                        hasUnsavedChanges = true
                    default:
                        consecutiveTransientFailures += 1
                    }

                    if failure.shouldStopBatch || consecutiveTransientFailures >= 3 {
                        stoppingFailure = failure
                    }
                }

                let completed = offset + 1
                if completed.isMultiple(of: 5) || completed == callsigns.count || stoppingFailure != nil {
                    self.dailyRankBackfillCompleted = completed
                    self.dailyRankBackfillStatus = "\(completed) of \(callsigns.count) checked, \(successfulCallsigns) saved, \(self.rankQuotaAvailabilityDescription)."
                    self.rankServiceStatus = self.dailyRankBackfillStatus
                }

                if completed.isMultiple(of: 100) || completed == callsigns.count || stoppingFailure != nil {
                    self.applySafeFieldDeltas(from: publishedRecords, to: workingRecords)
                    publishedRecords = workingRecords
                    self.autoSaveActiveWorkspace()
                    hasUnsavedChanges = false
                }
                if stoppingFailure != nil { break }

                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            let wasCancelled = Task.isCancelled
            if hasUnsavedChanges {
                self.applySafeFieldDeltas(from: publishedRecords, to: workingRecords)
                self.autoSaveActiveWorkspace()
            }
            self.isEnriching = false
            self.isDailyRankBackfillRunning = false
            self.enrichmentTask = nil

            if wasCancelled {
                self.dailyRankBackfillStatus = "Stopped after \(self.dailyRankBackfillCompleted) of \(callsigns.count) callsigns. Completed results were saved."
            } else if let stoppingFailure {
                self.dailyRankBackfillStatus = "Paused after \(self.dailyRankBackfillCompleted) callsigns: \(stoppingFailure.localizedDescription)"
            } else {
                self.dailyRankBackfillStatus = "Daily rank backfill finished: \(successfulCallsigns) saved, \(unavailableCallsigns) unavailable, \(self.rankQuotaAvailabilityDescription)."
                self.playActivitySound(.success)
            }
            self.rankServiceStatus = self.dailyRankBackfillStatus
            self.appendLog("QRZ Rank daily backfill: \(self.dailyRankBackfillStatus)")
        }
    }

    @discardableResult
    private func propagateExistingRankValues() -> Int {
        let rankFields = ["RANK_QSO", "RANK_BAND", "RANK_DXCC"]
        var knownValues: [String: [String: String]] = [:]
        let baseRecords = qsoRecords
        var workingRecords = baseRecords

        for record in workingRecords {
            let callsign = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !callsign.isEmpty else { continue }
            for field in rankFields {
                let value = record[field].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, knownValues[callsign]?[field] == nil {
                    knownValues[callsign, default: [:]][field] = value
                }
            }
        }

        var updatedRows = 0
        for index in workingRecords.indices {
            let callsign = workingRecords[index]["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let values = knownValues[callsign] else { continue }
            var rowChanged = false
            for field in rankFields where workingRecords[index][field].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let value = values[field] {
                    workingRecords[index].fields[field] = value
                    rowChanged = true
                }
            }
            if rowChanged { updatedRows += 1 }
        }
        if updatedRows > 0 {
            applySafeFieldDeltas(from: baseRecords, to: workingRecords)
        }
        return updatedRows
    }

    private func applyRankResponse(
        _ response: QRZRankResponse,
        callsign: String,
        checkedDay: String,
        recordIndices: [Int],
        records: inout [QSORecordModel]
    ) {
        let rankValues = [
            "RANK_QSO": response.rank_qso ?? "",
            "RANK_BAND": response.rank_band ?? "",
            "RANK_DXCC": response.rank_countries ?? ""
        ]
        for index in recordIndices where records.indices.contains(index) {
            for (field, value) in rankValues where !value.isEmpty {
                records[index].fields[field] = value
            }
            records[index].fields["APP_YAAM_RANK_CHECKED"] = checkedDay
            records[index].fields["APP_YAAM_RANK_STATUS"] = "FOUND"
            records[index].fields["APP_YAAM_ENRICHED"] = "Y"
        }
    }

    private func markRankLookup(
        callsign: String,
        checkedDay: String,
        status: String,
        recordIndices: [Int],
        records: inout [QSORecordModel]
    ) {
        for index in recordIndices where records.indices.contains(index) {
            records[index].fields["APP_YAAM_RANK_CHECKED"] = checkedDay
            records[index].fields["APP_YAAM_RANK_STATUS"] = status
        }
    }

    private func configureQRZEmailBackfillTimer() {
        qrzEmailBackfillTimer?.invalidate()
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.backfillMissingQRZEmailsBatch()
            }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        qrzEmailBackfillTimer = timer

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await self.backfillMissingQRZEmailsBatch()
        }
    }

    func backfillMissingQRZEmailsNow() {
        Task { @MainActor in
            await backfillMissingQRZEmailsBatch()
        }
    }

    @MainActor
    private func backfillMissingQRZEmailsBatch() async {
        guard !qsoRecords.isEmpty, !isEnriching else { return }
        guard !isQRZEmailBackfillRunning else {
            appendLog("QRZ name/email backfill skipped: previous batch is still running.")
            return
        }
        let hasQRZCookies = await QRZWebKitScraper.shared.hasQRZCookies(allowCredentialPrompt: false)
        let hasHAMQTHCredentials = hasHAMQTHLookupCredentialHint
        guard hasQRZCookies || hasHAMQTHCredentials else {
            appendLog("QRZ/HAMQTH name/email backfill skipped: no saved QRZ.com session cookies or HAMQTH credentials. Open QRZ Login or enter HAMQTH credentials in Settings.")
            return
        }
        isQRZEmailBackfillRunning = true
        defer { isQRZEmailBackfillRunning = false }

        for header in ["NAME", "EMAIL", "QRZ_URL", "APP_YAAM_ENRICHED", "APP_YAAM_EMAIL_CHECKED"] where !tableHeaders.contains(header) {
            tableHeaders.append(header)
        }

        let callsigns = missingQRZContactCallsignBatch(limit: 40)
        guard !callsigns.isEmpty else {
            appendLog("QRZ name/email backfill: no callsigns with missing QRZ name or unchecked missing email remain.")
            return
        }

        qrzEmailBackfillBatchNumber += 1
        let batchNumber = qrzEmailBackfillBatchNumber
        appendLog("QRZ/HAMQTH name/email backfill batch #\(batchNumber): checking \(callsigns.count) callsign(s), starting at \(callsigns.first ?? "-") and ending at \(callsigns.last ?? "-").")
        var updatedNameCount = 0
        var updatedEmailCount = 0
        var checkedWithoutContactCount = 0
        var savedNames: [String] = []
        var savedEmails: [String] = []
        var noContactCallsigns: [String] = []
        var detailLines: [String] = []
        let baseRecords = qsoRecords
        var workingRecords = baseRecords
        var recordIndicesByCallsign: [String: [Int]] = [:]
        for index in workingRecords.indices {
            let callsign = workingRecords[index]["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !callsign.isEmpty { recordIndicesByCallsign[callsign, default: []].append(index) }
        }
        var didChangeRecords = false

        for (offset, callsign) in callsigns.enumerated() {
            if Task.isCancelled { break }

            detailLines.append("[\(offset + 1)/\(callsigns.count)] \(callsign): checking")
            let contact = await fetchContactInfo(
                for: callsign,
                allowQRZWebKitFallback: false,
                allowCredentialPrompt: false
            )
            let checkedMarker = Self.adifDateFormatter.string(from: Date())
            var changedNameForCallsign = false
            var changedEmailForCallsign = false

            for index in recordIndicesByCallsign[callsign] ?? [] where workingRecords.indices.contains(index) {
                workingRecords[index].fields["QRZ_URL"] = "https://www.qrz.com/db/\(callsign)"
                workingRecords[index].fields["APP_YAAM_EMAIL_CHECKED"] = checkedMarker
                didChangeRecords = true

                if let name = contact.name, !name.isEmpty {
                    let currentName = workingRecords[index]["NAME"].trimmingCharacters(in: .whitespacesAndNewlines)
                    let newName = currentName.isEmpty || isGenericQRZName(currentName)
                        ? name
                        : appendedDistinctValue(currentName, newValue: name)
                    if newName != currentName {
                        workingRecords[index].fields["NAME"] = newName
                        updatedNameCount += 1
                        changedNameForCallsign = true
                    }
                } else if isGenericQRZName(workingRecords[index]["NAME"]) {
                    workingRecords[index].fields["NAME"] = ""
                    updatedNameCount += 1
                    changedNameForCallsign = true
                }

                if let email = contact.email, !email.isEmpty {
                    let currentEmail = workingRecords[index]["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
                    if currentEmail != email {
                        workingRecords[index].fields["EMAIL"] = email
                        updatedEmailCount += 1
                        changedEmailForCallsign = true
                    }
                    workingRecords[index].fields["APP_YAAM_ENRICHED"] = "Y"
                }
            }

            if let name = contact.name, !name.isEmpty, changedNameForCallsign {
                savedNames.append("\(callsign)=\(name)")
            }
            if let email = contact.email, !email.isEmpty, changedEmailForCallsign {
                savedEmails.append("\(callsign)=\(email)")
            }

            if contact.name == nil && contact.email == nil {
                checkedWithoutContactCount += 1
                noContactCallsigns.append(callsign)
                detailLines.append("[\(offset + 1)/\(callsigns.count)] \(callsign): no QRZ/HAMQTH name/email; marked checked")
            } else {
                let nameSummary = contact.name ?? "no name"
                let emailSummary = contact.email ?? "no email"
                detailLines.append("[\(offset + 1)/\(callsigns.count)] \(callsign): saved \(nameSummary), \(emailSummary)")
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        if didChangeRecords {
            applySafeFieldDeltas(from: baseRecords, to: workingRecords)
            autoSaveActiveWorkspace()
        }
        let namesSummary = savedNames.isEmpty ? "none" : savedNames.joined(separator: ", ")
        let emailsSummary = savedEmails.isEmpty ? "none" : savedEmails.joined(separator: ", ")
        let noContactSummary = noContactCallsigns.isEmpty ? "none" : noContactCallsigns.joined(separator: ", ")
        appendLog("""
        QRZ/HAMQTH name/email backfill batch #\(batchNumber) details:
        \(detailLines.joined(separator: "\n"))
        QRZ/HAMQTH name/email backfill batch #\(batchNumber) complete: \(updatedNameCount) name row(s) saved [\(namesSummary)]; \(updatedEmailCount) email row(s) saved [\(emailsSummary)]; \(checkedWithoutContactCount) checked/no contact [\(noContactSummary)].
        """)
    }

    private func missingQRZContactCallsignBatch(limit: Int) -> [String] {
        var seen = Set<String>()
        var callsigns: [String] = []

        for record in qsoRecords {
            let callsign = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !callsign.isEmpty, !seen.contains(callsign) else { continue }

            let name = record["NAME"].trimmingCharacters(in: .whitespacesAndNewlines)
            let email = record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
            let checkedEmail = record["APP_YAAM_EMAIL_CHECKED"].trimmingCharacters(in: .whitespacesAndNewlines)
            let needsName = name.isEmpty || isGenericQRZName(name)
            let needsEmail = email.isEmpty && checkedEmail.isEmpty
            guard needsName || needsEmail else { continue }

            seen.insert(callsign)
            callsigns.append(callsign)

            if callsigns.count >= limit {
                break
            }
        }

        return callsigns
    }
    
    private func fetchQRZContactInfo(
        for callsign: String,
        allowWebKitFallback: Bool = false,
        allowCredentialPrompt: Bool = true
    ) async -> QRZEmailFetchResult {
        let rawResult = await fetchQRZEmailFromRawHTML(
            for: callsign,
            allowCredentialPrompt: allowCredentialPrompt
        )
        if rawResult.email != nil || rawResult.notFound || !allowWebKitFallback {
            return rawResult
        }

        let webResult = await QRZWebKitScraper.shared.fetchEmail(for: callsign)
        return QRZEmailFetchResult(
            email: webResult.email,
            name: webResult.name ?? rawResult.name,
            qmailRaw: webResult.qmailRaw.isEmpty ? rawResult.qmailRaw : webResult.qmailRaw,
            qmailDecoded: webResult.qmailDecoded.isEmpty ? rawResult.qmailDecoded : webResult.qmailDecoded,
            notFound: webResult.notFound || rawResult.notFound
        )
    }

    private var hasHAMQTHLookupCredentialHint: Bool {
        let username = UserDefaults.standard.string(forKey: "hamqthUsername")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !username.isEmpty && CredentialVault.hasStoredValueHint(for: .hamqthPassword)
    }

    func fetchContactInfo(
        for callsign: String,
        allowQRZWebKitFallback: Bool = false,
        allowCredentialPrompt: Bool = true
    ) async -> QRZEmailFetchResult {
        async let qrzContact = fetchQRZContactInfo(
            for: callsign,
            allowWebKitFallback: allowQRZWebKitFallback,
            allowCredentialPrompt: allowCredentialPrompt
        )
        async let hamqthContact = fetchHAMQTHContactInfo(
            for: callsign,
            allowCredentialPrompt: allowCredentialPrompt
        )

        let (qrz, hamqth) = await (qrzContact, hamqthContact)
        return QRZEmailFetchResult(
            email: qrz.email ?? hamqth.email,
            name: qrz.name ?? hamqth.name,
            qmailRaw: qrz.qmailRaw,
            qmailDecoded: qrz.qmailDecoded,
            notFound: qrz.notFound && hamqth.notFound
        )
    }

    private func fetchHAMQTHContactInfo(for callsign: String, allowCredentialPrompt: Bool) async -> QRZEmailFetchResult {
        let normalizedCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCallsign.isEmpty else {
            return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
        }

        guard let sessionID = await hamqthSessionIDForLookup(allowCredentialPrompt: allowCredentialPrompt) else {
            return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
        }

        guard var components = URLComponents(string: "https://www.hamqth.com/xml.php") else {
            return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
        }
        components.queryItems = [
            URLQueryItem(name: "id", value: sessionID),
            URLQueryItem(name: "callsign", value: normalizedCallsign),
            URLQueryItem(name: "prg", value: "YAAM")
        ]
        guard let url = components.url else {
            return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
        }

        do {
            let xml = try await fetchHAMQTHXML(from: url)
            if hamqthXMLValue("error", in: xml) != nil {
                hamqthSessionID = nil
                if let refreshedSessionID = await hamqthSessionIDForLookup(
                    forceRefresh: true,
                    allowCredentialPrompt: allowCredentialPrompt
                ) {
                    components.queryItems = [
                        URLQueryItem(name: "id", value: refreshedSessionID),
                        URLQueryItem(name: "callsign", value: normalizedCallsign),
                        URLQueryItem(name: "prg", value: "YAAM")
                    ]
                    if let retryURL = components.url {
                        let retryXML = try await fetchHAMQTHXML(from: retryURL)
                        return decodeHAMQTHContactXML(retryXML, callsign: normalizedCallsign)
                    }
                }
                return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "", notFound: true)
            }

            return decodeHAMQTHContactXML(xml, callsign: normalizedCallsign)
        } catch {
            appendLog("⚠️ HAMQTH lookup failed for \(normalizedCallsign): \(error.localizedDescription)")
            return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
        }
    }

    private func hamqthSessionIDForLookup(
        forceRefresh: Bool = false,
        allowCredentialPrompt: Bool = true
    ) async -> String? {
        if !forceRefresh, let hamqthSessionID, !hamqthSessionID.isEmpty {
            return hamqthSessionID
        }

        let username = UserDefaults.standard.string(forKey: "hamqthUsername")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = allowCredentialPrompt
            ? CredentialVault.value(for: .hamqthPassword)
            : CredentialVault.valueIfAvailableWithoutPrompt(for: .hamqthPassword)
        guard !username.isEmpty, !password.isEmpty else { return nil }

        guard var components = URLComponents(string: "https://www.hamqth.com/xml.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "p", value: password),
            URLQueryItem(name: "prg", value: "YAAM")
        ]
        guard let url = components.url else { return nil }

        do {
            let xml = try await fetchHAMQTHXML(from: url)
            if let sessionID = hamqthXMLValue("session_id", in: xml), !sessionID.isEmpty {
                hamqthSessionID = sessionID
                return sessionID
            }

            let message = hamqthXMLValue("error", in: xml) ?? "No session_id returned."
            appendLog("⚠️ HAMQTH login failed: \(message)")
        } catch {
            appendLog("⚠️ HAMQTH login failed: \(error.localizedDescription)")
        }

        return nil
    }

    private func fetchHAMQTHXML(from url: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("YAAM-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<400).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .isoLatin1) ??
            ""
    }

    private func decodeHAMQTHContactXML(_ xml: String, callsign: String) -> QRZEmailFetchResult {
        let rawName = hamqthXMLValue("nick", in: xml) ??
            hamqthXMLValue("adr_name", in: xml) ??
            hamqthXMLValue("name", in: xml)
        let name = rawName.map { cleanedQRZName($0, callsign: callsign) }.flatMap { $0.isEmpty ? nil : $0 }

        let rawEmail = hamqthXMLValue("email", in: xml) ??
            hamqthXMLValue("mail", in: xml)
        let email = rawEmail.map(cleanedEmailAddress).flatMap { $0.isEmpty ? nil : $0 }
        let notFound = hamqthXMLValue("error", in: xml) != nil || xml.localizedCaseInsensitiveContains("<search/>")

        return QRZEmailFetchResult(
            email: email,
            name: name,
            qmailRaw: "",
            qmailDecoded: "",
            notFound: notFound
        )
    }

    private func hamqthXMLValue(_ tag: String, in xml: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<\(NSRegularExpression.escapedPattern(for: tag))\\b[^>]*>(.*?)</\(NSRegularExpression.escapedPattern(for: tag))>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }

        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, range: range),
              let valueRange = Range(match.range(at: 1), in: xml) else { return nil }

        let value = String(xml[valueRange])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&apos;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value.isEmpty ? nil : value
    }

    private func fetchQRZEmail(for callsign: String) async -> String? {
        if await !QRZWebKitScraper.shared.hasQRZCookies() {
            appendLog("⚠️ No QRZ.com cookies found. Open QRZ Login, sign in, then click Done / Save Session.")
        }

        let result = await fetchContactInfo(for: callsign, allowQRZWebKitFallback: true)
        return result.email
    }

    @MainActor
    func fetchAndStoreQRZEmail(for callsign: String) async -> String? {
        let normalizedCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCallsign.isEmpty else { return nil }

        for header in ["NAME", "EMAIL", "QRZ_URL", "APP_YAAM_ENRICHED", "APP_YAAM_EMAIL_CHECKED"] where !tableHeaders.contains(header) {
            tableHeaders.append(header)
        }

        appendLog("Fetching QRZ/HAMQTH name and email for \(normalizedCallsign)...")
        if await !QRZWebKitScraper.shared.hasQRZCookies() {
            appendLog("⚠️ No QRZ.com cookies found. Public QRZ data and HAMQTH (if configured) will be tried first; open QRZ Login if email is not returned.")
        }

        let result = await fetchContactInfo(for: normalizedCallsign, allowQRZWebKitFallback: true)
        let checkedMarker = Self.adifDateFormatter.string(from: Date())
        var updatedRows = 0
        var updatedNameRows = 0
        var updatedEmailRows = 0

        for index in qsoRecords.indices {
            let rowCallsign = qsoRecords[index]["CALL"]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard rowCallsign == normalizedCallsign else { continue }

            if let name = result.name, !name.isEmpty {
                let currentName = qsoRecords[index]["NAME"].trimmingCharacters(in: .whitespacesAndNewlines)
                if currentName.isEmpty || isGenericQRZName(currentName) {
                    qsoRecords[index].fields["NAME"] = name
                    updatedNameRows += 1
                } else {
                    let mergedName = appendedDistinctValue(currentName, newValue: name)
                    if mergedName != currentName {
                        qsoRecords[index].fields["NAME"] = mergedName
                        updatedNameRows += 1
                    }
                }
            } else if isGenericQRZName(qsoRecords[index]["NAME"]) {
                qsoRecords[index].fields["NAME"] = ""
                updatedNameRows += 1
            }

            if let email = result.email, !email.isEmpty {
                qsoRecords[index].fields["EMAIL"] = email
                qsoRecords[index].fields["APP_YAAM_ENRICHED"] = "Y"
                updatedEmailRows += 1
            }

            qsoRecords[index].fields["QRZ_URL"] = "https://www.qrz.com/db/\(normalizedCallsign)"
            qsoRecords[index].fields["APP_YAAM_EMAIL_CHECKED"] = checkedMarker
            updatedRows += 1
        }

        guard updatedNameRows > 0 || updatedEmailRows > 0 else {
            appendLog("⚠️ No QRZ/HAMQTH name/email found for \(normalizedCallsign). Checked \(updatedRows) row(s).")
            objectWillChange.send()
            autoSaveActiveWorkspace()
            playActivitySound(.failure)
            return nil
        }

        if let email = result.email, !email.isEmpty {
            selectedEmailCallsign = normalizedCallsign
            selectedEmailAddress = email
            selectedEmailTemplate = nil
        }
        objectWillChange.send()
        autoSaveActiveWorkspace()
        appendLog("✅ QRZ/HAMQTH name/email saved for \(normalizedCallsign): \(updatedNameRows) name row(s), \(updatedEmailRows) email row(s).")
        playActivitySound(.success)
        return result.email
    }

    @MainActor
    func openQSLCardEmailComposer(for record: QSORecordModel) {
        let callsign = record["CALL"]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let email = record["EMAIL"]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard record.isConfirmed else {
            alertTitle = "QSO Not Confirmed"
            alertMessage = "QSL card delivery is available after the QSO is confirmed."
            showAlert = true
            playActivitySound(.failure)
            return
        }

        guard !callsign.isEmpty, !email.isEmpty else {
            alertTitle = "Email Address Missing"
            alertMessage = "This confirmed QSO does not have an email address yet. Enrich the callsign or add an EMAIL value first."
            showAlert = true
            playActivitySound(.failure)
            return
        }

        selectedEmailCallsign = callsign
        selectedEmailAddress = email
        selectedEmailQSO = record
        selectedEmailTemplate = "QSL Card Delivery"
        selectedEmailUnconfirmedQSOs = []
        showEmailComposer = true
    }

    private func fetchQRZEmailFromRawHTML(
        for callsign: String,
        allowCredentialPrompt: Bool = true
    ) async -> QRZEmailFetchResult {
        let normalizedCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let url = URL(string: "https://www.qrz.com/db/\(normalizedCallsign)") else {
            return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
        }

        var request = QRZWebKitSession.browserLikeRequest(url: url, timeoutInterval: 12)

        let cookieHeader = await qrzCookieHeader(allowCredentialPrompt: allowCredentialPrompt)
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        for attempt in 1...3 {
            do {
                if attempt > 1 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
                }

                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 12
                configuration.timeoutIntervalForResource = 20
                configuration.waitsForConnectivity = true
                configuration.httpCookieAcceptPolicy = .always
                configuration.httpShouldSetCookies = false
                let session = URLSession(configuration: configuration)
                let (data, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse, !(200..<400).contains(httpResponse.statusCode) {
                    return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
                }

                let html = String(data: data, encoding: .utf8) ??
                    String(data: data, encoding: .isoLatin1) ??
                    ""
                return decodeQRZQmail(from: html, callsign: normalizedCallsign)
            } catch {}
        }

        return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
    }

    private func qrzCookieHeader(allowCredentialPrompt: Bool = true) async -> String {
        await withCheckedContinuation { continuation in
            QRZWebKitSession.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let qrzCookies = cookies
                    .filter { $0.domain.contains("qrz.com") }
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")
                if qrzCookies.isEmpty {
                    continuation.resume(
                        returning: QRZSessionStore.savedCookieHeader(
                            allowUserInteraction: allowCredentialPrompt
                        )
                    )
                } else {
                    continuation.resume(returning: qrzCookies)
                }
            }
        }
    }

    private func decodeQRZQmail(from html: String, callsign: String) -> QRZEmailFetchResult {
        let notFound = isQRZNoResultText(html)
        let contactName = extractedQRZName(from: html, callsign: callsign)

        guard let regex = try? NSRegularExpression(
            pattern: "\\bqmail\\s*=\\s*['\"]([^'\"]+)['\"]",
            options: []
        ) else {
            return QRZEmailFetchResult(email: nil, name: contactName, qmailRaw: "", qmailDecoded: "", notFound: notFound)
        }

        let searchRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: searchRange),
              let qmailRange = Range(match.range(at: 1), in: html) else {
            return QRZEmailFetchResult(email: nil, name: contactName, qmailRaw: "", qmailDecoded: "", notFound: notFound)
        }

        let qmail = String(html[qmailRange])
        let chars = Array(qmail)
        var countText = ""
        var index = chars.count - 1

        while index > 0 {
            let character = chars[index]
            if character == "!" {
                break
            }

            countText.append(character)
            index -= 1
        }

        index -= 1
        guard let count = Int(countText), count > 0 else {
            return QRZEmailFetchResult(email: nil, name: contactName, qmailRaw: qmail, qmailDecoded: "", notFound: notFound)
        }

        var decoded = ""
        for _ in 0..<count {
            guard index >= 0 else { break }
            decoded.append(chars[index])
            index -= 2
        }

        let email = cleanedEmailAddress(decoded)
        return QRZEmailFetchResult(email: email.isEmpty ? nil : email, name: contactName, qmailRaw: qmail, qmailDecoded: decoded, notFound: notFound)
    }

    private func extractedQRZName(from html: String, callsign: String) -> String? {
        if let description = metaContent(named: "og:description", in: html) ?? metaContent(named: "description", in: html) {
            let name = cleanedQRZDescriptionName(description, callsign: callsign)
            if !name.isEmpty {
                return name
            }
        }

        return nil
    }

    private func metaContent(named metaName: String, in html: String) -> String? {
        guard let tagRegex = try? NSRegularExpression(
            pattern: "<meta\\b[^>]*>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for tagMatch in tagRegex.matches(in: html, range: range) {
            guard let tagRange = Range(tagMatch.range, in: html) else { continue }
            let attributes = htmlAttributes(in: String(html[tagRange]))
            let name = attributes["property"] ?? attributes["name"]
            guard name?.caseInsensitiveCompare(metaName) == .orderedSame else { continue }
            if let content = attributes["content"] {
                return content
            }
        }

        return nil
    }

    private func htmlAttributes(in tag: String) -> [String: String] {
        guard let attributeRegex = try? NSRegularExpression(
            pattern: "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*([\"'])(.*?)\\2",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return [:]
        }

        var attributes: [String: String] = [:]
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        for match in attributeRegex.matches(in: tag, range: range) {
            guard match.numberOfRanges > 3,
                  let keyRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 3), in: tag) else {
                continue
            }
            attributes[String(tag[keyRange]).lowercased()] = String(tag[valueRange])
        }
        return attributes
    }

    private func cleanedQRZDescriptionName(_ rawValue: String, callsign: String) -> String {
        var candidate = rawValue
            .replacingOccurrences(of: "\\s+personal biography\\b.*$", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let commaRange = candidate.range(of: ",") {
            candidate = String(candidate[..<commaRange.lowerBound])
        }

        candidate = candidate
            .replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: callsign))\\b", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleanedQRZName(candidate, callsign: callsign)
    }

    private func cleanedQRZName(_ rawValue: String, callsign: String) -> String {
        let withoutTags = rawValue
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let stripped = withoutTags
            .replacingOccurrences(of: "\\s*[-–]\\s*QRZ\\.com.*$", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !stripped.isEmpty,
              stripped.localizedCaseInsensitiveCompare(callsign) != .orderedSame,
              !stripped.contains("@"),
              !isGenericQRZName(stripped),
              !isQRZNoResultText(stripped),
              stripped.count <= 80 else {
            return ""
        }

        return stripped
    }

    private func isGenericQRZName(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized.contains("callsign lookup") ||
            normalized.contains("qrz ham radio") ||
            isQRZNoResultText(value) ||
            normalized == "world" ||
            normalized == "ham radio" ||
            normalized == "qrz.com"
    }

    private func isQRZNoResultText(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("produced no results") ||
            normalized.contains("search for") && normalized.contains("no results") ||
            normalized.contains("callsign not found") ||
            normalized.contains("not found in the qrz database")
    }

    private func appendedDistinctValue(_ currentValue: String, newValue: String) -> String {
        let normalizedNew = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedNew.isEmpty else { return currentValue }

        let existingParts = currentValue
            .components(separatedBy: CharacterSet(charactersIn: "/;,"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !existingParts.contains(normalizedNew),
              currentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != normalizedNew else {
            return currentValue
        }

        return "\(currentValue) / \(newValue)"
    }

    func applyCapturedQRZEmail(callsign: String, email rawEmail: String) {
        let normalizedCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let email = cleanedEmailAddress(rawEmail)

        guard !normalizedCallsign.isEmpty, !email.isEmpty else {
            showNativeAlert(
                title: "QRZ Email Not Saved",
                message: "No valid callsign or email address was available to save into the log table."
            )
            playActivitySound(.failure)
            return
        }

        for header in ["EMAIL", "QRZ_URL", "APP_YAAM_ENRICHED", "APP_YAAM_EMAIL_CHECKED"] where !tableHeaders.contains(header) {
            tableHeaders.append(header)
        }

        var updatedRows = 0
        for index in qsoRecords.indices {
            let rowCallsign = qsoRecords[index]["CALL"]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()

            guard rowCallsign == normalizedCallsign else { continue }

            qsoRecords[index].fields["EMAIL"] = email
            qsoRecords[index].fields["QRZ_URL"] = "https://www.qrz.com/db/\(normalizedCallsign)"
            qsoRecords[index].fields["APP_YAAM_ENRICHED"] = "Y"
            qsoRecords[index].fields["APP_YAAM_EMAIL_CHECKED"] = Self.adifDateFormatter.string(from: Date())
            updatedRows += 1
        }

        selectedEmailCallsign = normalizedCallsign
        selectedEmailAddress = email
        selectedEmailTemplate = nil

        guard updatedRows > 0 else {
            showNativeAlert(
                title: "QRZ Email Captured",
                message: "\(normalizedCallsign): \(email)\n\nNo matching CALL rows were found in the current log table."
            )
            playActivitySound(.notice)
            return
        }

        objectWillChange.send()
        autoSaveActiveWorkspace()
        appendLog("✅ QRZ email saved to \(updatedRows) table row(s) for \(normalizedCallsign): \(email)")
        playActivitySound(.success)
        showNativeAlert(
            title: "QRZ Email Saved",
            message: "\(email) was saved to \(updatedRows) row(s) for \(normalizedCallsign)."
        )
    }

    private func cleanedEmailAddress(_ rawValue: String) -> String {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>\"'()[]{}"))
        let normalized = rawValue
            .replacingOccurrences(of: "mailto:", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "mailto", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .trimmingCharacters(in: separators)

        guard let regex = try? NSRegularExpression(
            pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}(?=\\b|\\s|$)",
            options: [.caseInsensitive]
        ) else {
            return ""
        }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: range),
              let emailRange = Range(match.range, in: normalized) else {
            return ""
        }

        return String(normalized[emailRange])
            .trimmingCharacters(in: separators.union(CharacterSet(charactersIn: ".,;:")))
    }

    func sendEmail(
        to recipient: String,
        subject: String,
        body: String,
        attachmentData: Data? = nil,
        attachmentName: String? = nil,
        playSound: Bool = true,
        completion: @escaping (Bool, String) -> Void
    ) {
        let targetCallsign = selectedEmailCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        let rawHost = UserDefaults.standard.string(forKey: "smtpHost")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let host = rawHost.isEmpty ? "smtp.gmail.com" : rawHost
        
        let rawPort = UserDefaults.standard.string(forKey: "smtpPort")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let port = rawPort.isEmpty ? "465" : rawPort
        
        let user = UserDefaults.standard.string(forKey: "smtpUser")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawPass = CredentialVault.value(for: .smtpPassword)
        
        let pass = rawPass.replacingOccurrences(of: " ", with: "")
        
        guard !host.isEmpty, !user.isEmpty, !pass.isEmpty else {
            if playSound { playActivitySound(.failure) }
            completion(false, "SMTP MISSING: Check Preferences for Host, User, and Pass.")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            let dateStr = dateFormatter.string(from: Date())
            let messageID = "<\(UUID().uuidString)@\(host)>"
            
            var emailContentData = Data()
            
            if let attachmentData = attachmentData, let attachmentName = attachmentName {
                let boundary = "YAAM-Boundary-\(UUID().uuidString)"
                
                let headers = """
                From: \(user)
                To: \(recipient)
                Subject: \(subject)
                Date: \(dateStr)
                Message-ID: \(messageID)
                MIME-Version: 1.0
                Content-Type: multipart/mixed; boundary="\(boundary)"
                
                
                """.replacingOccurrences(of: "\n", with: "\r\n")
                
                emailContentData.append(headers.data(using: .utf8)!)
                
                let textPart = """
                --\(boundary)
                Content-Type: text/plain; charset=UTF-8
                Content-Transfer-Encoding: 7bit
                
                \(body)
                
                
                """.replacingOccurrences(of: "\n", with: "\r\n")
                
                emailContentData.append(textPart.data(using: .utf8)!)
                
                let attachmentHeader = """
                --\(boundary)
                Content-Type: application/pdf; name="\(attachmentName)"
                Content-Transfer-Encoding: base64
                Content-Disposition: attachment; filename="\(attachmentName)"
                
                
                """.replacingOccurrences(of: "\n", with: "\r\n")
                
                emailContentData.append(attachmentHeader.data(using: .utf8)!)
                
                let base64String = attachmentData.base64EncodedString(options: [.lineLength64Characters, .endLineWithCarriageReturn])
                emailContentData.append((base64String + "\r\n\r\n").data(using: .utf8)!)
                
                let endBoundary = "--\(boundary)--\r\n"
                emailContentData.append(endBoundary.data(using: .utf8)!)
            } else {
                let emailContent = """
                From: \(user)
                To: \(recipient)
                Subject: \(subject)
                Date: \(dateStr)
                Message-ID: \(messageID)
                Content-Type: text/plain; charset=UTF-8
                Content-Transfer-Encoding: 8bit
                
                \(body)
                """
                
                let normalizedEmailContent = emailContent
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                    .replacingOccurrences(of: "\n", with: "\r\n")

                if let data = normalizedEmailContent.data(using: .utf8) {
                    emailContentData.append(data)
                }
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            
            process.environment = ProcessInfo.processInfo.environment
            
            let isPort465 = (port == "465")
            let urlScheme = isPort465 ? "smtps" : "smtp"
            
            var arguments = [
                "--url", "\(urlScheme)://\(host):\(port)",
                "--user", "\(user):\(pass)",
                "--mail-from", user,
                "--mail-rcpt", recipient,
                "--verbose",
                "--insecure",
                "--ipv4"
            ]
            
            if !isPort465 {
                arguments.append("--ssl-reqd")
            }
            
            let tempEmailURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("eml")
            arguments.append(contentsOf: ["--upload-file", tempEmailURL.path])
            process.arguments = arguments

            let outputPipe = Pipe()
            
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            do {
                try emailContentData.write(to: tempEmailURL, options: .atomic)
                try process.run()
                process.waitUntilExit()
                try? FileManager.default.removeItem(at: tempEmailURL)
                
                let errData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let outputLog = String(data: errData, encoding: .utf8) ?? "EMPTY LOG"
                
                if process.terminationStatus == 0 {
                    DispatchQueue.main.async {
                        self.recordEmailHistory(callsign: targetCallsign, email: recipient, subject: subject, status: "Sent")
                        if playSound { self.playActivitySound(.success) }
                    }
                    completion(true, "Email successfully sent to \(recipient)!")
                } else {
                    DispatchQueue.main.async {
                        self.recordEmailHistory(callsign: targetCallsign, email: recipient, subject: subject, status: "Failed")
                        if playSound { self.playActivitySound(.failure) }
                    }
                    completion(false, "ERROR \(process.terminationStatus):\n\n" + outputLog)
                }
            } catch {
                try? FileManager.default.removeItem(at: tempEmailURL)
                DispatchQueue.main.async {
                    self.recordEmailHistory(callsign: targetCallsign, email: recipient, subject: subject, status: "Failed")
                    if playSound { self.playActivitySound(.failure) }
                }
                completion(false, "Process Failed: \(error.localizedDescription)")
            }
        }
    }

    func bulkEmailRecipients(limit: Int = 50) -> [BulkEmailRecipient] {
        callsignsWithNoConfirmedQSOs
            .filter { !$0.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(limit)
            .map { item in
                let normalizedCall = item.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let unconfirmedQSOs = qsoRecords.filter { record in
                    record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCall &&
                    !record.isConfirmed
                }
                return BulkEmailRecipient(
                    callsign: item.callsign,
                    email: item.email,
                    qsoCount: item.qsoCount,
                    bands: item.bands,
                    countries: item.countries,
                    qso: unconfirmedQSOs.first,
                    unconfirmedQSOs: unconfirmedQSOs
                )
            }
    }

    func sendBulkConfirmationEmails(
        recipients: [BulkEmailRecipient],
        templateName: String,
        completion: @escaping (Int, Int) -> Void
    ) {
        let selectedRecipients = Array(recipients.prefix(25))
        guard !selectedRecipients.isEmpty else {
            completion(0, 0)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var sentCount = 0
            var failedCount = 0
            let semaphore = DispatchSemaphore(value: 0)

            for recipient in selectedRecipients {
                DispatchQueue.main.async {
                    self.selectedEmailCallsign = recipient.callsign
                    self.selectedEmailAddress = recipient.email
                    self.selectedEmailQSO = recipient.qso
                    self.selectedEmailTemplate = nil
                    self.selectedEmailUnconfirmedQSOs = recipient.unconfirmedQSOs

                    let message = self.bulkEmailMessage(for: recipient, templateName: templateName)
                    self.sendEmail(to: recipient.email, subject: message.subject, body: message.body, playSound: false) { success, _ in
                        if success {
                            sentCount += 1
                        } else {
                            failedCount += 1
                        }
                        semaphore.signal()
                    }
                }

                semaphore.wait()
                Thread.sleep(forTimeInterval: 1.0)
            }

            DispatchQueue.main.async {
                self.selectedEmailQSO = nil
                self.selectedEmailUnconfirmedQSOs = []
                self.playActivitySound(failedCount == 0 ? .success : .failure)
                completion(sentCount, failedCount)
            }
        }
    }

    func recentConfirmedQSLBatchCandidateCount(limit: Int = 40) -> Int {
        recentConfirmedQSLBatchCandidates(limit: limit).count
    }

    func recentUnconfirmedReminderBatchRecipientCount(limit: Int = 40) -> Int {
        recentUnconfirmedReminderRecipients(limit: limit).count
    }

    func sendRecentConfirmedQSLCardsBatch(limit: Int = 40) {
        let candidates = recentConfirmedQSLBatchCandidates(limit: limit)
        guard !candidates.isEmpty else {
            showNativeAlert(
                title: "No Recent Confirmed QSOs",
                message: "No confirmed QSOs from the last 24 hours with an EMAIL value were found."
            )
            playActivitySound(.failure)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Send QSL Cards in Bulk?"
        alert.informativeText = """
        YAAM will send QSL card emails for \(candidates.count) confirmed QSO(s) from the last 24 hours.

        Each email will include a generated QSL card PDF attachment. The batch limit is \(limit) emails per run.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Send \(candidates.count) QSL Cards")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isSendingBatchMail = true
        batchMailStatus = "Sending QSL cards 0/\(candidates.count)"
        appendLog("Batch QSL card delivery started: \(candidates.count) confirmed QSO(s).")
        sendConfirmedQSLCardEmails(records: candidates) { sent, failed in
            self.isSendingBatchMail = false
            self.batchMailStatus = "QSL cards complete: \(sent) sent, \(failed) failed"
            self.appendLog("Batch QSL card delivery complete: \(sent) sent, \(failed) failed.")
            self.alertTitle = "Batch QSL Cards Complete"
            self.alertMessage = "\(sent) QSL card email(s) sent, \(failed) failed."
            self.showAlert = true
        }
    }

    func sendRecentUnconfirmedReminderBatch(limit: Int = 40) {
        let recipients = recentUnconfirmedReminderRecipients(limit: limit)
        guard !recipients.isEmpty else {
            showNativeAlert(
                title: "No Recent Unconfirmed QSOs",
                message: "No unconfirmed QSOs from the last 7 days with an EMAIL value were found."
            )
            playActivitySound(.failure)
            return
        }

        let repeatedRecipients = recipients.compactMap { recipient -> String? in
            guard let previous = latestEmailHistory(for: recipient.callsign) else { return nil }
            return "\(recipient.callsign) (\(formattedEmailHistoryDate(previous.date)))"
        }

        let alert = NSAlert()
        alert.messageText = "Send Friendly Confirmation Reminders?"
        alert.informativeText = """
        YAAM will send reminder emails to \(recipients.count) callsign(s) with unconfirmed QSOs from the last 7 days.

        The email text includes a friendly note explaining that YAAM.app may automatically send this reminder.
        \(repeatedRecipients.isEmpty ? "" : "\nPreviously emailed callsigns:\n" + repeatedRecipients.prefix(12).joined(separator: "\n") + (repeatedRecipients.count > 12 ? "\n...and \(repeatedRecipients.count - 12) more." : ""))
        """
        alert.alertStyle = repeatedRecipients.isEmpty ? .informational : .warning
        alert.addButton(withTitle: "Send \(recipients.count) Reminders")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isSendingBatchMail = true
        batchMailStatus = "Sending reminders 0/\(recipients.count)"
        appendLog("Recent unconfirmed reminder batch started: \(recipients.count) recipient(s).")
        sendRecentUnconfirmedReminderEmails(recipients: recipients) { sent, failed in
            self.isSendingBatchMail = false
            self.batchMailStatus = "Reminders complete: \(sent) sent, \(failed) failed"
            self.appendLog("Recent unconfirmed reminder batch complete: \(sent) sent, \(failed) failed.")
            self.alertTitle = "Reminder Batch Complete"
            self.alertMessage = "\(sent) reminder email(s) sent, \(failed) failed."
            self.showAlert = true
        }
    }

    private func sendConfirmedQSLCardEmails(records: [QSORecordModel], completion: @escaping (Int, Int) -> Void) {
        let selectedRecords = Array(records.prefix(40))
        let station = qslCardStationInfoFromDefaults()

        DispatchQueue.global(qos: .userInitiated).async {
            var sentCount = 0
            var failedCount = 0
            let semaphore = DispatchSemaphore(value: 0)

            for record in selectedRecords {
                let callsign = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let email = record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !callsign.isEmpty, !email.isEmpty else {
                    failedCount += 1
                    continue
                }

                var attachmentData: Data?
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")

                DispatchQueue.main.sync {
                    do {
                        try QSLCardRenderer.exportPDF(record: record, station: station, to: tempURL)
                        attachmentData = try Data(contentsOf: tempURL)
                    } catch {
                        self.appendLog("QSL card export failed for \(callsign): \(error.localizedDescription)")
                    }
                    try? FileManager.default.removeItem(at: tempURL)
                }

                guard let attachmentData else {
                    failedCount += 1
                    continue
                }

                DispatchQueue.main.async {
                    self.selectedEmailCallsign = callsign
                    self.selectedEmailAddress = email
                    self.selectedEmailQSO = record
                    self.selectedEmailTemplate = "QSL Card Delivery"
                    self.selectedEmailUnconfirmedQSOs = []

                    let message = self.qslCardDeliveryMessage(for: record)
                    let attachmentName = "\(QSLCardRenderer.cleanFileComponent(station.callsign))_QSL_\(QSLCardRenderer.cleanFileComponent(callsign)).pdf"
                    self.sendEmail(
                        to: email,
                        subject: message.subject,
                        body: message.body,
                        attachmentData: attachmentData,
                        attachmentName: attachmentName,
                        playSound: false
                    ) { success, _ in
                        if success {
                            sentCount += 1
                        } else {
                            failedCount += 1
                        }
                        self.batchMailStatus = "Sending QSL cards \(sentCount + failedCount)/\(selectedRecords.count)"
                        semaphore.signal()
                    }
                }

                semaphore.wait()
                Thread.sleep(forTimeInterval: 1.0)
            }

            DispatchQueue.main.async {
                self.selectedEmailQSO = nil
                self.selectedEmailTemplate = nil
                self.selectedEmailUnconfirmedQSOs = []
                self.playActivitySound(failedCount == 0 ? .success : .failure)
                completion(sentCount, failedCount)
            }
        }
    }

    private func sendRecentUnconfirmedReminderEmails(recipients: [BulkEmailRecipient], completion: @escaping (Int, Int) -> Void) {
        let selectedRecipients = Array(recipients.prefix(40))

        DispatchQueue.global(qos: .userInitiated).async {
            var sentCount = 0
            var failedCount = 0
            let semaphore = DispatchSemaphore(value: 0)

            for recipient in selectedRecipients {
                DispatchQueue.main.async {
                    self.selectedEmailCallsign = recipient.callsign
                    self.selectedEmailAddress = recipient.email
                    self.selectedEmailQSO = recipient.qso
                    self.selectedEmailTemplate = "Friendly Reminder"
                    self.selectedEmailUnconfirmedQSOs = recipient.unconfirmedQSOs

                    let message = self.friendlyRecentConfirmationReminderMessage(for: recipient)
                    self.sendEmail(to: recipient.email, subject: message.subject, body: message.body, playSound: false) { success, _ in
                        if success {
                            sentCount += 1
                        } else {
                            failedCount += 1
                        }
                        self.batchMailStatus = "Sending reminders \(sentCount + failedCount)/\(selectedRecipients.count)"
                        semaphore.signal()
                    }
                }

                semaphore.wait()
                Thread.sleep(forTimeInterval: 1.0)
            }

            DispatchQueue.main.async {
                self.selectedEmailQSO = nil
                self.selectedEmailTemplate = nil
                self.selectedEmailUnconfirmedQSOs = []
                self.playActivitySound(failedCount == 0 ? .success : .failure)
                completion(sentCount, failedCount)
            }
        }
    }

    private func recentConfirmedQSLBatchCandidates(limit: Int) -> [QSORecordModel] {
        recentRecords(days: 1)
            .filter { record in
                record.isConfirmed &&
                !record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { lhs, rhs in
                (lhs["QSO_DATE"] + lhs["TIME_ON"]) > (rhs["QSO_DATE"] + rhs["TIME_ON"])
            }
            .prefix(limit)
            .map { $0 }
    }

    private func recentUnconfirmedReminderRecipients(limit: Int) -> [BulkEmailRecipient] {
        let records = recentRecords(days: 7).filter { record in
            !record.isConfirmed &&
            !record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let grouped = Dictionary(grouping: records) { record in
            record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }

        return grouped.keys.sorted().compactMap { callsign in
            guard !callsign.isEmpty, let qsos = grouped[callsign], let first = qsos.first else { return nil }
            let email = first["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty else { return nil }
            let bands = Set(qsos.map { $0["BAND"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
                .sorted()
                .joined(separator: ", ")
            let countries = Set(qsos.map { $0["COUNTRY"].trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                .sorted()
                .joined(separator: ", ")
            return BulkEmailRecipient(
                callsign: callsign,
                email: email,
                qsoCount: qsos.count,
                bands: bands,
                countries: countries,
                qso: first,
                unconfirmedQSOs: qsos
            )
        }
        .prefix(limit)
        .map { $0 }
    }

    private func recentRecords(days: Int) -> [QSORecordModel] {
        let calendar = Calendar(identifier: .gregorian)
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else { return [] }
        return qsoRecords.filter { record in
            guard let qsoDate = adifDateTime(for: record) else { return false }
            return qsoDate >= cutoff
        }
    }

    private func adifDateTime(for record: QSORecordModel) -> Date? {
        let date = record["QSO_DATE"].trimmingCharacters(in: .whitespacesAndNewlines)
        guard date.count == 8,
              let year = Int(date.prefix(4)),
              let month = Int(date.dropFirst(4).prefix(2)),
              let day = Int(date.suffix(2)) else {
            return nil
        }

        let time = (record["TIME_ON"].isEmpty ? record["TIME_OFF"] : record["TIME_ON"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isNumber }
        let hour = time.count >= 2 ? Int(time.prefix(2)) ?? 0 : 0
        let minute = time.count >= 4 ? Int(time.dropFirst(2).prefix(2)) ?? 0 : 0
        let second = time.count >= 6 ? Int(time.dropFirst(4).prefix(2)) ?? 0 : 0

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date
    }

    private func qslCardStationInfoFromDefaults() -> QSLCardStationInfo {
        let profile = activeStationProfile
        let stationCallsign = currentStationCallsign == "DEFAULT" ? "NOCALL" : currentStationCallsign
        let grid = profile?.normalizedGrid ?? ""
        let radio = profile?.radioModel ?? ""
        let antenna = profile?.antennaDescription ?? ""
        let power = profile?.powerWatts ?? 100
        return QSLCardStationInfo(
            callsign: stationCallsign,
            grid: grid,
            radio: radio,
            antenna: antenna,
            powerWatts: power
        )
    }

    private func qslCardDeliveryMessage(for record: QSORecordModel) -> (subject: String, body: String) {
        let myCall = currentStationCallsign == "DEFAULT" ? "NOCALL" : currentStationCallsign
        let targetCall = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let name = record["NAME"].trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = name.isEmpty ? targetCall : name
        let details = confirmationRequestDetailsBlock(for: [record])

        return (
            "QSL Card for our QSO - \(targetCall) de \(myCall)",
            """
            Hello \(greeting),

            I hope you are doing very well.

            Thank you for the confirmed QSO. I have attached my QSL card for our contact.

            \(details)

            Many thanks again, and I look forward to hearing you again soon.

            Warm 73,
            \(myCall)
            """
        )
    }

    private func friendlyRecentConfirmationReminderMessage(for recipient: BulkEmailRecipient) -> (subject: String, body: String) {
        let myCall = currentStationCallsign == "DEFAULT" ? "NOCALL" : currentStationCallsign
        let qsoText = recipient.qsoCount == 1 ? "one recent QSO" : "\(recipient.qsoCount) recent QSOs"
        let details = confirmationRequestDetailsBlock(for: recipient.unconfirmedQSOs)

        return (
            "Friendly QSO confirmation reminder - \(myCall)",
            """
            Hi \(recipient.callsign),

            I hope you are doing well. Thank you for \(qsoText) during the last week.

            I noticed these QSOs are still unconfirmed in my log. When you have a moment, I would really appreciate it if you could confirm or upload them on LoTW or QRZ.

            \(details)

            If you have already received this email before, please excuse the duplicate. It is because YAAM.app can automatically send this friendly reminder from my logbook, and I am still tuning that workflow.

            Thanks again for the contact and hope to meet you on the air soon.

            73,
            \(myCall)
            """
        )
    }

    private func bulkEmailMessage(for recipient: BulkEmailRecipient, templateName: String) -> (subject: String, body: String) {
        let myCall = currentStationCallsign
        let qsos = recipient.unconfirmedQSOs.isEmpty ? recipient.qso.map { [$0] } ?? [] : recipient.unconfirmedQSOs
        let bandCount = uniqueBandCount(in: qsos)
        let details = confirmationRequestDetailsBlock(for: qsos)
        let qsoText = qsos.count == 1 ? "1 unconfirmed QSO" : "\(qsos.count) unconfirmed QSOs"
        let bandText = bandCount == 1 ? "1 band" : "\(bandCount) bands"

        switch templateName {
        case "QSL Card Request":
            return (
                "QSL request for \(qsoText) on \(bandText) - \(myCall)",
                """
                Hello \(recipient.callsign),

                Thank you for our QSOs. I currently have \(qsoText) with you across \(bandText) that are still not confirmed in my log.

                \(details)

                I am following up on these confirmations for award tracking and to keep my logbook accurate. I would appreciate a QSL confirmation when convenient.

                73,
                \(myCall)
                """
            )
        default:
            return (
                "LoTW/QRZ confirmation request for \(qsoText) on \(bandText) - \(myCall)",
                """
                Hello \(recipient.callsign),

                Could you please upload or confirm our QSOs on LoTW or QRZ? I currently have \(qsoText) with you across \(bandText) that are still not confirmed.

                \(details)

                I am following up on these confirmations for award tracking and to keep my logbook accurate and organized.

                Thank you and 73,
                \(myCall)
                """
            )
        }
    }

    func confirmationRequestMessage(
        callsign: String,
        templateName: String,
        qsos: [QSORecordModel]
    ) -> (subject: String, body: String) {
        let myCall = currentStationCallsign
        let normalizedCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let bandCount = uniqueBandCount(in: qsos)
        let qsoText = qsos.count == 1 ? "1 unconfirmed QSO" : "\(qsos.count) unconfirmed QSOs"
        let bandText = bandCount == 1 ? "1 band" : "\(bandCount) bands"
        let details = confirmationRequestDetailsBlock(for: qsos)

        switch templateName {
        case "QSL Card Request":
            return (
                "QSL request for \(qsoText) on \(bandText) - \(myCall)",
                """
                Hello \(normalizedCall),

                Thank you for our QSOs. I currently have \(qsoText) with you across \(bandText) that are still not confirmed in my log.

                \(details)

                I am following up on these confirmations for award tracking and to keep my logbook accurate. I would appreciate a QSL confirmation when convenient.

                73,
                \(myCall)
                """
            )
        default:
            return (
                "LoTW/QRZ confirmation request for \(qsoText) on \(bandText) - \(myCall)",
                """
                Hello \(normalizedCall),

                Could you please upload or confirm our QSOs on LoTW or QRZ? I currently have \(qsoText) with you across \(bandText) that are still not confirmed.

                \(details)

                I am following up on these confirmations for award tracking and to keep my logbook accurate and organized.

                Thank you and 73,
                \(myCall)
                """
            )
        }
    }

    private func confirmationRequestDetailsBlock(for qsos: [QSORecordModel]) -> String {
        guard !qsos.isEmpty else { return "QSO Details:\n- No unconfirmed QSO details found in the current log." }

        let sortedQSOs = qsos.sorted { lhs, rhs in
            let left = lhs["QSO_DATE"] + lhs["TIME_ON"]
            let right = rhs["QSO_DATE"] + rhs["TIME_ON"]
            return left < right
        }

        let lines = sortedQSOs.enumerated().map { index, qso in
            let date = formattedADIFDate(qso["QSO_DATE"].trimmingCharacters(in: .whitespacesAndNewlines))
            let time = formattedADIFTime(qso["TIME_ON"].trimmingCharacters(in: .whitespacesAndNewlines))
            let band = qso["BAND"].trimmingCharacters(in: .whitespacesAndNewlines)
            let mode = qso["MODE"].trimmingCharacters(in: .whitespacesAndNewlines)
            let freq = qso["FREQ"].trimmingCharacters(in: .whitespacesAndNewlines)
            let rstSent = qso["RST_SENT"].trimmingCharacters(in: .whitespacesAndNewlines)
            let rstRcvd = qso["RST_RCVD"].trimmingCharacters(in: .whitespacesAndNewlines)

            let parts = [
                date.isEmpty ? nil : date,
                time.isEmpty ? nil : "\(time) UTC",
                band.isEmpty ? nil : band,
                mode.isEmpty ? nil : mode,
                freq.isEmpty ? nil : "\(freq) MHz",
                rstSent.isEmpty ? nil : "RST sent \(rstSent)",
                rstRcvd.isEmpty ? nil : "RST received \(rstRcvd)"
            ].compactMap { $0 }

            return "\(index + 1). " + (parts.isEmpty ? "QSO details unavailable" : parts.joined(separator: " | "))
        }

        return "QSO Details:\n" + lines.joined(separator: "\n")
    }

    private func uniqueBandCount(in qsos: [QSORecordModel]) -> Int {
        let bands = Set(qsos.map { $0["BAND"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
        return max(bands.count, qsos.isEmpty ? 0 : 1)
    }

    private func formattedADIFDate(_ rawDate: String) -> String {
        guard rawDate.count == 8 else { return rawDate }
        let y = rawDate.prefix(4)
        let m = rawDate.dropFirst(4).prefix(2)
        let d = rawDate.suffix(2)
        return "\(y)-\(m)-\(d)"
    }

    private func formattedADIFTime(_ rawTime: String) -> String {
        guard rawTime.count >= 4 else { return rawTime }
        let h = rawTime.prefix(2)
        let m = rawTime.dropFirst(2).prefix(2)
        let s = rawTime.count >= 6 ? ":\(rawTime.dropFirst(4).prefix(2))" : ""
        return "\(h):\(m)\(s)"
    }

    private var emailHistoryURL: URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("YAAM")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("EmailHistory.json")
    }

    private func loadEmailHistory() {
        guard let url = emailHistoryURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([EmailHistoryEntry].self, from: data) else {
            return
        }

        emailHistory = decoded.sorted { $0.date > $1.date }
        refreshEmailHistoryColumns()
    }

    private func recordEmailHistory(callsign: String, email: String, subject: String, status: String) {
        let entry = EmailHistoryEntry(
            id: UUID(),
            date: Date(),
            callsign: callsign,
            email: email,
            subject: subject,
            status: status
        )

        emailHistory.insert(entry, at: 0)
        emailHistory = Array(emailHistory.prefix(500))
        saveEmailHistory()
        updateEmailHistoryColumn(with: entry)
    }

    func latestEmailHistory(for callsign: String) -> EmailHistoryEntry? {
        let normalizedCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCallsign.isEmpty else { return nil }

        return emailHistory
            .filter { $0.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCallsign }
            .sorted { $0.date > $1.date }
            .first
    }

    func formattedEmailHistoryDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func refreshEmailHistoryColumns() {
        guard !emailHistory.isEmpty, !qsoRecords.isEmpty else { return }

        for header in ["APP_YAAM_LAST_EMAIL"] where !tableHeaders.contains(header) {
            tableHeaders.append(header)
        }

        let latestByCallsign = Dictionary(grouping: emailHistory, by: {
            $0.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }).compactMapValues { entries in
            entries.sorted { $0.date > $1.date }.first
        }

        for index in qsoRecords.indices {
            let callsign = qsoRecords[index]["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let entry = latestByCallsign[callsign] else { continue }
            qsoRecords[index].fields["APP_YAAM_LAST_EMAIL"] = emailHistorySummary(for: entry)
        }
    }

    private func updateEmailHistoryColumn(with entry: EmailHistoryEntry) {
        let normalizedCallsign = entry.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCallsign.isEmpty else { return }

        if !tableHeaders.contains("APP_YAAM_LAST_EMAIL") {
            tableHeaders.append("APP_YAAM_LAST_EMAIL")
        }

        let summary = emailHistorySummary(for: entry)
        var updatedRows = 0
        for index in qsoRecords.indices {
            let rowCallsign = qsoRecords[index]["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard rowCallsign == normalizedCallsign else { continue }
            qsoRecords[index].fields["APP_YAAM_LAST_EMAIL"] = summary
            updatedRows += 1
        }

        if updatedRows > 0 {
            objectWillChange.send()
            autoSaveActiveWorkspace()
        }
    }

    private func emailHistorySummary(for entry: EmailHistoryEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(formatter.string(from: entry.date)) | \(entry.status) | \(entry.subject)"
    }

    private func saveEmailHistory() {
        guard let url = emailHistoryURL,
              let data = try? JSONEncoder().encode(emailHistory) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private enum QRZConfirmedFetchResult {
        case success([[String: String]])
        case failure(String)
    }

    private func fetchQRZConfirmedRecords(
        apiKey: String,
        sinceDateString: String?,
        completion: @escaping (QRZConfirmedFetchResult) -> Void
    ) {
        guard let endpoint = URL(string: "https://logbook.qrz.com/api") else {
            completion(.failure("Invalid QRZ Logbook API endpoint."))
            return
        }

        var options = ["TYPE:ADIF", "STATUS:CONFIRMED"]
        if let sinceDateString, !sinceDateString.isEmpty {
            options.append("MODSINCE:\(sinceDateString)")
        }

        let bodyItems = [
            "KEY=\(apiKey)",
            "ACTION=FETCH",
            "OPTION=\(options.joined(separator: ","))"
        ]

        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("YAAM-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyItems.joined(separator: "&").data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error.localizedDescription))
                return
            }

            guard let data,
                  let responseText = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                completion(.failure("QRZ returned an empty response."))
                return
            }

            guard let qrzResponse = self.parseQRZLogbookResponse(responseText) else {
                completion(.failure("QRZ returned an unreadable response."))
                return
            }

            guard qrzResponse.result == "OK" else {
                completion(.failure("RESULT=\(qrzResponse.result)&COUNT=\(qrzResponse.count)"))
                return
            }

            guard qrzResponse.adif.localizedCaseInsensitiveContains("<eor>") else {
                completion(.failure("QRZ returned no ADIF records. RESULT=\(qrzResponse.result)&COUNT=\(qrzResponse.count)"))
                return
            }

            let (_, records) = parseADIF(content: qrzResponse.adif)
            completion(.success(records))
        }.resume()
    }

    private func parseQRZLogbookResponse(_ responseText: String) -> (result: String, count: String, adif: String)? {
        let result = qrzResponseValue("RESULT", in: responseText)?.uppercased() ?? ""
        let count = qrzResponseValue("COUNT", in: responseText) ?? "0"

        guard let adifMarkerRange = responseText.range(of: "ADIF=", options: .caseInsensitive) else {
            return (result: result, count: count, adif: "")
        }

        let rawADIF = String(responseText[adifMarkerRange.upperBound...])
            .removingPercentEncoding?
            .replacingOccurrences(of: "+", with: " ") ??
            String(responseText[adifMarkerRange.upperBound...])

        return (result: result, count: count, adif: decodeHTMLEntities(rawADIF))
    }

    private func qrzResponseValue(_ key: String, in responseText: String) -> String? {
        let pattern = "(?:^|&)\(NSRegularExpression.escapedPattern(for: key))=([^&]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(responseText.startIndex..<responseText.endIndex, in: responseText)
        guard let match = regex.firstMatch(in: responseText, range: range),
              let valueRange = Range(match.range(at: 1), in: responseText) else { return nil }
        return String(responseText[valueRange]).removingPercentEncoding ?? String(responseText[valueRange])
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
    }

    private func isQRZConfirmedRecord(_ record: [String: String]) -> Bool {
        let status = (
            record["APP_QRZLOG_STATUS"] ??
            record["QRZLOG_QSL_RCVD"] ??
            record["QSL_RCVD"] ??
            ""
        ).uppercased()

        return status == "CONFIRMED" || status == "Y" || status == "C" || status == "V"
    }

    private func qrzRecord(_ serverRecord: [String: String], matches localRecord: QSORecordModel) -> Bool {
        let serverCall = normalizeCallsign(serverRecord["CALL"] ?? "")
        let localCall = normalizeCallsign(localRecord["CALL"])
        guard !serverCall.isEmpty, serverCall == localCall else { return false }

        let serverDate = cleanDate(serverRecord["QSO_DATE"] ?? "")
        let localDate = cleanDate(localRecord["QSO_DATE"])
        guard !serverDate.isEmpty, serverDate == localDate else { return false }

        let serverTime = cleanTime(serverRecord["TIME_ON"] ?? serverRecord["TIME_OFF"] ?? "")
        let localTime = cleanTime(localRecord["TIME_ON"].isEmpty ? localRecord["TIME_OFF"] : localRecord["TIME_ON"])
        if !serverTime.isEmpty, !localTime.isEmpty, serverTime.prefix(4) != localTime.prefix(4) {
            return false
        }

        let serverBand = cleanBand(serverRecord["BAND"] ?? "")
        let localBand = cleanBand(localRecord["BAND"])
        if !serverBand.isEmpty, !localBand.isEmpty, serverBand != localBand {
            return false
        }

        let serverMode = cleanMode(serverRecord["MODE"] ?? "")
        let localMode = cleanMode(localRecord["MODE"])
        if !serverMode.isEmpty, !localMode.isEmpty, serverMode != localMode {
            return false
        }

        return true
    }

    private func legacySyncConfirmations(
        forceFullSync: Bool = false,
        sources: Set<SyncSource> = [.lotw, .qrz],
        showCompletionAlert: Bool = true,
        completion: ((ConfirmationSyncSummary) -> Void)? = nil
    ) {
        guard !qsoRecords.isEmpty else {
            appendLog("Error: No log loaded to sync.")
            completion?(ConfirmationSyncSummary())
            return
        }

        guard !isSyncingAPI else {
            appendLog("Confirmation sync skipped: another confirmation sync is already running.")
            completion?(ConfirmationSyncSummary())
            return
        }
        
        let lotwUser = UserDefaults.standard.string(forKey: "lotwUsername")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lotwPass = CredentialVault.value(for: .lotwPassword)
        let qrzKey = activeQRZAPIKey

        let syncLoTW = sources.contains(.lotw) && !lotwUser.isEmpty && !lotwPass.isEmpty
        let syncQRZ = sources.contains(.qrz) && !qrzKey.isEmpty

        if !syncLoTW && !syncQRZ {
            self.alertTitle = "Credentials Required 🔑"
            self.alertMessage = "Configure credentials for the selected LoTW or QRZ confirmation source in Settings."
            self.showAlert = true
            self.playActivitySound(.failure)
            completion?(ConfirmationSyncSummary())
            return
        }
        
        let confirmationHeaders = ["LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "QSL_RCVD"]
        for h in confirmationHeaders {
            if !tableHeaders.contains(h) {
                tableHeaders.append(h)
            }
        }
        
        isSyncingAPI = true
        if syncLoTW { beginSyncStatus(.lotw, detail: "Downloading LoTW confirmations...") }
        if syncQRZ { beginSyncStatus(.qrz, detail: "Downloading QRZ confirmations...") }
        
        let isFirstFullSync = forceFullSync || (totalConfirmedCount < 50 && qsoRecords.count > 1000)
        let lastLoTWSyncDate = isFirstFullSync ? nil : (UserDefaults.standard.object(forKey: "lastLoTWSyncDate") as? Date)
        let lastQRZSyncDate = forceFullSync ? nil : (UserDefaults.standard.object(forKey: "lastQRZSyncDate") as? Date)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let lotwSinceDateString = lastLoTWSyncDate != nil ? dateFormatter.string(from: lastLoTWSyncDate!) : "1900-01-01"
        let qrzSinceDateString = lastQRZSyncDate.map { dateFormatter.string(from: $0) }
        let matchIndex = ConfirmationMatchIndex(records: qsoRecords.map(\.fields))
        
        if isFirstFullSync {
            appendLog("🚀 Launching FULL Historical QSL Sync (Fetching all confirmations since 1900)...")
        } else {
            appendLog("🔄 Launching Incremental QSL Sync (LoTW since \(lotwSinceDateString), QRZ \(qrzSinceDateString.map { "since \($0)" } ?? "full confirmed sync"))...")
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var newlyConfirmedCount = 0
            var lotwChangedCount = 0
            var qrzChangedCount = 0
            var lotwFetchedCount = 0
            var qrzFetchedCount = 0
            var lotwFailed = false
            var qrzFailed = false
            var syncLogs: [String] = []
            
            let group = DispatchGroup()
            
            if syncLoTW {
                group.enter()
                if let encodedUser = lotwUser.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let encodedPass = lotwPass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let lotwEndpoint = URL(string: "https://lotw.arrl.org/lotwuser/lotwreport.adi?login=\(encodedUser)&password=\(encodedPass)&qso_query=1&qso_qslsince=\(lotwSinceDateString)") {
                    
                    var request = URLRequest(url: lotwEndpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 45)
                    request.setValue("YAAM-macOS/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")
                    
                    URLSession.shared.dataTask(with: request) { data, _, error in
                        defer { group.leave() }

                        if let error {
                            DispatchQueue.main.async {
                                lotwFailed = true
                                syncLogs.append("LoTW Error: \(error.localizedDescription)")
                            }
                            return
                        }

                        if let data = data, let reportADIF = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                            if !reportADIF.lowercased().contains("invalid password") && !reportADIF.lowercased().contains("access denied") {
                                let (_, serverRecords) = parseADIF(content: reportADIF)

                                DispatchQueue.main.async {
                                    lotwFetchedCount += serverRecords.count
                                    syncLogs.append("LoTW: Server returned \(serverRecords.count) confirmed QSL records.")
                                    for rec in serverRecords {
                                        let call = self.normalizeCallsign(rec["CALL"] ?? "")
                                        let date = self.cleanDate(rec["QSO_DATE"] ?? "")
                                        let band = self.cleanBand(rec["BAND"] ?? "")
                                        let lotwRcvd = (rec["LOTW_QSL_RCVD"] ?? rec["QSL_RCVD"] ?? "").uppercased()
                                        let lotwConfirmedDate = self.cleanDate(
                                            rec["LOTW_QSLRDATE"] ??
                                            rec["APP_LOTW_QSLRDATE"] ??
                                            rec["QSLRDATE"] ??
                                            ""
                                        )
                                        
                                        if lotwRcvd == "Y" || lotwRcvd == "V" {
                                            let candidates = matchIndex.candidates(callsign: call, date: date, band: band)
                                            for i in candidates where self.qsoRecords.indices.contains(i) {
                                                let qCall = self.normalizeCallsign(self.qsoRecords[i]["CALL"])
                                                let qDate = self.cleanDate(self.qsoRecords[i]["QSO_DATE"])
                                                let qBand = self.cleanBand(self.qsoRecords[i]["BAND"])
                                                
                                                if qCall == call && qDate == date && (qBand.isEmpty || band.isEmpty || qBand == band) {
                                                    if !lotwConfirmedDate.isEmpty {
                                                        self.qsoRecords[i].fields["LOTW_QSLRDATE"] = lotwConfirmedDate
                                                    }

                                                    if !self.qsoRecords[i].isConfirmed || self.qsoRecords[i].fields["LOTW_QSL_RCVD"] != "Y" {
                                                        self.qsoRecords[i].fields["LOTW_QSL_RCVD"] = "Y"
                                                        self.qsoRecords[i].fields["QSL_RCVD"] = "Y"
                                                        self.rememberConfirmedRecord(self.qsoRecords[i])
                                                        newlyConfirmedCount += 1
                                                        lotwChangedCount += 1
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                DispatchQueue.main.async {
                                    lotwFailed = true
                                    syncLogs.append("LoTW Error: Invalid credentials.")
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                lotwFailed = true
                                syncLogs.append("LoTW Error: Empty or unreadable response.")
                            }
                        }
                    }.resume()
                } else {
                    DispatchQueue.main.async {
                        lotwFailed = true
                        syncLogs.append("LoTW Error: Unable to create request URL.")
                    }
                    group.leave()
                }
            }
            
            if syncQRZ {
                group.enter()
                self.fetchQRZConfirmedRecords(apiKey: qrzKey, sinceDateString: qrzSinceDateString) { result in

                    switch result {
                    case .success(let serverRecords):
                        DispatchQueue.main.async {
                            qrzFetchedCount += serverRecords.count
                            syncLogs.append("QRZ: Server returned \(serverRecords.count) confirmed logbook records.")
                            for rec in serverRecords {
                                guard self.isQRZConfirmedRecord(rec) else { continue }
                                let qrzConfirmedDate = self.cleanDate(
                                    rec["APP_QRZLOG_QSLDATE"] ??
                                    rec["QRZLOG_QSLRDATE"] ??
                                    rec["APP_QRZLOG_QSLRDATE"] ??
                                    rec["QSLRDATE"] ??
                                    ""
                                )

                                let candidates = matchIndex.candidates(
                                    callsign: rec["CALL"] ?? "",
                                    date: rec["QSO_DATE"] ?? ""
                                )
                                for i in candidates where self.qsoRecords.indices.contains(i) {
                                    guard self.qrzRecord(rec, matches: self.qsoRecords[i]) else { continue }

                                    if !qrzConfirmedDate.isEmpty {
                                        self.qsoRecords[i].fields["APP_QRZLOG_QSLDATE"] = qrzConfirmedDate
                                    }

                                    if self.qsoRecords[i]["QRZLOG_QSL_RCVD"].uppercased() != "Y" {
                                        self.qsoRecords[i].fields["QRZLOG_QSL_RCVD"] = "Y"
                                        self.qsoRecords[i].fields["QSL_RCVD"] = "Y"
                                        self.qsoRecords[i].fields["APP_QRZLOG_STATUS"] = "CONFIRMED"
                                        self.rememberConfirmedRecord(self.qsoRecords[i])
                                        newlyConfirmedCount += 1
                                        qrzChangedCount += 1
                                    }
                                }
                            }
                        }
                        group.leave()
                    case .failure(let message):
                        if qrzSinceDateString != nil, message.uppercased().contains("RESULT=FAIL"), message.uppercased().contains("COUNT=0") {
                            DispatchQueue.main.async {
                                syncLogs.append("QRZ: Incremental confirmed sync returned no records, retrying full confirmed sync...")
                            }
                            self.fetchQRZConfirmedRecords(apiKey: qrzKey, sinceDateString: nil) { fallbackResult in
                                defer { group.leave() }

                                switch fallbackResult {
                                case .success(let serverRecords):
                                    DispatchQueue.main.async {
                                        qrzFetchedCount += serverRecords.count
                                        syncLogs.append("QRZ: Full confirmed sync returned \(serverRecords.count) confirmed logbook records.")
                                        for rec in serverRecords {
                                            guard self.isQRZConfirmedRecord(rec) else { continue }
                                            let qrzConfirmedDate = self.cleanDate(
                                                rec["APP_QRZLOG_QSLDATE"] ??
                                                rec["QRZLOG_QSLRDATE"] ??
                                                rec["APP_QRZLOG_QSLRDATE"] ??
                                                rec["QSLRDATE"] ??
                                                ""
                                            )

                                            let candidates = matchIndex.candidates(
                                                callsign: rec["CALL"] ?? "",
                                                date: rec["QSO_DATE"] ?? ""
                                            )
                                            for i in candidates where self.qsoRecords.indices.contains(i) {
                                                guard self.qrzRecord(rec, matches: self.qsoRecords[i]) else { continue }

                                                if !qrzConfirmedDate.isEmpty {
                                                    self.qsoRecords[i].fields["APP_QRZLOG_QSLDATE"] = qrzConfirmedDate
                                                }

                                                if self.qsoRecords[i]["QRZLOG_QSL_RCVD"].uppercased() != "Y" {
                                                    self.qsoRecords[i].fields["QRZLOG_QSL_RCVD"] = "Y"
                                                    self.qsoRecords[i].fields["QSL_RCVD"] = "Y"
                                                    self.qsoRecords[i].fields["APP_QRZLOG_STATUS"] = "CONFIRMED"
                                                    self.rememberConfirmedRecord(self.qsoRecords[i])
                                                    newlyConfirmedCount += 1
                                                    qrzChangedCount += 1
                                                }
                                            }
                                        }
                                    }
                                case .failure(let fallbackMessage):
                                    DispatchQueue.main.async {
                                        qrzFailed = true
                                        syncLogs.append("QRZ Error: \(fallbackMessage)")
                                    }
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                qrzFailed = true
                                syncLogs.append("QRZ Error: \(message)")
                            }
                            group.leave()
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                self.isSyncingAPI = false
                if syncLoTW, !lotwFailed {
                    UserDefaults.standard.set(Date(), forKey: "lastLoTWSyncDate")
                }
                if syncQRZ, !qrzFailed {
                    UserDefaults.standard.set(Date(), forKey: "lastQRZSyncDate")
                }
                
                for log in syncLogs {
                    self.appendLog(log)
                }
                
                self.objectWillChange.send()
                self.autoSaveActiveWorkspace()

                let lotwMessage = lotwFailed
                    ? (syncLogs.last(where: { $0.hasPrefix("LoTW Error") }) ?? "LoTW synchronization failed")
                    : "\(lotwFetchedCount) checked, \(lotwChangedCount) confirmations updated"
                let qrzMessage = qrzFailed
                    ? (syncLogs.last(where: { $0.hasPrefix("QRZ Error") }) ?? "QRZ synchronization failed")
                    : "\(qrzFetchedCount) checked, \(qrzChangedCount) confirmations updated"
                if syncLoTW {
                    self.finishSyncStatus(
                        .lotw,
                        state: lotwFailed ? .failure : .success,
                        detail: lotwMessage,
                        changed: lotwChangedCount
                    )
                }
                if syncQRZ {
                    self.finishSyncStatus(
                        .qrz,
                        state: qrzFailed ? .failure : .success,
                        detail: qrzMessage,
                        changed: qrzChangedCount
                    )
                }

                let summary = ConfirmationSyncSummary(
                    lotwFetched: lotwFetchedCount,
                    qrzFetched: qrzFetchedCount,
                    lotwChanged: lotwChangedCount,
                    qrzChanged: qrzChangedCount,
                    lotwMessage: lotwMessage,
                    qrzMessage: qrzMessage,
                    lotwFailed: lotwFailed,
                    qrzFailed: qrzFailed
                )
                
                if newlyConfirmedCount > 0 {
                    self.appendLog("✅ Sync Complete: \(newlyConfirmedCount) new QSL confirmations matched!")
                    if showCompletionAlert {
                        self.alertTitle = "QSL Sync Complete 🟢"
                        self.alertMessage = "Successfully updated \(newlyConfirmedCount) confirmations in your logbook!"
                        self.showAlert = true
                    }
                    self.playActivitySound(.success)
                } else {
                    self.appendLog("⚪ Sync Complete: All confirmations are up to date (\(summary.fetched) records checked).")
                    if showCompletionAlert {
                        self.alertTitle = "Log Up To Date ⚪"
                        self.alertMessage = "Checked \(summary.fetched) cloud records. All confirmations in your log are up to date."
                        self.showAlert = true
                    }
                    self.playActivitySound(syncLogs.contains { $0.lowercased().contains("error") } ? .failure : .success)
                }
                completion?(summary)
            }
        }
    }

    func deleteRecord(id: UUID) {
        if let idx = qsoRecords.firstIndex(where: { $0.id == id }) {
            guard createDestructiveCheckpointIfNeeded(reason: "Before deleting QSO records") else { return }
            let recordNum = qsoRecords[idx].index
            let call = qsoRecords[idx]["CALL"]
            qsoRecords.remove(at: idx)
            selectedRecordIDs.remove(id)
            
            for i in 0..<qsoRecords.count {
                qsoRecords[i].index = i + 1
            }
            appendLog("Deleted QSO record #\(recordNum) (\(call)).")
            autoSaveActiveWorkspace(
                allowEmptyReplacement: qsoRecords.isEmpty,
                replaceMissingRecords: true
            )
        }
    }

    func updateCell(recordID: UUID, header: String, newValue: String) {
        if let idx = qsoRecords.firstIndex(where: { $0.id == recordID }) {
            qsoRecords[idx][header] = newValue
            appendLog("Updated record #\(qsoRecords[idx].index) [\(header)] ➔ '\(qsoRecords[idx][header])'")
            autoSaveActiveWorkspace()
        }
    }

    @discardableResult
    func populateMissingGridSquaresFromCoordinates() -> Int {
        var updatedCount = 0

        for index in qsoRecords.indices {
            let existingGrid = qsoRecords[index]["GRIDSQUARE"].trimmingCharacters(in: .whitespacesAndNewlines)
            let alternateGrid = qsoRecords[index]["GRID"].trimmingCharacters(in: .whitespacesAndNewlines)
            if GridLocator.fourCharacterGrid(from: existingGrid) != nil ||
                GridLocator.fourCharacterGrid(from: alternateGrid) != nil {
                continue
            }

            let latitude = firstCoordinateValue(in: qsoRecords[index], keys: ["LAT", "LATITUDE"])
            let longitude = firstCoordinateValue(in: qsoRecords[index], keys: ["LON", "LONG", "LONGITUDE"])
            guard let grid = GridLocator.fourCharacterGrid(latitude: latitude, longitude: longitude) else {
                continue
            }

            qsoRecords[index].fields["GRIDSQUARE"] = grid
            updatedCount += 1
        }

        guard updatedCount > 0 else { return 0 }
        if !tableHeaders.contains("GRIDSQUARE") {
            if let countryIndex = tableHeaders.firstIndex(of: "COUNTRY") {
                tableHeaders.insert("GRIDSQUARE", at: countryIndex + 1)
            } else {
                tableHeaders.append("GRIDSQUARE")
            }
        }

        appendLog("Derived 4-character Maidenhead grids for \(updatedCount) QSO record(s) from LAT/LON coordinates.")
        autoSaveActiveWorkspace()
        return updatedCount
    }

    private func firstCoordinateValue(in record: QSORecordModel, keys: [String]) -> String {
        for key in keys {
            let value = record[key].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return ""
    }

    func deleteColumn(header: String) {
        guard createDestructiveCheckpointIfNeeded(reason: "Before deleting column \(header)") else { return }
        tableHeaders.removeAll(where: { $0 == header })
        for i in 0..<qsoRecords.count {
            qsoRecords[i].fields.removeValue(forKey: header)
        }
        appendLog("Removed column '\(header)' from log structure.")
        autoSaveActiveWorkspace()
    }

    private var confirmationCacheFileURL: URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("YAAM")
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("confirmed_cache.json")
    }
    
    private func loadPersistentConfirmationCache() {
        guard let fileURL = confirmationCacheFileURL,
              let data = try? Data(contentsOf: fileURL),
              let keys = try? JSONDecoder().decode(Set<String>.self, from: data) else { return }
        self.localConfirmedKeys = keys
    }
    
    private func savePersistentConfirmationCache() {
        guard let fileURL = confirmationCacheFileURL,
              let data = try? JSONEncoder().encode(localConfirmedKeys) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    private func normalizeCallsign(_ call: String) -> String {
        var clean = call.uppercased().trimmingCharacters(in: .whitespaces)
        if let slashIdx = clean.firstIndex(of: "/") {
            clean = String(clean[..<slashIdx])
        }
        return clean
    }
    
    private func cleanDate(_ dateStr: String) -> String {
        return dateStr.replacingOccurrences(of: "-", with: "")
                      .replacingOccurrences(of: "/", with: "")
                      .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanBand(_ bandStr: String) -> String {
        return bandStr.uppercased()
                      .replacingOccurrences(of: "METER", with: "M")
                      .replacingOccurrences(of: "METERS", with: "M")
                      .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanTime(_ timeStr: String) -> String {
        return timeStr
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanMode(_ modeStr: String) -> String {
        return modeStr.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyPersistentConfirmationCache(to records: inout [QSORecordModel]) -> Int {
        var matchedCount = 0
        for i in 0..<records.count {
            let call = normalizeCallsign(records[i]["CALL"])
            let date = cleanDate(records[i]["QSO_DATE"])
            let band = cleanBand(records[i]["BAND"])
            
            let strictKey = "\(call)_\(date)_\(band)"
            let fallbackKey = "\(call)_\(date)"
            
            if localConfirmedKeys.contains(strictKey) || localConfirmedKeys.contains(fallbackKey) {
                if !records[i].isConfirmed {
                    records[i].fields["LOTW_QSL_RCVD"] = "Y"
                    records[i].fields["QRZLOG_QSL_RCVD"] = "Y"
                    records[i].fields["QSL_RCVD"] = "Y"
                    matchedCount += 1
                }
            } else if records[i].isConfirmed {
                localConfirmedKeys.insert(strictKey)
                localConfirmedKeys.insert(fallbackKey)
            }
        }
        
        if matchedCount > 0 {
            savePersistentConfirmationCache()
        }
        return matchedCount
    }

    private func rememberConfirmedRecord(_ record: QSORecordModel) {
        let call = normalizeCallsign(record["CALL"])
        let date = cleanDate(record["QSO_DATE"])
        let band = cleanBand(record["BAND"])
        guard !call.isEmpty, !date.isEmpty else { return }

        localConfirmedKeys.insert("\(call)_\(date)")
        if !band.isEmpty {
            localConfirmedKeys.insert("\(call)_\(date)_\(band)")
        }
        savePersistentConfirmationCache()
    }

    func rememberConfirmedRecords(_ records: [QSORecordModel]) {
        var didChange = false
        for record in records {
            let call = normalizeCallsign(record["CALL"])
            let date = cleanDate(record["QSO_DATE"])
            let band = cleanBand(record["BAND"])
            guard !call.isEmpty, !date.isEmpty else { continue }

            didChange = localConfirmedKeys.insert("\(call)_\(date)").inserted || didChange
            if !band.isEmpty {
                didChange = localConfirmedKeys.insert("\(call)_\(date)_\(band)").inserted || didChange
            }
        }
        if didChange { savePersistentConfirmationCache() }
    }

    func saveCurrentLog() {
        if isMasterMode {
            do {
                try persistCurrentWorkspace(reason: "Manual save")
                appendLog("Master Log saved to the protected database.")
            } catch {
                databaseStatus = error.localizedDescription
                appendLog("Master Log save failed: \(error.localizedDescription)")
            }
            return
        }

        guard let url = loadedFileURL else {
            saveAsCurrentLog()
            return
        }
        writeRecordsToFileAsync(records: qsoRecords.map { $0.fields }, to: url)
    }

    func saveAsCurrentLog() {
        let exportingMasterLog = isMasterMode
        let panel = NSSavePanel()
        var types: [UTType] = [.plainText]
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        types.append(.commaSeparatedText)
        
        panel.allowedContentTypes = types
        if !exportingMasterLog, loadedFileURL == nil {
            let cleanName = loadedFileName
                .replacingOccurrences(of: "Guest: ", with: "")
                .replacingOccurrences(of: " (SDR Control)", with: "")
            let baseName = URL(fileURLWithPath: cleanName).deletingPathExtension().lastPathComponent
            panel.nameFieldStringValue = "\(baseName.isEmpty ? "SmartSDR" : baseName)_YAAM.adi"
        } else {
            panel.nameFieldStringValue = loadedFileName.isEmpty ? "modified_log.adi" : loadedFileName
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            writeRecordsToFileAsync(records: qsoRecords.map { $0.fields }, to: url)
            if !exportingMasterLog {
                self.loadedFileURL = url
                self.loadedFileName = url.lastPathComponent
            }
        }
    }

    func exportFilteredLogAs() {
        let panel = NSSavePanel()
        var types: [UTType] = [.plainText]
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        types.append(.commaSeparatedText)
        
        panel.allowedContentTypes = types
        let baseName = loadedFileName.isEmpty ? "filtered_log" : URL(fileURLWithPath: loadedFileName).deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName)_Filtered_Slice.adi"
        
        if panel.runModal() == .OK, let url = panel.url {
            let filteredDicts = filteredRecords.map { $0.fields }
            writeRecordsToFileAsync(records: filteredDicts, to: url)
        }
    }

    func openDatabaseExport(profileID: UUID? = nil) {
        convertSource = 1
        convertDatabaseProfileID = profileID ?? activeStationProfileID
        selectedTab = 1
        UserDefaults.standard.set(1, forKey: "selectedTab")
    }

    private func writeRecordsToFileAsync(records: [[String: String]], to url: URL) {
        isLoading = true
        let isCSV = url.pathExtension.lowercased() == "csv"
        let headers = tableHeaders
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            if isCSV {
                let csvContent = generateCSV(headers: headers, records: records)
                let finalOutput = "\u{FEFF}" + csvContent
                do {
                    try finalOutput.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.appendLog("Successfully wrote CSV file to: \(url.lastPathComponent)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.appendLog("Error saving CSV file: \(error.localizedDescription)")
                    }
                }
            } else {
                let adifOutput = generateADIF(originalContent: "", records: records)
                do {
                    try adifOutput.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.appendLog("Successfully wrote ADIF file to: \(url.lastPathComponent)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.appendLog("Error saving ADIF file: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func showAboutDialog() {
        showAboutSheet = true
    }

    func checkForUpdates() {
        appendLog("Checking GitHub repository for updates...")
        isCheckingUpdates = true
        
        guard let url = URL(string: "https://api.github.com/repos/fact0real/yaam/releases/latest") else {
            isCheckingUpdates = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCheckingUpdates = false
                
                if let error = error {
                    self.appendLog("Update check failed: \(error.localizedDescription)")
                    self.showNativeAlert(
                        title: "Update Check Failed 🔴",
                        message: "Unable to connect to GitHub releases.\n\nError: \(error.localizedDescription)"
                    )
                    return
                }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let latestTag = json["tag_name"] as? String {
                    
                    let cleanTag = latestTag.replacingOccurrences(of: "v", with: "")
                    let htmlUrl = json["html_url"] as? String
                    let downloadURL = htmlUrl != nil ? URL(string: htmlUrl!) : nil
                    
                    if cleanTag != self.currentVersion {
                        self.appendLog("YAAM Update available: \(latestTag)")
                        self.showNativeAlert(
                            title: "YAAM Update Available! 🚀",
                            message: "A new version (\(latestTag)) is available on GitHub!\nYour current version is v\(self.currentVersion).\n\nWould you like to open the release page?",
                            actionURL: downloadURL
                        )
                    } else {
                        self.appendLog("YAAM is up to date (v\(self.currentVersion)).")
                        self.showNativeAlert(
                            title: "Up to Date 🟢",
                            message: "You are running the latest version of YAAM (v\(self.currentVersion))."
                        )
                    }
                } else {
                    self.showNativeAlert(
                        title: "Up to Date 🟢",
                        message: "You are running the latest version of YAAM (v\(self.currentVersion))."
                    )
                }
            }
        }.resume()
    }
    
    func showNativeAlert(title: String, message: String, actionURL: URL? = nil) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            
            if let _ = actionURL {
                alert.addButton(withTitle: "Open Release Page")
                alert.addButton(withTitle: "Cancel")
            } else {
                alert.addButton(withTitle: "OK")
            }
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn, let url = actionURL {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
