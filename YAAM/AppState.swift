//
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

// MARK: - API Response Models (Swift 6 Safe)
nonisolated struct QRZRankResponse: Codable, Sendable {
    let bid: String?
    let callsign: String?
    let country_iso: String?
    let country_name: String?
    let rank_band: String?
    let rank_countries: String?
    let rank_qso: String?
    let score_band: String?
    let score_countries: String?
    let score_qso: String?
}

// MARK: - Band Statistics Model
struct BandStatModel: Identifiable {
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
struct UnconfirmedBandCountryStatModel: Identifiable {
    let id = UUID()
    let band: String
    let countries: [UnconfirmedCountryStatModel]
}

struct UnconfirmedCountryStatModel: Identifiable {
    let id = UUID()
    let country: String
    let qsoCount: Int
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

struct SolarForecastPoint: Identifiable {
    var id: String { dateLabel }
    let date: Date
    let dateLabel: String
    let solarFlux: Int
    let aIndex: Int
    let kpIndex: Int
}

// MARK: - Country Statistics Model
struct CountryStatModel: Identifiable {
    let id = UUID()
    let country: String
    let flag: String
    let qsoCount: Int
    let confirmedCount: Int
    let unconfirmedCount: Int
}

// MARK: - Comprehensive DXCC & Country/Territory Flag Lookup Engine
func countryToFlag(_ country: String) -> String {
    let clean = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if clean.isEmpty { return "🌐" }
    
    switch clean {
    // MARK: - Special DXCC Island Entities, UN & Territories
    case "rodriguez is.", "rodrigues is.", "rodrigues island", "rodrigues": return "🇲🇺"
    case "dodecanese": return "🇬🇷"
    case "montserrat": return "🇲🇸"
    case "western sahara": return "🇪🇭"
    case "central kiribati", "kiribati": return "🇰🇮"
    case "united nations hq", "un hq", "united nations": return "🇺🇳"
    case "fiji islands", "fiji": return "🇫🇯"
    case "canary is.", "canary islands", "canary island", "canary": return "🇮🇨"
    case "sardinia": return "🇮🇹"
    case "crete": return "🇬🇷"
    case "azores", "azores is.": return "🇵🇹"
    case "balearic is.", "balearic islands": return "🇪🇸"
    case "bonaire": return "🇧🇶"
    case "corsica": return "🇫🇷"
    case "madeira is.", "madeira": return "🇵🇹"
    case "ceuta & melilla", "ceuta and melilla", "ceuta": return "🇪🇸"
    case "curacao": return "🇨🇼"
    case "aruba": return "🇦🇼"
    case "sint maarten": return "🇸🇽"
    case "st. martin", "saint martin": return "🇲🇫"
    case "svalbard": return "🇸🇯"
    case "jan mayen": return "🇸🇯"
    case "faroe is.", "faroe islands", "faroe": return "🇫🇴"
    case "greenland": return "🇬🇱"
    case "aland is.", "aland islands", "aland": return "🇦🇽"
    case "market reef": return "🇫🇮"
    case "mount athos": return "🇬🇷"
    case "isle of man": return "🇮🇲"
    case "jersey": return "🇯🇪"
    case "guernsey": return "🇬🇬"
    case "gibraltar": return "🇬🇮"
    case "hawaii": return "🇺🇸"
    case "alaska": return "🇺🇸"
    case "puerto rico": return "🇵🇷"
    case "virgin is.", "us virgin is.", "u.s. virgin islands", "virgin islands": return "🇻🇮"
    case "british virgin is.", "british virgin islands": return "🇻🇬"
    case "guam": return "🇬🇺"
    case "northern mariana is.": return "🇲🇵"
    case "american samoa": return "🇦🇸"
    case "martinique": return "🇲🇶"
    case "guadeloupe": return "🇬🇵"
    case "reunion", "reunion is.": return "🇷🇪"
    case "mayotte": return "🇾🇹"
    case "french guiana": return "🇬🇫"
    case "bermuda": return "🇧🇲"
    case "cayman is.", "cayman islands": return "🇰🇾"
    case "falkland is.", "falkland islands": return "🇫🇰"
    case "saint helena": return "🇸🇭"
    case "tristan da cunha": return "🇸🇭"
    case "ascension is.": return "🇸🇭"
    case "galapagos is.", "galapagos": return "🇪🇨"
    case "easter is.", "easter island": return "🇨🇱"
    case "lord howe is.": return "🇦🇺"
    case "norfolk is.": return "🇳🇫"
    case "christmas is.": return "🇨🇽"
    case "cocos (keeling) is.": return "🇨🇨"

    // MARK: - Americas & Caribbean
    case "belize": return "🇧ℤ"
    case "united states", "united states of america", "usa", "u.s.a.": return "🇺🇸"
    case "canada": return "🇨🇦"
    case "mexico": return "🇲🇽"
    case "brazil": return "🇧🇷"
    case "argentina": return "🇦🇷"
    case "chile": return "🇨🇱"
    case "colombia": return "🇨🇴"
    case "peru": return "🇵🇪"
    case "venezuela": return "🇻🇪"
    case "ecuador": return "🇪🇨"
    case "bolivia": return "🇧🇴"
    case "paraguay": return "🇵🇾"
    case "uruguay": return "🇺🇾"
    case "guyana": return "🇬🇾"
    case "suriname": return "🇸🇷"
    case "cuba": return "🇨🇺"
    case "dominican republic": return "🇩🇴"
    case "jamaica": return "🇯🇲"
    case "haiti": return "🇭🇹"
    case "costa rica": return "🇨🇷"
    case "panama": return "🇵🇦"
    case "guatemala": return "🇬🇹"
    case "honduras": return "🇭🇳"
    case "el salvador": return "🇸🇻"
    case "nicaragua": return "🇳🇮"
    case "bahamas": return "🇧🇸"
    case "trinidad & tobago", "trinidad and tobago": return "🇹🇹"
    case "barbados": return "🇧🇧"

    // MARK: - Africa
    case "chad": return "🇹🇩"
    case "cameroon": return "🇨🇲"
    case "congo", "republic of congo", "democratic republic of congo", "dr congo", "dr congo / zaire": return "🇨🇬"
    case "malawi": return "🇲🇼"
    case "benin": return "🇧🇯"
    case "south africa": return "🇿🇦"
    case "egypt": return "🇪🇬"
    case "nigeria": return "🇳🇬"
    case "kenya": return "🇰🇪"
    case "morocco": return "🇲🇦"
    case "algeria": return "🇩🇿"
    case "tunisia": return "🇹🇳"
    case "ethiopia": return "🇪🇹"
    case "ghana": return "🇬🇭"
    case "senegal": return "🇸🇳"
    case "cote d'ivoire", "ivory coast": return "🇨🇮"
    case "tanzania": return "🇹🇿"
    case "uganda": return "🇺🇬"
    case "zimbabwe": return "🇿🇼"
    case "zambia": return "🇿🇲"
    case "namibia": return "🇳🇦"
    case "angola": return "🇦🇴"
    case "madagascar": return "🇲🇬"
    case "mauritius": return "🇲🇺"

    // MARK: - Europe
    case "republic of kosovo", "kosovo": return "🇽🇰"
    case "armenia", "republic of armenia": return "🇦🇲"
    case "england", "uk", "united kingdom", "great britain": return "🇬🇧"
    case "scotland": return "🏴󠁧󠁢󠁳󠁣󠁴󠁿"
    case "wales": return "🏴󠁧󠁢󠁷󠁬󠁳󠁿"
    case "northern ireland": return "🇬🇧"
    case "european russia", "kaliningrad", "russia": return "🇷🇺"
    case "germany", "fed. rep. of germany", "federal republic of germany": return "🇩🇪"
    case "france": return "🇫🇷"
    case "italy": return "🇮🇹"
    case "spain": return "🇪🇸"
    case "portugal": return "🇵🇹"
    case "greece": return "🇬🇷"
    case "netherlands": return "🇳🇱"
    case "belgium": return "🇧🇪"
    case "switzerland": return "🇨🇭"
    case "austria": return "🇦🇹"
    case "poland": return "🇵🇱"
    case "sweden": return "🇸🇪"
    case "norway": return "🇳🇴"
    case "finland": return "🇫🇮"
    case "denmark": return "🇩🇰"
    case "ukraine": return "🇺🇦"
    case "belarus": return "🇧🇾"
    case "czech republic", "czechia": return "🇨🇿"
    case "slovak republic", "slovakia": return "🇸🇰"
    case "hungary": return "🇭🇺"
    case "romania": return "🇷🇴"
    case "bulgaria": return "🇧🇬"
    case "croatia": return "🇭🇷"
    case "serbia": return "🇷🇸"
    case "slovenia": return "🇸🇮"
    case "bosnia-herzegovina", "bosnia & herzegovina", "bosnia": return "🇧🇦"
    case "north macedonia", "macedonia": return "🇲🇰"
    case "albania": return "🇦🇱"
    case "montenegro": return "🇲🇪"
    case "ireland", "republic of ireland": return "🇮🇪"
    case "iceland": return "🇮🇸"
    case "estonia": return "🇪🇪"
    case "latvia": return "🇱🇻"
    case "lithuania": return "🇱🇹"
    case "moldova", "republic of moldova": return "🇲🇩"
    case "cyprus": return "🇨🇾"
    case "malta": return "🇲🇹"
    case "luxembourg": return "🇱🇺"
    case "monaco": return "🇲🇨"
    case "andorra": return "🇦🇩"
    case "san marino": return "🇸🇲"
    case "vatican", "vatican city": return "🇻🇦"
    case "liechtenstein": return "🇱🇮"

    // MARK: - Asia & Middle East
    case "iran", "islamic republic of iran": return "🇮🇷"
    case "republic of korea", "korea, republic of", "korea (republic of)", "south korea", "korea", "rok": return "🇰🇷"
    case "democratic people's republic of korea", "dprk", "korea, d.p.r. of", "north korea": return "🇰🇵"
    case "japan": return "🇯🇵"
    case "china", "people's republic of china", "prc": return "🇨🇳"
    case "asiatic russia": return "🇷🇺"
    case "taiwan", "republic of china": return "🇹🇼"
    case "hong kong": return "🇭🇰"
    case "macao", "macau": return "🇲🇴"
    case "saudi arabia": return "🇸🇦"
    case "india": return "🇮🇳"
    case "pakistan": return "🇵🇰"
    case "turkey", "turkiye": return "🇹🇷"
    case "israel": return "🇮🇱"
    case "indonesia": return "🇮🇩"
    case "philippines": return "🇵🇭"
    case "thailand": return "🇹🇭"
    case "vietnam", "viet nam": return "🇻🇳"
    case "malaysia", "east malaysia", "west malaysia": return "🇲🇾"
    case "singapore": return "🇸🇬"
    case "united arab emirates", "uae": return "🇦🇪"
    case "kuwait": return "🇰🇼"
    case "qatar": return "🇶🇦"
    case "oman": return "🇴🇲"
    case "bahrain": return "🇧🇭"
    case "iraq": return "🇮🇶"
    case "jordan": return "🇯🇴"
    case "lebanon": return "🇱🇧"
    case "syria", "syrian arab republic": return "🇸🇾"
    case "mongolia": return "🇲🇳"
    case "kazakhstan": return "🇰🇿"
    case "uzbekistan": return "🇺🇿"
    case "turkmenistan": return "🇹🇲"
    case "kyrgyzstan": return "🇰🇬"
    case "tajikistan": return "🇹🇯"
    case "azerbaijan": return "🇦🇿"
    case "georgia": return "🇬🇪"
    case "sri lanka": return "🇱🇰"
    case "bangladesh": return "🇧🇩"
    case "nepal": return "🇳🇵"
    case "myanmar", "burma": return "🇲🇲"
    case "cambodia": return "🇰🇭"
    case "laos", "lao pdr": return "🇱🇦"
    case "brunei", "brunei darussalam": return "🇧🇳"
    case "maldives": return "🇲🇻"
    case "afghanistan": return "🇦🇫"

    // MARK: - Oceania & Pacific
    case "australia": return "🇦🇺"
    case "new zealand": return "🇳ℤ"
    case "papua new guinea": return "🇵🇬"
    case "new caledonia": return "🇳🇨"
    case "french polynesia": return "🇵🇫"
    case "samoa": return "🇼🇸"
    case "vanuatu": return "🇻🇺"
    case "solomon is.", "solomon islands": return "🇸🇧"
    case "palau": return "🇵🇼"
    case "micronesia": return "🇫🇲"
    case "marshall is.", "marshall islands": return "🇲🇭"
    case "tuvalu": return "🇹🇻"
    case "nauru": return "🇳🇷"
    case "tonga": return "🇹🇴"

    default: break
    }
    
    // Smart Fallback Keyword Search
    if clean.contains("rodriguez") || clean.contains("rodrigues") { return "🇲🇺" }
    if clean.contains("dodecanese") { return "🇬🇷" }
    if clean.contains("montserrat") { return "🇲🇸" }
    if clean.contains("sahara") { return "🇪🇭" }
    if clean.contains("kiribati") { return "🇰🇮" }
    if clean.contains("united nations") || clean.contains("4u1un") { return "🇺🇳" }
    if clean.contains("fiji") { return "🇫🇯" }
    if clean.contains("chad") { return "🇹🇩" }
    if clean.contains("cameroon") { return "🇨🇲" }
    if clean.contains("congo") { return "🇨🇬" }
    if clean.contains("kosovo") { return "🇽🇰" }
    if clean.contains("armenia") { return "🇦🇲" }
    if clean.contains("malawi") { return "🇲🇼" }
    if clean.contains("canary") { return "🇮🇨" }
    if clean.contains("sardinia") { return "🇮🇹" }
    if clean.contains("crete") { return "🇬🇷" }
    if clean.contains("azores") { return "🇵🇹" }
    if clean.contains("balearic") { return "🇪🇸" }
    if clean.contains("bonaire") { return "🇧🇶" }
    if clean.contains("belize") { return "🇧ℤ" }
    if clean.contains("benin") { return "🇧🇯" }
    if clean.contains("curacao") { return "🇨🇼" }
    if clean.contains("galapagos") { return "🇪🇨" }
    if clean.contains("faroe") { return "🇫🇴" }
    if clean.contains("greenland") { return "🇬🇱" }
    if clean.contains("corsica") { return "🇫🇷" }
    if clean.contains("madeira") { return "🇵🇹" }
    if clean.contains("korea") { return "🇰🇷" }
    if clean.contains("russia") { return "🇷🇺" }
    if clean.contains("germany") { return "🇩🇪" }
    if clean.contains("japan") { return "🇯🇵" }
    if clean.contains("china") { return "🇨🇳" }
    if clean.contains("united states") || clean.contains("u.s.a") { return "🇺🇸" }
    if clean.contains("czech") { return "🇨🇿" }
    if clean.contains("slovak") { return "🇸🇰" }
    
    // Dynamic ISO 2-letter Country Code Emoji Builder
    if clean.count == 2 {
        let base: UInt32 = 127397
        var unicodeScalars = String.UnicodeScalarView()
        for scalar in clean.uppercased().unicodeScalars {
            if let newScalar = UnicodeScalar(base + scalar.value) {
                unicodeScalars.append(newScalar)
            }
        }
        return String(unicodeScalars)
    }
    
    return "🌐"
}

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
struct QSORecordModel: Identifiable {
    let id = UUID()
    var index: Int
    var fields: [String: String]
    
