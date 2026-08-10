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
    let percentage: Double
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

// MARK: - Proven Native QRZ Scraper Engine (Simple & Reliable)
@MainActor
class QRZWebKitScraper: NSObject, WKNavigationDelegate {
    static let shared = QRZWebKitScraper()
    private var webView: WKWebView!
    private var continuation: CheckedContinuation<String?, Never>?

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        // Shares WebKit cookie store naturally with QRZLoginView!
        config.websiteDataStore = .default()

        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        self.webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        self.webView.navigationDelegate = self
    }

    func fetchEmail(for callsign: String) async -> String? {
        guard let url = URL(string: "https://www.qrz.com/db/\(callsign)") else { return nil }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
            self.webView.load(request)
        }
    }

    // MARK: - WKNavigationDelegate
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let jsScript = """
            (function() {
                var qemSpan = document.getElementById('qem');
                if (qemSpan) {
                    if (typeof showqem === 'function') {
                        try { showqem(); } catch(e) {}
                    } else {
                        var evt = new MouseEvent('mouseover', { bubbles: true, cancelable: true, view: window });
                        qemSpan.dispatchEvent(evt);
                        qemSpan.click();
                    }

                    var text = (qemSpan.innerText || qemSpan.textContent || "").trim();
                    if (text && text.includes('@') && text.includes('.')) {
                        return text;
                    }
                }

                var mailtoAnchor = document.querySelector('a[href^="mailto:"]');
                if (mailtoAnchor) {
                    var href = mailtoAnchor.getAttribute('href').replace('mailto:', '').split('?')[0].trim();
                    if (href && !href.includes('qrz.com') && !href.includes('support')) {
                        return href;
                    }
                }

                return "";
            })();
            """

            webView.evaluateJavaScript(jsScript) { [weak self] result, _ in
                let extracted = result as? String
                let email = (extracted?.isEmpty == false) ? extracted : nil

                Task { @MainActor in
                    let cont = self?.continuation
                    self?.continuation = nil
                    cont?.resume(returning: email)
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            let cont = self.continuation
            self.continuation = nil
            cont?.resume(returning: nil)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            let cont = self.continuation
            self.continuation = nil
            cont?.resume(returning: nil)
        }
    }
}

