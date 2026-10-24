import Foundation
import Combine
import WebKit

/// QRZ evidence only: an empty local EMAIL field or a failed lookup is never proof of absence.
nonisolated enum QRZIncomingEmailStatus: Equatable, Sendable {
    case unchecked, checking, available(String), notPublished, signInRequired, unavailable

    var title: String {
        switch self {
        case .unchecked: return "QRZ email not checked"
        case .checking: return "Checking QRZ email…"
        case .available: return "QRZ email available"
        case .notPublished: return "No published QRZ email · signed-in check"
        case .signInRequired: return "Sign in to QRZ to check email"
        case .unavailable: return "QRZ email check unavailable · retry or check QRZ Login"
        }
    }
    var permitsMissingEmailRejection: Bool { self == .notPublished }
}

nonisolated enum QRZIncomingEmailEvidence {
    static let rejectionComment = "Unable to request the QSO details because no email address is published on your QRZ profile."

    static func normalizedCall(_ raw: String) -> String? {
        let call = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (3...30).contains(call.count),
              call.range(of: #"^[A-Z0-9]+(?:/[A-Z0-9]+)*$"#, options: .regularExpression) != nil else { return nil }
        return call
    }

    static func status(call: String, url: URL?, profileCall: String, fieldExists: Bool,
                       fieldText: String, encodedEmail: String, blocked: Bool, authenticated: Bool) -> QRZIncomingEmailStatus {
        guard let call = normalizedCall(call), !blocked, let url,
              url.scheme == "https", ["qrz.com", "www.qrz.com"].contains(url.host?.lowercased() ?? "") else { return .unavailable }
        guard authenticated else { return .signInRequired }
        guard url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).uppercased() == "DB/" + call,
              normalizedCall(profileCall) == call else { return .unavailable }
        let text = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.range(of: #"login|log in|sign in|captcha|verify|javascript"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return .signInRequired
        }
        if let email = usableEmail(decodeQmail(encodedEmail)) { return .available(email) }
        if fieldExists, let email = usableEmail(text) { return .available(email) }
        // A recognized, explicitly absent official email field is required.
        // Missing markup, a hidden/reveal field or malformed qmail remains unknown.
        guard fieldExists, encodedEmail.isEmpty else { return .unavailable }
        if text.range(of: #"^\(?(?:none|n/a|not (?:provided|listed|published|available|supplied)|no (?:e-?mail)(?: address)?(?: (?:provided|listed|published|available|on file))?)\)?[.!]?$"#,
                                      options: [.regularExpression, .caseInsensitive]) != nil {
            return .notPublished
        }
        return .unavailable
    }

    private static func usableEmail(_ value: String) -> String? {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.range(of: #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#,
                          options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return email
    }

    private static func decodeQmail(_ encoded: String) -> String {
        let chars = Array(encoded)
        guard let delimiter = chars.lastIndex(of: "!"), delimiter > 0,
              let count = Int(String(chars[(delimiter + 1)...].reversed())),
              count > 0, count <= 320, delimiter >= count * 2 - 1 else { return "" }
        return String((0..<count).map { chars[delimiter - 1 - $0 * 2] })
    }
}

/// Own WebView and one operation at a time; never replaces the shared enrichment scraper's work.
@MainActor final class QRZIncomingEmailChecker: ObservableObject {
    @Published private(set) var states: [String: QRZIncomingEmailStatus] = [:]
    @Published private(set) var checkingCall: String?
    private var task: Task<Void, Never>?
    private var reader: QRZIncomingEmailReader?
    private var generation = UUID()
    private let lookupOverride: (@MainActor (String) async -> QRZIncomingEmailStatus)?

    init(initialStates: [String: QRZIncomingEmailStatus] = [:],
         lookup: (@MainActor (String) async -> QRZIncomingEmailStatus)? = nil) {
        states = initialStates
        lookupOverride = lookup
    }

    func status(for call: String) -> QRZIncomingEmailStatus {
        states[QRZIncomingEmailEvidence.normalizedCall(call) ?? ""] ?? .unchecked
    }

    func check(_ rawCall: String) {
        guard checkingCall == nil, let call = QRZIncomingEmailEvidence.normalizedCall(rawCall) else { return }
        checkingCall = call
        states[call] = .checking
        let currentGeneration = generation
        let reader = lookupOverride == nil ? QRZIncomingEmailReader() : nil
        self.reader = reader
        task = Task { @MainActor in
            let result: QRZIncomingEmailStatus
            if let lookupOverride { result = await lookupOverride(call) }
            else if let reader { result = await reader.fetch(call) }
            else { result = .unavailable }
            guard !Task.isCancelled, generation == currentGeneration else { return }
            states[call] = result
            checkingCall = nil
            self.reader = nil
            task = nil
        }
    }

    func reset() {
        generation = UUID()
        task?.cancel(); task = nil
        reader?.cancel(); reader = nil
        checkingCall = nil
        states = [:]
    }
}

@MainActor private final class QRZIncomingEmailReader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView!
    private var continuation: CheckedContinuation<QRZIncomingEmailStatus, Never>?
    private var timeout: Task<Void, Never>?
    private var call = ""
    private var operationID = UUID()

    override init() {
        super.init()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: QRZWebKitSession.browserLikeConfiguration())
        webView.customUserAgent = QRZWebKitSession.userAgent
        webView.navigationDelegate = self
    }

    func fetch(_ call: String) async -> QRZIncomingEmailStatus {
        guard continuation == nil, let call = QRZIncomingEmailEvidence.normalizedCall(call),
              let url = URL(string: "https://www.qrz.com/db/" + call) else { return .unavailable }
        self.call = call
        let id = UUID(); operationID = id
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeout = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, operationID == id else { return }
                finish(.unavailable)
            }
            // Uses the existing QRZ session. Authentication and verification remain user controlled.
            QRZSessionStore.restoreToWebKit { [weak self] in
                guard let self, self.continuation != nil, self.operationID == id else { return }
                self.webView.load(QRZWebKitSession.browserLikeRequest(url: url, timeoutInterval: 15))
            }
        }
    }

    func cancel() { finish(.unavailable) }

    private func finish(_ status: QRZIncomingEmailStatus) {
        timeout?.cancel(); timeout = nil
        operationID = UUID()
        let pending = continuation; continuation = nil
        webView.stopLoading()
        pending?.resume(returning: status)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, self.continuation != nil else { return }
            let id = self.operationID
            let pageURL = webView.url
            let value = try? await webView.evaluateJavaScript(QRZIncomingEmailEvidence.script)
            let auth = (try? await webView.evaluateJavaScript(QRZAuthenticationPolicy.inspectionScript)) as? [String: Bool] ?? [:]
            let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
            }
            let session = cookies.contains {
                let name = $0.name.lowercased()
                return QRZAuthenticationPolicy.trustedHost($0.domain) && ($0.expiresDate ?? .distantFuture) > Date() &&
                    (name.contains("session") || name.contains("remember") || name.contains("login"))
            }
            let authenticated = QRZAuthenticationPolicy.evaluate(url: pageURL, logout: auth["logout"] == true,
                loginForm: auth["loginForm"] == true, challenge: auth["challenge"] == true, sessionCookie: session) == .authenticated
            guard webView.url == pageURL, self.continuation != nil, self.operationID == id else { return }
            guard let evidence = value as? [String: Any] else { self.finish(.unavailable); return }
            self.finish(QRZIncomingEmailEvidence.status(
                call: self.call, url: webView.url,
                profileCall: evidence["profileCall"] as? String ?? "",
                fieldExists: evidence["fieldExists"] as? Bool ?? false,
                fieldText: evidence["fieldText"] as? String ?? "",
                encodedEmail: evidence["encodedEmail"] as? String ?? "",
                blocked: evidence["blocked"] as? Bool ?? true, authenticated: authenticated))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(.unavailable) }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(.unavailable) }
    }
    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        Task { @MainActor in
            let valid = !navigationResponse.isForMainFrame || (navigationResponse.response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } == true
            decisionHandler(valid ? .allow : .cancel)
            if !valid { self.finish(.unavailable) }
        }
    }
    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        Task { @MainActor in
            let valid = navigationAction.targetFrame?.isMainFrame != true || navigationAction.request.url.map {
                $0.scheme == "https" && ["qrz.com", "www.qrz.com"].contains($0.host?.lowercased() ?? "")
            } == true
            decisionHandler(valid ? .allow : .cancel)
            if !valid { self.finish(.unavailable) }
        }
    }
}

extension QRZIncomingEmailEvidence {
    // Only official profile metadata is inspected; biography, advertisements and arbitrary links are ignored.
    static let script = #"""
    (() => {
        const profile = document.querySelector('#csdata');
        const call = profile?.querySelector('.hamcall')?.textContent?.trim() || '';
        const field = profile ? Array.from(profile.querySelectorAll('p')).find(p => /^\s*Email\s*:/i.test(p.textContent || '')) : null;
        const qem = profile?.querySelector('#qem');
        const text = (qem?.textContent || field?.textContent || '').replace(/^\s*Email\s*:\s*/i, '').trim();
        return { profileCall: call, fieldExists: !!field || !!qem, fieldText: text,
            encodedEmail: typeof window.qmail === 'string' ? window.qmail : '',
            blocked: !!document.querySelector('#challenge-form, .g-recaptcha, #cf-challenge-running') || /just a moment|access denied|security check/i.test(document.title) };
    })();
    """#
}