    var isConfirmed: Bool {
        let lotw = fields["LOTW_QSL_RCVD"]?.uppercased() ?? ""
        let qrz = fields["QRZLOG_QSL_RCVD"]?.uppercased() ?? ""
        let qsl = fields["QSL_RCVD"]?.uppercased() ?? ""
        return lotw == "Y" || lotw == "V" || qrz == "Y" || qsl == "Y" || qrz == "CONFIRMED" || qrz == "C"
    }
    
    // SMART DEDUPLICATION KEY: Call + Date + Time + Band + Mode
    var uniqueKey: String {
        let call = fields["CALL"]?.uppercased().trimmingCharacters(in: .whitespaces) ?? ""
        let date = fields["QSO_DATE"] ?? ""
        let time = fields["TIME_ON"] ?? fields["TIME_OFF"] ?? ""
        let band = fields["BAND"]?.uppercased().trimmingCharacters(in: .whitespaces) ?? ""
        let mode = fields["MODE"]?.uppercased().trimmingCharacters(in: .whitespaces) ?? ""
        return "\(call)_\(date)_\(time)_\(band)_\(mode)"
    }
    
    subscript(key: String) -> String {
        get { return fields[key] ?? "" }
        set { fields[key] = newValue }
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
    let qmailRaw: String
    let qmailDecoded: String

    init(email: String?, qmailRaw: String, qmailDecoded: String) {
        self.email = email
        self.qmailRaw = qmailRaw
        self.qmailDecoded = qmailDecoded
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

    func hasQRZCookies() async -> Bool {
        await withCheckedContinuation { continuation in
            QRZWebKitSession.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let hasCookies = cookies.contains { cookie in
                    cookie.domain.contains("qrz.com")
                }
                continuation.resume(returning: hasCookies)
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
                let qmailRaw = payload["qmailRaw"] as? String ?? ""
                let qmailDecoded = payload["qmailDecoded"] as? String ?? ""

                Task { @MainActor in
                    self?.finishEmailFetch(
                        returning: QRZEmailFetchResult(
                            email: email,
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
                resolve(\(debug ? "{ email: firstEmail, qmailRaw: firstDetails.raw, qmailDecoded: firstDetails.decoded, steps: steps, immediate: true }" : "{ email: firstEmail, qmailRaw: firstDetails.raw, qmailDecoded: firstDetails.decoded }"));
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
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
    }
    
    // UI & Status States
    @Published var logText: String = "YAAM Master Logbook Engine Initialized.\n"
    @Published var isCheckingUpdates: Bool = false
    @Published var isLoading: Bool = false
    @Published var isSyncingAPI: Bool = false
    @Published var propagationSnapshot = PropagationSnapshot()
    @Published var isFetchingPropagation: Bool = false
    
    // Row Selection State
    @Published var selectedRecordIDs: Set<UUID> = []
    
    // Email, SMTP & Enrichment States
    @Published var isEnriching: Bool = false
    private var enrichmentTask: Task<Void, Never>? = nil
    private var sdrControlSyncTimer: Timer?
    private var externalADIFSyncTimer: Timer?
    private var qrzEmailBackfillTimer: Timer?
    private var qrzEmailBackfillBatchNumber = 0
    private var isQRZEmailBackfillRunning = false
    
    @Published var showEmailComposer: Bool = false
    @Published var showSMTPSettings: Bool = false
    @Published var selectedEmailCallsign: String = ""
    @Published var selectedEmailAddress: String = ""
    @Published var selectedEmailQSO: QSORecordModel? = nil
    @Published var selectedEmailUnconfirmedQSOs: [QSORecordModel] = []
    @Published var emailHistory: [EmailHistoryEntry] = []
    @Published var showQSLCardComposer: Bool = false
    @Published var selectedQSLCardQSO: QSORecordModel? = nil
    
    // QRZ Rank & Login States
    @Published var isFetchingRank: Bool = false
    @Published var qrzRankData: QRZRankResponse? = nil
    @Published var qrzComparisonRankData: [QRZRankResponse] = []
    @Published var leaderboardSearchCallsign: String = ""
    @Published var ownerRankData: QRZRankResponse? = nil

    private let qrzSecureSessionToken = "eyJ1c2VybmFtZSI6ImZhY3RvcmVhbCJ9.amtpHA.AzDgCiVIUz64RzWEOtlXb_DENnI"

    @Published var showQRZLoginSheet: Bool = false
    
    // Search & Smart Sorting States
    @Published var searchText: String = ""
    @Published var sortHeader: String? = "QSO_DATE"
    @Published var sortAscending: Bool = false
    
    // Workspace File Tracking
    @Published var loadedFileURL: URL? = nil
    @Published var loadedFileName: String = ""
    @Published var isMasterMode: Bool = true
    
    @Published var tableHeaders: [String] = []
    @Published var qsoRecords: [QSORecordModel] = []
    @Published var recentLogFiles: [URL] = []
    @Published var selectedTab: Int = 0
    
    // Persistent Local Confirmations Memory Database Cache
    private var localConfirmedKeys: Set<String> = []
    
    // Filter & Modal Sheet States
    @Published var filterCriteria = FilterCriteria()
    @Published var showFilterSheet: Bool = false
    @Published var showStatsSheet: Bool = false
    
    // Global User Alerts
    @Published var showAlert: Bool = false
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""

    @Published var showAboutSheet: Bool = false

    override init() {
        super.init()
        loadPersistentConfirmationCache()
        loadMasterLogbook()
        loadRecentLogsFromDatabase()
        loadEmailHistory()
        configureExternalADIFAutoSync()
        configureSDRControlPeriodicSync()
        configureQRZEmailBackfillTimer()
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
        let countries = Set(qsoRecords.compactMap { $0["COUNTRY"].isEmpty ? nil : $0["COUNTRY"] })
        return Array(countries).sorted()
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
        
        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            records = records.filter { record in
                let country = record["COUNTRY"]
                let searchableText = (record.fields.values + [
                    country,
                    countryToFlag(country),
                    record["CONT"]
                ])
                .joined(separator: " ")
                .lowercased()

                return searchableText.contains(query) ||
                tableHeaders.contains { $0.lowercased().contains(query) }
            }
        }
        
        if let sortKey = sortHeader {
            records.sort { r1, r2 in
                let v1 = r1[sortKey].trimmingCharacters(in: .whitespaces)
                let v2 = r2[sortKey].trimmingCharacters(in: .whitespaces)
                
                let isAscending: Bool
                if sortKey == "QSO_DATE" {
                    let t1 = r1["TIME_ON"].trimmingCharacters(in: .whitespaces)
                    let t2 = r2["TIME_ON"].trimmingCharacters(in: .whitespaces)
                    isAscending = "\(v1)\(t1)" < "\(v2)\(t2)"
                } else if let d1 = Double(v1), let d2 = Double(v2) {
                    isAscending = d1 < d2
                } else if sortKey == "QSO_DATE" || sortKey == "TIME_ON" || sortKey == "TIME_OFF" {
                    isAscending = v1 < v2
                } else {
                    isAscending = v1.localizedCaseInsensitiveCompare(v2) == .orderedAscending
                }
                
                return sortAscending ? isAscending : !isAscending
            }
        }
        
        return records
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
    
    func forceQRZReLogin() {
        appendLog("🔑 Opening QRZ.com Authenticator...")
        self.showQRZLoginSheet = true
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
        
        isFetchingRank = true
        qrzRankData = nil
        
        let group = DispatchGroup()
        
        if ownerRankData == nil || ownerRankData?.callsign?.uppercased() != ownerCall {
            group.enter()
            fetchSingleRank(callsign: ownerCall) { [weak self] (result: QRZRankResponse?) in
                Task { @MainActor in
                    self?.ownerRankData = result
                    group.leave()
                }
            }
        }
        
        group.enter()
        fetchSingleRank(callsign: targetCall) { [weak self] (result: QRZRankResponse?) in
            Task { @MainActor in
                self?.qrzRankData = result
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
        let targets = Array(Set(callsigns.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }.filter { !$0.isEmpty && $0 != ownerCall })).prefix(6)

        guard !targets.isEmpty else { return }

        isFetchingRank = true
        qrzComparisonRankData = []

        let group = DispatchGroup()
        var results: [QRZRankResponse] = []
        let lock = NSLock()

        if ownerRankData == nil || ownerRankData?.callsign?.uppercased() != ownerCall {
            group.enter()
            fetchSingleRank(callsign: ownerCall) { [weak self] result in
                Task { @MainActor in
                    self?.ownerRankData = result
                    group.leave()
                }
            }
        }

        for callsign in targets {
            group.enter()
            fetchSingleRank(callsign: callsign) { result in
                if let result {
                    lock.lock()
                    results.append(result)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.qrzComparisonRankData = results.sorted {
                ($0.callsign ?? "") < ($1.callsign ?? "")
            }
            self?.qrzRankData = self?.qrzComparisonRankData.first
            self?.isFetchingRank = false
            self?.appendLog("Leaderboard multi comparison loaded for \(results.count) callsigns.")
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

        fetchSingleRank(callsign: ownerCall) { [weak self] result in
            Task { @MainActor in
                self?.ownerRankData = result
            }
        }
    }

    private func fetchSingleRank(callsign: String, completion: @escaping (QRZRankResponse?) -> Void) {
        guard let url = URL(string: "https://qrz-rank.asis.sh/api/rank/\(callsign)") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("session=\(qrzSecureSessionToken)", forHTTPHeaderField: "Cookie")
        request.setValue("YAAM-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let decoded = try? JSONDecoder().decode(QRZRankResponse.self, from: data) else {
                completion(nil)
                return
            }
            completion(decoded)
        }.resume()
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
        let call = UserDefaults.standard.string(forKey: "stationCallsign")?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
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
        guard let url = masterLogbookURL else { return }
        self.isMasterMode = true
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
    
    private func autoSaveActiveWorkspace() {
        guard let url = loadedFileURL, !qsoRecords.isEmpty else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            let recordsDicts = self.qsoRecords.map { $0.fields }
            let adifOutput = generateADIF(originalContent: "", records: recordsDicts)
            try? adifOutput.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func importADIFDialog() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText]
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        if let adifType = UTType(filenameExtension: "adif") { types.append(adifType) }
        
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            let alert = NSAlert()
            alert.messageText = "How would you like to handle this log?"
            alert.informativeText = "You can merge these new QSOs into your Master Logbook (\(currentStationCallsign)), or simply open the file as a Guest Logbook to view and enrich it separately."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Merge into Master Log")
            alert.addButton(withTitle: "Open as Guest Log")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                mergeADIFIntoMaster(from: url)
            } else if response == .alertSecondButtonReturn {
                loadGuestLog(from: url)
            }
        }
    }

    func syncSDRControlLogbook() {
        guard let source = sdrControlLogbookSource() ?? promptForSDRControlLogbookSource() else {
            return
        }

        mergeSDRControlLogbook(from: source)
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

        sdrControlSyncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncSDRControlLogbookIfNeeded(isAutomatic: true)
            }
        }
    }

    func syncSDRControlLogbookIfNeeded(isAutomatic: Bool = false) {
        guard !isLoading else { return }
        guard let source = sdrControlLogbookSource() ?? (isAutomatic ? nil : promptForSDRControlLogbookSource()) else {
            return
        }

        let lastModified = (try? source.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let lastSynced = UserDefaults.standard.object(forKey: "sdrControlLastSyncedModificationDate") as? Date
        if isAutomatic, let lastModified, let lastSynced, lastModified <= lastSynced {
            return
        }

        mergeSDRControlLogbook(from: source, allowPermissionPrompt: !isAutomatic)
        if let lastModified {
            UserDefaults.standard.set(lastModified, forKey: "sdrControlLastSyncedModificationDate")
        }
        UserDefaults.standard.set(Date(), forKey: "sdrControlLastSyncRunDate")
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

    private func mergeSDRControlLogbook(from source: SDRControlLogbookSource, allowPermissionPrompt: Bool = true) {
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
                let records = try self.parseSDRControlLogbook(url: url)

                DispatchQueue.main.async {
                    if !self.isMasterMode {
                        self.loadMasterLogbook()
                    }

                    let headers = self.sdrControlHeaders(from: records)
                    for header in headers where !self.tableHeaders.contains(header) {
                        self.tableHeaders.append(header)
                    }

                    var existingKeys = Set(self.qsoRecords.map { $0.uniqueKey })
                    var addedCount = 0
                    var skippedCount = 0

                    for record in records {
                        let model = QSORecordModel(index: self.qsoRecords.count + 1, fields: record)
                        guard !existingKeys.contains(model.uniqueKey) else {
                            skippedCount += 1
                            continue
                        }

                        self.qsoRecords.append(model)
                        existingKeys.insert(model.uniqueKey)
                        addedCount += 1
                    }

                    for index in self.qsoRecords.indices {
                        self.qsoRecords[index].index = index + 1
                    }

                    self.autoSaveActiveWorkspace()
                    self.isLoading = false
                    self.appendLog("SDR-Control sync complete: \(addedCount) new QSOs added, \(skippedCount) duplicates skipped.")
                    self.playActivitySound(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    if allowPermissionPrompt, self.isFilePermissionError(error), !source.securityScoped {
                        UserDefaults.standard.removeObject(forKey: "sdrControlLogbookPath")
                        if let selectedSource = self.promptForSDRControlLogbookSource() {
                            self.mergeSDRControlLogbook(from: selectedSource)
                        }
                        return
                    }

                    self.showNativeAlert(
                        title: "SDR-Control Sync Failed",
                        message: error.localizedDescription
                    )
                    self.playActivitySound(.failure)
                }
            }
        }
    }

    private func isFilePermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain &&
            (nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileReadNoSuchFileError)
    }

    private func parseSDRControlLogbook(url: URL) throws -> [[String: String]] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let entries = plist as? [[String: Any]] else {
            throw NSError(
                domain: "YAAM.SDRControl",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "SmartSDR.smartsdrlog does not contain the expected array of QSO records."]
            )
        }

        return entries.compactMap { entry in
            let deleted = stringValue(entry["Deleted"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard deleted != "1" else { return nil }

            var record: [String: String] = [:]
            for (key, value) in entry {
                guard key != "Deleted" else { continue }
                let normalizedKey = normalizedSDRControlKey(key)
                let normalizedValue = normalizedSDRControlValue(value, key: normalizedKey)
                if !normalizedValue.isEmpty {
                    record[normalizedKey] = normalizedValue
                }
            }

            record["APP_SDR_CONTROL_ID"] = stringValue(entry["UniqueId"])
            record["APP_SDR_CONTROL_IMPORTED"] = "Y"
            return record["CALL", default: ""].isEmpty ? nil : record
        }
    }

    private func normalizedSDRControlKey(_ key: String) -> String {
        switch key {
        case "Name": return "NAME"
        case "UniqueId": return "APP_SDR_CONTROL_ID"
        default: return key.uppercased()
        }
    }

    private func normalizedSDRControlValue(_ value: Any, key: String) -> String {
        let rawValue = stringValue(value)
        switch key {
        case "QSO_DATE":
            return rawValue.replacingOccurrences(of: "-", with: "")
        case "TIME_ON", "TIME_OFF":
            return rawValue.replacingOccurrences(of: ":", with: "")
        default:
            return rawValue
        }
    }

    private func sdrControlHeaders(from records: [[String: String]]) -> [String] {
        let preferred = [
            "QSO_DATE", "TIME_ON", "TIME_OFF", "CALL", "FREQ", "FREQ_RX", "BAND", "BAND_RX",
            "MODE", "SUBMODE", "RST_SENT", "RST_RCVD", "NAME", "QTH", "COUNTRY", "CONT",
            "DXCC", "CQZ", "ITUZ", "GRIDSQUARE", "LAT", "LON", "COMMENT", "OPERATOR",
            "STATION_CALLSIGN", "APP_SDR_CONTROL_ID", "APP_SDR_CONTROL_IMPORTED"
        ]
        let allHeaders = Set(records.flatMap { $0.keys })
        return preferred.filter { allHeaders.contains($0) } +
            allHeaders.subtracting(preferred).sorted()
    }

    private func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }
    
    func loadGuestLog(from url: URL) {
        isLoading = true
        isMasterMode = false
        loadedFileURL = url
        loadedFileName = "Guest: " + url.lastPathComponent
        selectedRecordIDs.removeAll()
        archiveLogToDatabase(originalURL: url)
        appendLog("Opening Guest Log: \(url.lastPathComponent)...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let content = (try? String(contentsOfFile: url.path, encoding: .utf8)) ?? (try? String(contentsOfFile: url.path, encoding: .isoLatin1)) else {
                DispatchQueue.main.async { self.isLoading = false; self.appendLog("Error: Unable to read guest file.") }
                return
            }
            let (headers, records) = parseADIF(content: content)
            var qsoModels = records.enumerated().map { QSORecordModel(index: $0 + 1, fields: $1) }
            let offlineMatched = self.applyPersistentConfirmationCache(to: &qsoModels)
            
            DispatchQueue.main.async {
                self.tableHeaders = headers
                self.qsoRecords = qsoModels
                self.refreshEmailHistoryColumns()
                self.isLoading = false
                self.appendLog("Successfully loaded \(records.count) QSOs in Guest Mode.")
                if offlineMatched > 0 {
                    self.appendLog("Offline Database Engine: Matched \(offlineMatched) confirmations instantly from local storage.")
                }
            }
        }
    }
    
    private func mergeADIFIntoMaster(from url: URL) {
        isLoading = true
        appendLog("Analyzing & Merging '\(url.lastPathComponent)' into Master Logbook...")
        archiveLogToDatabase(originalURL: url)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.sync {
                if !self.isMasterMode { self.loadMasterLogbook() }
            }
            
            guard let content = (try? String(contentsOfFile: url.path, encoding: .utf8)) ?? (try? String(contentsOfFile: url.path, encoding: .isoLatin1)) else {
                DispatchQueue.main.async { self.isLoading = false; self.appendLog("Error reading file encoding.") }
                return
            }
            
            let (newHeaders, newRecordsDicts) = parseADIF(content: content)
            
            DispatchQueue.main.async {
                for header in newHeaders {
                    if !self.tableHeaders.contains(header) { self.tableHeaders.append(header) }
                }
                
                var existingKeys = Set(self.qsoRecords.map { $0.uniqueKey })
                var addedCount = 0
                var updatedCount = 0
                
                for dict in newRecordsDicts {
                    let tempModel = QSORecordModel(index: 0, fields: dict)
                    let key = tempModel.uniqueKey
                    
                    if !existingKeys.contains(key) {
                        self.qsoRecords.append(tempModel)
                        existingKeys.insert(key)
                        addedCount += 1
                    } else {
                        if let idx = self.qsoRecords.firstIndex(where: { $0.uniqueKey == key }) {
                            var updated = false
                            if tempModel.isConfirmed && !self.qsoRecords[idx].isConfirmed {
                                if let lotw = tempModel.fields["LOTW_QSL_RCVD"], !lotw.isEmpty { self.qsoRecords[idx].fields["LOTW_QSL_RCVD"] = lotw; updated = true }
                                if let qsl = tempModel.fields["QSL_RCVD"], !qsl.isEmpty { self.qsoRecords[idx].fields["QSL_RCVD"] = qsl; updated = true }
                            }
                            if updated { updatedCount += 1 }
                        }
                    }
                }
                
                for i in 0..<self.qsoRecords.count { self.qsoRecords[i].index = i + 1 }
                self.autoSaveActiveWorkspace()
                self.isLoading = false
                self.appendLog("Merge Complete: \(addedCount) New QSOs added, \(updatedCount) Confirmations updated.")
                self.playActivitySound(.success)
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

        externalADIFSyncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncExternalADIFLogIfNeeded(isAutomatic: true)
            }
        }
    }

    func configureSDRControlAutoSync() {
        configureExternalADIFAutoSync()
    }

    func syncExternalADIFLogIfNeeded(isAutomatic: Bool = false) {
        guard !isLoading else { return }

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
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            appendLog("External ADIF sync skipped: file not found at saved path.")
            if !isAutomatic { playActivitySound(.failure) }
            return
        }

        let lastModified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let lastSynced = UserDefaults.standard.object(forKey: "externalADIFLastSyncedModificationDate") as? Date ??
            UserDefaults.standard.object(forKey: "sdrControlLastSyncedModificationDate") as? Date
        if isAutomatic, let lastModified, let lastSynced, lastModified <= lastSynced {
            return
        }

        appendLog("External ADIF sync started...")
        mergeADIFIntoMaster(from: url)
        if let lastModified {
            UserDefaults.standard.set(lastModified, forKey: "externalADIFLastSyncedModificationDate")
        }
        UserDefaults.standard.set(Date(), forKey: "externalADIFLastSyncRunDate")
    }

    func syncSDRControlLogIfNeeded(isAutomatic: Bool = false) {
        syncExternalADIFLogIfNeeded(isAutomatic: isAutomatic)
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
        let lotwPass = UserDefaults.standard.string(forKey: "lotwPassword")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
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
        let lotwPass = UserDefaults.standard.string(forKey: "lotwPassword")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
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
        enrichmentTask?.cancel()
        enrichmentTask = nil
        isEnriching = false
        appendLog("🛑 Enrichment process stopped by user.")
    }

    func enrichLogData(targetCallsigns: Set<String>? = nil) {
        guard !qsoRecords.isEmpty else { return }

        let newHeaders = ["RANK_QSO", "RANK_BAND", "RANK_DXCC", "EMAIL", "QRZ_URL", "APP_YAAM_ENRICHED", "APP_YAAM_EMAIL_CHECKED"]
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
        
        let uniqueCallsigns = Array(callsignsToEnrich)
        guard !uniqueCallsigns.isEmpty else {
            if targetCallsigns == nil {
                appendLog("ℹ️ No QSOs found for today to enrich.")
            } else {
                appendLog("✅ All target records in this workspace are already enriched!")
            }
            selectedRecordIDs.removeAll()
            return
        }
        
        isEnriching = true
        appendLog("🚀 Enrichment: Processing \(uniqueCallsigns.count) callsign(s)...")
        
        enrichmentTask = Task { @MainActor in
            for (idx, callsign) in uniqueCallsigns.enumerated() {
                if Task.isCancelled { break }
                
                self.appendLog("[\(idx + 1)/\(uniqueCallsigns.count)] Step 1/2: Fetching ranks for \(callsign)...")
                let (rankQSO, rankBand, rankDXCC) = await self.asyncFetchRank(for: callsign)
                if rankQSO.isEmpty && rankBand.isEmpty && rankDXCC.isEmpty {
                    self.appendLog("⚠️ No rank data returned for \(callsign).")
                }
                
                if Task.isCancelled { break }

                self.appendLog("[\(idx + 1)/\(uniqueCallsigns.count)] Step 2/2: Fetching QRZ email for \(callsign)...")
                let fetchedEmail = await self.fetchQRZEmail(for: callsign)
                if fetchedEmail == nil {
                    self.appendLog("⚠️ No QRZ email found for \(callsign).")
                }

                if idx < uniqueCallsigns.count - 1 {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                }

                if Task.isCancelled { break }

                for i in 0..<self.qsoRecords.count {
                    if self.qsoRecords[i]["CALL"].uppercased() == callsign {
                        if !rankQSO.isEmpty { self.qsoRecords[i].fields["RANK_QSO"] = rankQSO }
                        if !rankBand.isEmpty { self.qsoRecords[i].fields["RANK_BAND"] = rankBand }
                        if !rankDXCC.isEmpty { self.qsoRecords[i].fields["RANK_DXCC"] = rankDXCC }
                        if let email = fetchedEmail, !email.isEmpty { self.qsoRecords[i].fields["EMAIL"] = email }

                        self.qsoRecords[i].fields["QRZ_URL"] = "https://www.qrz.com/db/\(callsign)"
                        self.qsoRecords[i].fields["APP_YAAM_ENRICHED"] = "Y"
                        self.qsoRecords[i].fields["APP_YAAM_EMAIL_CHECKED"] = Self.adifDateFormatter.string(from: Date())
                    }
                }
                self.objectWillChange.send()
                self.autoSaveActiveWorkspace()
            }
            
            let wasCancelled = Task.isCancelled
            self.isEnriching = false
            self.enrichmentTask = nil
            
            self.selectedRecordIDs.removeAll()
            self.objectWillChange.send()
            
            if wasCancelled {
                self.appendLog("🛑 Enrichment stopped.")
            } else {
                self.appendLog("✅ Enrichment complete & Workspace Auto-Saved!")
            }
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
            appendLog("QRZ email backfill skipped: previous batch is still running.")
            return
        }
        guard await QRZWebKitScraper.shared.hasQRZCookies() else {
            appendLog("QRZ email backfill skipped: no saved QRZ.com session cookies. Open QRZ Login, sign in, then click Done / Save Session.")
            return
        }
        isQRZEmailBackfillRunning = true
        defer { isQRZEmailBackfillRunning = false }

        for header in ["EMAIL", "QRZ_URL", "APP_YAAM_ENRICHED", "APP_YAAM_EMAIL_CHECKED"] where !tableHeaders.contains(header) {
            tableHeaders.append(header)
        }

        let callsigns = missingEmailCallsignBatch(limit: 40)
        guard !callsigns.isEmpty else {
            appendLog("QRZ email backfill: no unchecked callsigns without email remain.")
            return
        }

        qrzEmailBackfillBatchNumber += 1
        let batchNumber = qrzEmailBackfillBatchNumber
        appendLog("QRZ email backfill batch #\(batchNumber): checking \(callsigns.count) callsign(s), starting at \(callsigns.first ?? "-") and ending at \(callsigns.last ?? "-").")
        var updatedEmailCount = 0
        var checkedWithoutEmailCount = 0
        var savedEmails: [String] = []
        var noEmailCallsigns: [String] = []
        var detailLines: [String] = []

        for (offset, callsign) in callsigns.enumerated() {
            if Task.isCancelled { break }

            detailLines.append("[\(offset + 1)/\(callsigns.count)] \(callsign): checking")
            let email = await fetchQRZEmail(for: callsign)
            let checkedMarker = Self.adifDateFormatter.string(from: Date())

            for index in qsoRecords.indices {
                let rowCallsign = qsoRecords[index]["CALL"]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                guard rowCallsign == callsign else { continue }

                qsoRecords[index].fields["QRZ_URL"] = "https://www.qrz.com/db/\(callsign)"
                qsoRecords[index].fields["APP_YAAM_EMAIL_CHECKED"] = checkedMarker
                if let email, !email.isEmpty {
                    qsoRecords[index].fields["EMAIL"] = email
                    qsoRecords[index].fields["APP_YAAM_ENRICHED"] = "Y"
                }
            }

            if let email, !email.isEmpty {
                updatedEmailCount += 1
                savedEmails.append("\(callsign)=\(email)")
                detailLines.append("[\(offset + 1)/\(callsigns.count)] \(callsign): saved \(email)")
            } else {
                checkedWithoutEmailCount += 1
                noEmailCallsigns.append(callsign)
                detailLines.append("[\(offset + 1)/\(callsigns.count)] \(callsign): no public email; marked checked")
            }

            try? await Task.sleep(nanoseconds: 450_000_000)
        }

        objectWillChange.send()
        autoSaveActiveWorkspace()
        let savedSummary = savedEmails.isEmpty ? "none" : savedEmails.joined(separator: ", ")
        let noEmailSummary = noEmailCallsigns.isEmpty ? "none" : noEmailCallsigns.joined(separator: ", ")
        appendLog("""
        QRZ email backfill batch #\(batchNumber) details:
        \(detailLines.joined(separator: "\n"))
        QRZ email backfill batch #\(batchNumber) complete: \(updatedEmailCount) email(s) saved [\(savedSummary)]; \(checkedWithoutEmailCount) checked/no email [\(noEmailSummary)].
        """)
    }

    private func missingEmailCallsignBatch(limit: Int) -> [String] {
        var seen = Set<String>()
        var callsigns: [String] = []

        for record in qsoRecords {
            let callsign = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !callsign.isEmpty, !seen.contains(callsign) else { continue }
            guard record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard record["APP_YAAM_EMAIL_CHECKED"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            seen.insert(callsign)
            callsigns.append(callsign)

            if callsigns.count >= limit {
                break
            }
        }

        return callsigns
    }
    
    private func asyncFetchRank(for callsign: String) async -> (String, String, String) {
        guard let url = URL(string: "https://qrz-rank.asis.sh/api/rank/\(callsign)") else {
            return ("", "", "")
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        req.setValue("session=\(qrzSecureSessionToken)", forHTTPHeaderField: "Cookie")
        req.setValue("YAAM-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let decoded = try? JSONDecoder().decode(QRZRankResponse.self, from: data) {
                return (decoded.rank_qso ?? "", decoded.rank_band ?? "", decoded.rank_countries ?? "")
            }
        } catch {}
        return ("", "", "")
    }

    private func fetchQRZEmail(for callsign: String) async -> String? {
        if await !QRZWebKitScraper.shared.hasQRZCookies() {
            appendLog("⚠️ No QRZ.com cookies found. Open QRZ Login, sign in, then click Done / Save Session.")
        }

        let result = await fetchQRZEmailFromRawHTML(for: callsign)
        return result.email
    }

    @MainActor
    func fetchAndStoreQRZEmail(for callsign: String) async -> String? {
        let normalizedCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCallsign.isEmpty else { return nil }

        appendLog("Fetching QRZ email for \(normalizedCallsign)...")
        guard let email = await fetchQRZEmail(for: normalizedCallsign), !email.isEmpty else {
            appendLog("⚠️ No QRZ email found for \(normalizedCallsign).")
            playActivitySound(.failure)
            return nil
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
        objectWillChange.send()
        autoSaveActiveWorkspace()
        appendLog("✅ QRZ email saved to \(updatedRows) table row(s) for \(normalizedCallsign).")
        playActivitySound(.success)
        return email
    }

    private func fetchQRZEmailFromRawHTML(for callsign: String) async -> QRZEmailFetchResult {
        let normalizedCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let url = URL(string: "https://www.qrz.com/db/\(normalizedCallsign)") else {
            return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
        }

        var request = QRZWebKitSession.browserLikeRequest(url: url, timeoutInterval: 12)
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")

        let cookieHeader = await qrzCookieHeader()
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
                return decodeQRZQmail(from: html)
            } catch {}
        }

        return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
    }

    private func qrzCookieHeader() async -> String {
        await withCheckedContinuation { continuation in
            QRZWebKitSession.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let qrzCookies = cookies
                    .filter { $0.domain.contains("qrz.com") }
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")
                continuation.resume(returning: qrzCookies)
            }
        }
    }