// MARK: - Global Application State Manager (Workspace Architecture)
class AppState: NSObject, ObservableObject {
    var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
    }
    
    // UI & Status States
    @Published var logText: String = "YAAM Master Logbook Engine Initialized.\n"
    @Published var isCheckingUpdates: Bool = false
    @Published var isLoading: Bool = false
    @Published var isSyncingAPI: Bool = false
    
    // Row Selection State (Supports Max 19 Selection Limit)
    @Published var selectedRecordIDs: Set<UUID> = []
    
    // Email, SMTP & Enrichment States
    @Published var isEnriching: Bool = false
    private var enrichmentTask: Task<Void, Never>? = nil
    
    @Published var showEmailComposer: Bool = false
    @Published var showSMTPSettings: Bool = false
    @Published var selectedEmailCallsign: String = ""
    @Published var selectedEmailAddress: String = ""
    @Published var selectedEmailQSO: QSORecordModel? = nil
    
    // QRZ Rank & Login States
    @Published var isFetchingRank: Bool = false
    @Published var qrzRankData: QRZRankResponse? = nil
    @Published var leaderboardSearchCallsign: String = ""
    @Published var ownerRankData: QRZRankResponse? = nil

    private let qrzSecureSessionToken = "eyJ1c2VybmFtZSI6ImZhY3RvcmVhbCJ9.amtpHA.AzDgCiVIUz64RzWEOtlXb_DENnI"

    @Published var showQRZLoginSheet: Bool = false
    
    // Search & Smart Sorting States
    @Published var searchText: String = ""
    @Published var sortHeader: String? = nil
    @Published var sortAscending: Bool = true
    
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
        
        var bandMap: [String: (total: Int, confirmed: Int, countries: Set<String>)] = [:]
        let total = Double(qsoRecords.count)
        
        for record in qsoRecords {
            let band = record["BAND"].isEmpty ? "UNKNOWN" : record["BAND"].uppercased()
            let country = record["COUNTRY"]
            let confirmed = record.isConfirmed
            
            if bandMap[band] == nil {
                bandMap[band] = (total: 0, confirmed: 0, countries: Set<String>())
            }
            bandMap[band]?.total += 1
            if confirmed { bandMap[band]?.confirmed += 1 }
            if !country.isEmpty { bandMap[band]?.countries.insert(country) }
        }
        
        return bandMap.map { (bandKey, data) in
            let pct = (Double(data.total) / total) * 100.0
            let unconf = data.total - data.confirmed
            return BandStatModel(band: bandKey, qsoCount: data.total, confirmedCount: data.confirmed, unconfirmedCount: unconf, dxccCount: data.countries.count, percentage: pct)
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
                record.fields.values.contains { $0.lowercased().contains(query) } ||
                tableHeaders.contains { $0.lowercased().contains(query) }
            }
        }
        
        if let sortKey = sortHeader {
            records.sort { r1, r2 in
                let v1 = r1[sortKey].trimmingCharacters(in: .whitespaces)
                let v2 = r2[sortKey].trimmingCharacters(in: .whitespaces)
                
                let isAscending: Bool
                if let d1 = Double(v1), let d2 = Double(v2) {
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
            if selectedRecordIDs.count >= 19 {
                showNativeAlert(
                    title: "Selection Limit Reached ⚠️",
                    message: "You cannot select or enrich more than 19 rows at a time."
                )
                return
            }
            selectedRecordIDs.insert(id)
        }
    }
    
    func clearSelection() {
        selectedRecordIDs.removeAll()
    }
    
    func enrichSelectedRecords() {
        guard !selectedRecordIDs.isEmpty else { return }
        
        if selectedRecordIDs.count > 19 {
            showNativeAlert(
                title: "Selection Limit Exceeded ⚠️",
                message: "You cannot select or enrich more than 19 rows at a time."
            )
            return
        }
        
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
            self.appendLog("Master Logbook loaded successfully: \(self.qsoRecords.count) QSOs.")
        } else {
            self.qsoRecords = []
            self.tableHeaders = ["QSO_DATE", "TIME_ON", "CALL", "BAND", "MODE", "FREQ", "RST_SENT", "RST_RCVD", "COUNTRY", "COMMENT"]
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
            }
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
                        self.mergeADIFIntoMaster(from: cloudFileURL)
                    }
                } catch {
                    DispatchQueue.main.async { self.isLoading = false }
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
        
        if let targets = targetCallsigns, targets.count > 19 {
            showNativeAlert(
                title: "Selection Limit Exceeded ⚠️",
                message: "You cannot select or enrich more than 19 rows at a time."
            )
            return
        }
        
        let newHeaders = ["RANK_QSO", "RANK_BAND", "RANK_DXCC", "EMAIL", "QRZ_URL", "APP_YAAM_ENRICHED"]
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
            for record in qsoRecords {
                if record.fields["APP_YAAM_ENRICHED"] != "Y" {
                    let c = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if !c.isEmpty { callsignsToEnrich.insert(c) }
                }
            }
        }
        
        let uniqueCallsigns = Array(callsignsToEnrich)
        guard !uniqueCallsigns.isEmpty else {
            appendLog("✅ All target records in this workspace are already enriched!")
            selectedRecordIDs.removeAll()
            return
        }
        
        isEnriching = true
        appendLog("🚀 Enrichment: Processing \(uniqueCallsigns.count) callsign(s)...")
        
        enrichmentTask = Task { @MainActor in
            for (idx, callsign) in uniqueCallsigns.enumerated() {
                if Task.isCancelled { break }
                
                self.appendLog("[\(idx + 1)/\(uniqueCallsigns.count)] Step 1/2: Fetching Ranks for \(callsign)...")
                let (rankQSO, rankBand, rankDXCC) = await self.asyncFetchRank(for: callsign)
                
                if Task.isCancelled { break }
                
                self.appendLog("[\(idx + 1)/\(uniqueCallsigns.count)] Step 2/2: Extracting Email for \(callsign)...")
                let fetchedEmail = await QRZWebKitScraper.shared.fetchEmail(for: callsign)
                
                if Task.isCancelled { break }
                
                for i in 0..<self.qsoRecords.count {
                    if self.qsoRecords[i]["CALL"].uppercased() == callsign {
                        if !rankQSO.isEmpty { self.qsoRecords[i].fields["RANK_QSO"] = rankQSO }
                        if !rankBand.isEmpty { self.qsoRecords[i].fields["RANK_BAND"] = rankBand }
                        if !rankDXCC.isEmpty { self.qsoRecords[i].fields["RANK_DXCC"] = rankDXCC }
                        
                        if let email = fetchedEmail, !email.isEmpty {
                            self.qsoRecords[i].fields["EMAIL"] = email
                        }
                        
                        self.qsoRecords[i].fields["QRZ_URL"] = "https://www.qrz.com/db/\(callsign)"
                        self.qsoRecords[i].fields["APP_YAAM_ENRICHED"] = "Y"
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

    func sendEmail(to recipient: String, subject: String, body: String, completion: @escaping (Bool, String) -> Void) {
        
        let rawHost = UserDefaults.standard.string(forKey: "smtpHost")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let host = rawHost.isEmpty ? "smtp.gmail.com" : rawHost
        
        let rawPort = UserDefaults.standard.string(forKey: "smtpPort")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let port = rawPort.isEmpty ? "465" : rawPort
        
        let user = UserDefaults.standard.string(forKey: "smtpUser")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawPass = UserDefaults.standard.string(forKey: "smtpPass")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        let pass = rawPass.replacingOccurrences(of: " ", with: "")
        
        guard !host.isEmpty, !user.isEmpty, !pass.isEmpty else {
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
                    completion(true, "Email successfully sent to \(recipient)!")
                } else {
                    completion(false, "ERROR \(process.terminationStatus):\n\n" + outputLog)
                }
            } catch {
                completion(false, "Process Failed: \(error.localizedDescription)")
            }
        }
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
        let lastSyncDate = isFirstFullSync ? nil : (UserDefaults.standard.object(forKey: "lastLoTWSyncDate") as? Date)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        let sinceDateString = lastSyncDate != nil ? dateFormatter.string(from: lastSyncDate!) : "1900-01-01"
        
        if isFirstFullSync {
            appendLog("🚀 Launching FULL Historical QSL Sync (Fetching all confirmations since 1900)...")
        } else {
            appendLog("🔄 Launching Incremental QSL Sync (Fetching changes since \(sinceDateString))...")
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
                   let lotwEndpoint = URL(string: "https://lotw.arrl.org/lotwuser/lotwreport.adi?login=\(encodedUser)&password=\(encodedPass)&qso_query=1&qso_qslsince=\(sinceDateString)") {
                    
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
                                        
                                        if lotwRcvd == "Y" || lotwRcvd == "V" {
                                            for i in 0..<self.qsoRecords.count {
                                                if !self.qsoRecords[i].isConfirmed || self.qsoRecords[i].fields["LOTW_QSL_RCVD"] != "Y" {
                                                    let qCall = self.normalizeCallsign(self.qsoRecords[i]["CALL"])
                                                    let qDate = self.cleanDate(self.qsoRecords[i]["QSO_DATE"])
                                                    let qBand = self.cleanBand(self.qsoRecords[i]["BAND"])
                                                    
                                                    if qCall == call && qDate == date && (qBand.isEmpty || band.isEmpty || qBand == band) {
                                                        self.qsoRecords[i].fields["LOTW_QSL_RCVD"] = "Y"
                                                        self.qsoRecords[i].fields["QSL_RCVD"] = "Y"
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
                let qrzEndpointStr = "https://logbook.qrz.com/api?KEY=\(qrzKey)&ACTION=FETCH&OPTION=TYPE:ADIF&MODIFIEDSINCE=\(sinceDateString)"
                if let qrzEndpoint = URL(string: qrzEndpointStr) {
                    var request = URLRequest(url: qrzEndpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 45)
                    request.setValue("YAAM-macOS/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")
                    
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        defer { group.leave() }
                        
                        if let data = data, let reportADIF = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                            if reportADIF.contains("<") && reportADIF.contains(">") {
                                let (_, serverRecords) = parseADIF(content: reportADIF)
                                fetchedRecordsCount += serverRecords.count
                                syncLogs.append("QRZ: Server returned \(serverRecords.count) logbook records.")
                                
                                DispatchQueue.main.async {
                                    for rec in serverRecords {
                                        let call = self.normalizeCallsign(rec["CALL"] ?? "")
                                        let date = self.cleanDate(rec["QSO_DATE"] ?? "")
                                        let band = self.cleanBand(rec["BAND"] ?? "")
                                        let qrzRcvd = (rec["QRZLOG_QSL_RCVD"] ?? rec["APP_QRZLOG_STATUS"] ?? rec["QSL_RCVD"] ?? "").uppercased()
                                        
                                        if qrzRcvd == "Y" || qrzRcvd == "CONFIRMED" || qrzRcvd == "C" {
                                            for i in 0..<self.qsoRecords.count {
                                                if !self.qsoRecords[i].isConfirmed || self.qsoRecords[i].fields["QRZLOG_QSL_RCVD"] != "Y" {
                                                    let qCall = self.normalizeCallsign(self.qsoRecords[i]["CALL"])
                                                    let qDate = self.cleanDate(self.qsoRecords[i]["QSO_DATE"])
                                                    let qBand = self.cleanBand(self.qsoRecords[i]["BAND"])
                                                    
                                                    if qCall == call && qDate == date && (qBand.isEmpty || band.isEmpty || qBand == band) {
                                                        self.qsoRecords[i].fields["QRZLOG_QSL_RCVD"] = "Y"
                                                        self.qsoRecords[i].fields["QSL_RCVD"] = "Y"
                                                        newlyConfirmedCount += 1
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }.resume()
                } else {
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                self.isSyncingAPI = false
                UserDefaults.standard.set(Date(), forKey: "lastLoTWSyncDate")
                
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
                } else {
                    self.appendLog("⚪ Sync Complete: All confirmations are up to date (\(fetchedRecordsCount) records checked).")
                    self.alertTitle = "Log Up To Date ⚪"
                    self.alertMessage = "Checked \(fetchedRecordsCount) cloud records. All confirmations in your log are up to date."
                    self.showAlert = true
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