    private func decodeQRZQmail(from html: String) -> QRZEmailFetchResult {
        guard let regex = try? NSRegularExpression(
            pattern: "\\bqmail\\s*=\\s*['\"]([^'\"]+)['\"]",
            options: []
        ) else {
            return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
        }

        let searchRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: searchRange),
              let qmailRange = Range(match.range(at: 1), in: html) else {
            return QRZEmailFetchResult(email: nil, qmailRaw: "", qmailDecoded: "")
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
            return QRZEmailFetchResult(email: nil, qmailRaw: qmail, qmailDecoded: "")
        }

        var decoded = ""
        for _ in 0..<count {
            guard index >= 0 else { break }
            decoded.append(chars[index])
            index -= 2
        }

        let email = cleanedEmailAddress(decoded)
        return QRZEmailFetchResult(email: email.isEmpty ? nil : email, qmailRaw: qmail, qmailDecoded: decoded)
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

    func sendEmail(to recipient: String, subject: String, body: String, playSound: Bool = true, completion: @escaping (Bool, String) -> Void) {
        let targetCallsign = selectedEmailCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        let rawHost = UserDefaults.standard.string(forKey: "smtpHost")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let host = rawHost.isEmpty ? "smtp.gmail.com" : rawHost
        
        let rawPort = UserDefaults.standard.string(forKey: "smtpPort")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let port = rawPort.isEmpty ? "465" : rawPort
        
        let user = UserDefaults.standard.string(forKey: "smtpUser")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawPass = UserDefaults.standard.string(forKey: "smtpPass")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
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
            
            let emailContent = """
            From: \(user)
            To: \(recipient)
            Subject: \(subject)
            Date: \(dateStr)
            Message-ID: \(messageID)
            Content-Type: text/plain; charset=UTF-8
            
            \(body)
            """
            
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
                "--upload-file", "-",
                "--verbose",
                "--insecure",
                "--ipv4"
            ]
            
            if !isPort465 {
                arguments.append("--ssl-reqd")
            }
            
            process.arguments = arguments
            
            let stdinPipe = Pipe()
            let outputPipe = Pipe()
            
            process.standardInput = stdinPipe
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            do {
                try process.run()
                
                if let data = emailContent.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(data)
                }
                stdinPipe.fileHandleForWriting.closeFile()
                
                process.waitUntilExit()
                
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

    func syncConfirmations(forceFullSync: Bool = false) {
        guard !qsoRecords.isEmpty else {
            appendLog("Error: No log loaded to sync.")
            return
        }
        
        let lotwUser = UserDefaults.standard.string(forKey: "lotwUsername")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lotwPass = UserDefaults.standard.string(forKey: "lotwPassword")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let qrzKey = UserDefaults.standard.string(forKey: "qrzApiKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if lotwUser.isEmpty && qrzKey.isEmpty {
            self.alertTitle = "Credentials Required 🔑"
            self.alertMessage = "Please enter your LoTW or QRZ Logbook API credentials in Preferences (Cmd+,) to sync online QSL confirmations."
            self.showAlert = true
            self.playActivitySound(.failure)
            return
        }
        
        let confirmationHeaders = ["LOTW_QSL_RCVD", "QRZLOG_QSL_RCVD", "QSL_RCVD"]
        for h in confirmationHeaders {
            if !tableHeaders.contains(h) {
                tableHeaders.append(h)
            }
        }
        
        isSyncingAPI = true
        
        let isFirstFullSync = forceFullSync || (totalConfirmedCount < 50 && qsoRecords.count > 1000)
        let lastLoTWSyncDate = isFirstFullSync ? nil : (UserDefaults.standard.object(forKey: "lastLoTWSyncDate") as? Date)
        let lastQRZSyncDate = forceFullSync ? nil : (UserDefaults.standard.object(forKey: "lastQRZSyncDate") as? Date)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let lotwSinceDateString = lastLoTWSyncDate != nil ? dateFormatter.string(from: lastLoTWSyncDate!) : "1900-01-01"
        let qrzSinceDateString = lastQRZSyncDate.map { dateFormatter.string(from: $0) }
        
        if isFirstFullSync {
            appendLog("🚀 Launching FULL Historical QSL Sync (Fetching all confirmations since 1900)...")
        } else {
            appendLog("🔄 Launching Incremental QSL Sync (LoTW since \(lotwSinceDateString), QRZ \(qrzSinceDateString.map { "since \($0)" } ?? "full confirmed sync"))...")
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var newlyConfirmedCount = 0
            var fetchedRecordsCount = 0
            var syncLogs: [String] = []
            
            let group = DispatchGroup()
            
            if !lotwUser.isEmpty && !lotwPass.isEmpty {
                group.enter()
                if let encodedUser = lotwUser.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let encodedPass = lotwPass.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let lotwEndpoint = URL(string: "https://lotw.arrl.org/lotwuser/lotwreport.adi?login=\(encodedUser)&password=\(encodedPass)&qso_query=1&qso_qslsince=\(lotwSinceDateString)") {
                    
                    var request = URLRequest(url: lotwEndpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 45)
                    request.setValue("YAAM-macOS/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")
                    
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        defer { group.leave() }
                        
                        if let data = data, let reportADIF = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                            if !reportADIF.lowercased().contains("invalid password") && !reportADIF.lowercased().contains("access denied") {
                                let (_, serverRecords) = parseADIF(content: reportADIF)
                                fetchedRecordsCount += serverRecords.count
                                syncLogs.append("LoTW: Server returned \(serverRecords.count) confirmed QSL records.")
                                
                                DispatchQueue.main.async {
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
                                            for i in 0..<self.qsoRecords.count {
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
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                syncLogs.append("LoTW Error: Invalid credentials.")
                            }
                        }
                    }.resume()
                } else {
                    group.leave()
                }
            }
            
            if !qrzKey.isEmpty {
                group.enter()
                self.fetchQRZConfirmedRecords(apiKey: qrzKey, sinceDateString: qrzSinceDateString) { result in

                    switch result {
                    case .success(let serverRecords):
                        fetchedRecordsCount += serverRecords.count
                        syncLogs.append("QRZ: Server returned \(serverRecords.count) confirmed logbook records.")

                        DispatchQueue.main.async {
                            for rec in serverRecords {
                                guard self.isQRZConfirmedRecord(rec) else { continue }
                                let qrzConfirmedDate = self.cleanDate(
                                    rec["APP_QRZLOG_QSLDATE"] ??
                                    rec["QRZLOG_QSLRDATE"] ??
                                    rec["APP_QRZLOG_QSLRDATE"] ??
                                    rec["QSLRDATE"] ??
                                    ""
                                )

                                for i in 0..<self.qsoRecords.count {
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
                                    }
                                }
                            }
                        }
                        group.leave()
                    case .failure(let message):
                        if qrzSinceDateString != nil, message.uppercased().contains("RESULT=FAIL"), message.uppercased().contains("COUNT=0") {
                            syncLogs.append("QRZ: Incremental confirmed sync returned no records, retrying full confirmed sync...")
                            self.fetchQRZConfirmedRecords(apiKey: qrzKey, sinceDateString: nil) { fallbackResult in
                                defer { group.leave() }

                                switch fallbackResult {
                                case .success(let serverRecords):
                                    fetchedRecordsCount += serverRecords.count
                                    syncLogs.append("QRZ: Full confirmed sync returned \(serverRecords.count) confirmed logbook records.")

                                    DispatchQueue.main.async {
                                        for rec in serverRecords {
                                            guard self.isQRZConfirmedRecord(rec) else { continue }
                                            let qrzConfirmedDate = self.cleanDate(
                                                rec["APP_QRZLOG_QSLDATE"] ??
                                                rec["QRZLOG_QSLRDATE"] ??
                                                rec["APP_QRZLOG_QSLRDATE"] ??
                                                rec["QSLRDATE"] ??
                                                ""
                                            )

                                            for i in 0..<self.qsoRecords.count {
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
                                                }
                                            }
                                        }
                                    }
                                case .failure(let fallbackMessage):
                                    syncLogs.append("QRZ Error: \(fallbackMessage)")
                                }
                            }
                        } else {
                            syncLogs.append("QRZ Error: \(message)")
                            group.leave()
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                self.isSyncingAPI = false
                UserDefaults.standard.set(Date(), forKey: "lastLoTWSyncDate")
                if !qrzKey.isEmpty {
                    UserDefaults.standard.set(Date(), forKey: "lastQRZSyncDate")
                }
                
                for log in syncLogs {
                    self.appendLog(log)
                }
                
                self.objectWillChange.send()
                self.autoSaveActiveWorkspace()
                
                if newlyConfirmedCount > 0 {
                    self.appendLog("✅ Sync Complete: \(newlyConfirmedCount) new QSL confirmations matched!")
                    self.alertTitle = "QSL Sync Complete 🟢"
                    self.alertMessage = "Successfully updated \(newlyConfirmedCount) confirmations in your logbook!"
                    self.showAlert = true
                    self.playActivitySound(.success)
                } else {
                    self.appendLog("⚪ Sync Complete: All confirmations are up to date (\(fetchedRecordsCount) records checked).")
                    self.alertTitle = "Log Up To Date ⚪"
                    self.alertMessage = "Checked \(fetchedRecordsCount) cloud records. All confirmations in your log are up to date."
                    self.showAlert = true
                    self.playActivitySound(syncLogs.contains { $0.lowercased().contains("error") } ? .failure : .success)
                }
            }
        }
    }

    func deleteRecord(id: UUID) {
        if let idx = qsoRecords.firstIndex(where: { $0.id == id }) {
            let recordNum = qsoRecords[idx].index
            let call = qsoRecords[idx]["CALL"]
            qsoRecords.remove(at: idx)
            selectedRecordIDs.remove(id)
            
            for i in 0..<qsoRecords.count {
                qsoRecords[i].index = i + 1
            }
            appendLog("Deleted QSO record #\(recordNum) (\(call)).")
            autoSaveActiveWorkspace()
        }
    }

    func updateCell(recordID: UUID, header: String, newValue: String) {
        if let idx = qsoRecords.firstIndex(where: { $0.id == recordID }) {
            qsoRecords[idx].fields[header] = newValue
            appendLog("Updated record #\(qsoRecords[idx].index) [\(header)] ➔ '\(newValue)'")
            autoSaveActiveWorkspace()
        }
    }

    func deleteColumn(header: String) {
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

    func saveCurrentLog() {
        guard let url = loadedFileURL else {
            saveAsCurrentLog()
            return
        }
        writeRecordsToFileAsync(records: qsoRecords.map { $0.fields }, to: url)
    }

    func saveAsCurrentLog() {
        let panel = NSSavePanel()
        var types: [UTType] = [.plainText]
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        types.append(.commaSeparatedText)
        
        panel.allowedContentTypes = types
        panel.nameFieldStringValue = loadedFileName.isEmpty ? "modified_log.adi" : loadedFileName
        
        if panel.runModal() == .OK, let url = panel.url {
            writeRecordsToFileAsync(records: qsoRecords.map { $0.fields }, to: url)
            self.loadedFileURL = url
            self.loadedFileName = url.lastPathComponent
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
