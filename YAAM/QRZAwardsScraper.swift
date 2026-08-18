//
//  QRZAwardsScraper.swift
//  YAAM
//

import Foundation
import WebKit

@MainActor
final class QRZAwardsScraper: NSObject, WKNavigationDelegate {
    static let shared = QRZAwardsScraper()

    private enum Stage {
        case idle
        case loadingLogbook
        case authenticating
        case loadingAwards
        case analyzingAwards
    }

    private var webView: WKWebView!
    private var continuation: CheckedContinuation<QRZAwardsFetchResult, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var stage: Stage = .idle
    private var username = ""
    private var password = ""
    private var usernameSubmitted = false
    private var passwordSubmitted = false
    private var flowPollCount = 0
    private var requestID: UUID?

    override init() {
        super.init()
        let config = QRZWebKitSession.browserLikeConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1360, height: 1000), configuration: config)
        webView.customUserAgent = QRZWebKitSession.userAgent
        webView.navigationDelegate = self
    }

    func fetchAwards(username: String, password: String) async -> QRZAwardsFetchResult {
        if continuation != nil {
            finish(QRZAwardsFetchResult(
                awards: [],
                message: "The previous QRZ Awards lookup was replaced by a new request."
            ))
        }

        return await withCheckedContinuation { continuation in
            let requestID = UUID()
            self.continuation = continuation
            self.requestID = requestID
            self.username = username
            self.password = password
            self.stage = .loadingLogbook
            self.usernameSubmitted = false
            self.passwordSubmitted = false
            self.flowPollCount = 0
            self.timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard !Task.isCancelled, self.requestID == requestID else { return }
                self.webView.stopLoading()
                self.finish(QRZAwardsFetchResult(
                    awards: [],
                    message: "QRZ Awards lookup timed out while waiting for award analysis. Open QRZ Login if QRZ requires MFA or a browser challenge."
                ))
            }

            QRZSessionStore.restoreToWebKit { [weak self] in
                guard let self, self.requestID == requestID else { return }
                self.loadLogbook()
            }
        }
    }

    private func loadLogbook() {
        guard let url = URL(string: "https://logbook.qrz.com/logbook") else {
            finish(QRZAwardsFetchResult(awards: [], message: "Invalid QRZ Logbook URL."))
            return
        }
        stage = .loadingLogbook
        webView.load(QRZWebKitSession.browserLikeRequest(url: url, timeoutInterval: 30))
    }

    private func finish(_ result: QRZAwardsFetchResult) {
        timeoutTask?.cancel()
        timeoutTask = nil
        stage = .idle
        requestID = nil
        username = ""
        password = ""
        usernameSubmitted = false
        passwordSubmitted = false
        flowPollCount = 0

        let activeContinuation = continuation
        continuation = nil
        activeContinuation?.resume(returning: result)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.handlePageLoaded()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            self.finish(QRZAwardsFetchResult(awards: [], message: "QRZ navigation failed: \(error.localizedDescription)"))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            self.finish(QRZAwardsFetchResult(awards: [], message: "QRZ navigation failed: \(error.localizedDescription)"))
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            self.finish(QRZAwardsFetchResult(
                awards: [],
                message: "QRZ stopped responding while awards were being analyzed."
            ))
        }
    }

    private func handlePageLoaded() {
        switch stage {
        case .idle, .analyzingAwards:
            return
        case .loadingLogbook, .authenticating:
            inspectLoginOrLogbook()
        case .loadingAwards:
            waitForAwardsDOM(attempt: 0, lastAction: "navigation")
        }
    }

    private func inspectLoginOrLogbook() {
        guard continuation != nil else { return }

        webView.callAsyncJavaScript(
            Self.loginInspectionScript,
            arguments: [
                "username": username,
                "password": password,
                "canSubmitUsername": !usernameSubmitted,
                "canSubmitPassword": !passwordSubmitted
            ],
            in: nil,
            in: .page
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, self.continuation != nil else { return }

                switch result {
                case .success(let payload):
                    self.handleLoginInspectionPayload(payload as? [String: Any] ?? [:])
                case .failure(let error):
                    let nsError = error as NSError
                    let detail = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String
                        ?? nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String
                        ?? error.localizedDescription
                    self.finish(QRZAwardsFetchResult(
                        awards: [],
                        message: "Unable to inspect the QRZ login page: \(detail)"
                    ))
                }
            }
        }
    }

    private func handleLoginInspectionPayload(_ payload: [String: Any]) {
        let action = payload["action"] as? String ?? ""
        let pageError = (payload["error"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        switch action {
        case "username-submitted":
            usernameSubmitted = true
            stage = .authenticating
            scheduleFlowInspection(after: 0.5)
        case "password-submitted":
            passwordSubmitted = true
            stage = .authenticating
            scheduleFlowInspection(after: 1.0)
        case "logbook-ready":
            saveCurrentQRZSession()
            openAwardsPage()
        case "awards-ready":
            saveCurrentQRZSession()
            startAwardAnalysis()
        case "mfa-required":
            finish(QRZAwardsFetchResult(
                awards: [],
                message: "QRZ requires a two-factor authentication code. Complete QRZ Login once, save the session, then refresh Awards."
            ))
        case "browser-challenge":
            finish(QRZAwardsFetchResult(
                awards: [],
                message: "QRZ requires a browser verification challenge. Complete QRZ Login once, save the session, then refresh Awards."
            ))
        case "username-wait", "password-wait", "page-wait":
            if !pageError.isEmpty {
                finish(QRZAwardsFetchResult(awards: [], message: "QRZ login was not accepted: \(pageError)"))
            } else if flowPollCount >= 40 {
                let url = payload["url"] as? String ?? webView.url?.absoluteString ?? ""
                finish(QRZAwardsFetchResult(awards: [], message: "QRZ login did not complete. Last page: \(url)"))
            } else {
                scheduleFlowInspection(after: 0.5)
            }
        case "script-error":
            let stack = (payload["stack"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = stack.isEmpty ? "" : " [\(stack.prefix(240))]"
            finish(QRZAwardsFetchResult(
                awards: [],
                message: "Unable to inspect the QRZ login page: \(pageError.isEmpty ? "Unknown JavaScript error" : pageError)\(suffix)"
            ))
        default:
            finish(QRZAwardsFetchResult(
                awards: [],
                message: "QRZ login form changed and could not be completed (\(action))."
            ))
        }
    }

    private static let loginInspectionScript = #"""
        try {
            function text(el) {
                return (el && (el.innerText || el.textContent || el.value) || "").replace(/\s+/g, " ").trim();
            }
            function visible(el) {
                if (!el) { return false; }
                var rect = el.getBoundingClientRect();
                var style = window.getComputedStyle(el);
                return rect.width > 1 && rect.height > 1 && style.display !== "none" && style.visibility !== "hidden";
            }
            function setValue(input, value) {
                var prototype = Object.getPrototypeOf(input);
                var descriptor = prototype ? Object.getOwnPropertyDescriptor(prototype, "value") : null;
                if (descriptor && descriptor.set) {
                    descriptor.set.call(input, value);
                } else {
                    input.value = value;
                }
                input.dispatchEvent(new Event("input", { bubbles: true }));
                input.dispatchEvent(new Event("change", { bubbles: true }));
            }
            function submitSoon(control, form) {
                window.setTimeout(function() {
                    if (control && control.isConnected) {
                        control.click();
                        return;
                    }
                    if (form && form.isConnected) {
                        if (typeof form.requestSubmit === "function") {
                            form.requestSubmit();
                        } else {
                            form.submit();
                        }
                    }
                }, 100);
            }
            function visibleSubmit(pattern) {
                return Array.from(document.querySelectorAll('button[type="submit"], input[type="submit"], button, input[type="button"]'))
                    .find(function(el) { return visible(el) && pattern.test(text(el)); });
            }

            var body = text(document.body);
            var url = location.href;
            var awardHeaders = document.querySelectorAll('#accordion .awardContainerHeader').length;
            if (awardHeaders > 0 || document.querySelector('.issuedAwardsTable, #issuedAwardsBlock')) {
                return { action: "awards-ready", awardHeaders: awardHeaders, url: url };
            }

            var twoFactor = document.getElementById("2fcode")
                || document.querySelector('input[name="2fcode"], input[autocomplete="one-time-code"]');
            if (visible(twoFactor)) {
                return { action: "mfa-required", url: url };
            }

            if (/captcha|verify you are human|browser challenge|checking your browser/i.test(body)) {
                return { action: "browser-challenge", url: url };
            }

            var passwordInput = document.querySelector('#password, input[name="password"], input[type="password"]');
            if (visible(passwordInput)) {
                var passwordError = text(document.querySelector('.alert-danger, .login-error, .error, .invalid-feedback, #passwordError'));
                if (!canSubmitPassword) {
                    return { action: "password-wait", error: passwordError, url: url };
                }
                setValue(passwordInput, password);
                var signIn = visibleSubmit(/sign in|log in|login|submit/i);
                if (signIn) {
                    submitSoon(signIn, passwordInput.form);
                    return { action: "password-submitted", url: url };
                }
                if (passwordInput.form) {
                    submitSoon(null, passwordInput.form);
                    return { action: "password-submitted", url: url };
                }
                return { action: "password-form-missing", url: url };
            }

            var usernameInput = document.querySelector('#username, input[name="username"], input[name="u"], input[name="login"]');
            if (visible(usernameInput)) {
                var usernameError = text(document.querySelector('.alert-danger, .login-error, .error, .invalid-feedback, #usernameError'));
                if (!canSubmitUsername) {
                    return { action: "username-wait", error: usernameError, url: url };
                }
                setValue(usernameInput, username);
                var next = visibleSubmit(/next|continue|sign in|log in|login/i);
                if (next) {
                    submitSoon(next, usernameInput.form);
                    return { action: "username-submitted", url: url };
                }
                if (usernameInput.form) {
                    submitSoon(null, usernameInput.form);
                    return { action: "username-submitted", url: url };
                }
                return { action: "username-form-missing", url: url };
            }

            if (location.hostname === "logbook.qrz.com" && (typeof lb_go === "function" || document.querySelector('#lbmenu'))) {
                return { action: "logbook-ready", url: url };
            }

            return {
                action: "page-wait",
                url: url,
                title: document.title,
                body: body.slice(0, 300)
            };
        } catch (error) {
            return {
                action: "script-error",
                error: error && error.message ? error.message : String(error),
                stack: error && error.stack ? String(error.stack) : "",
                url: location.href
            };
        }
    """#

    private func scheduleFlowInspection(after delay: TimeInterval) {
        flowPollCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.continuation != nil else { return }
            guard self.stage == .loadingLogbook || self.stage == .authenticating else { return }
            self.inspectLoginOrLogbook()
        }
    }

    private func openAwardsPage() {
        guard continuation != nil else { return }
        stage = .loadingAwards

        let script = """
        (function() {
            if (document.querySelector('#issuedAwardsBlock, .issuedAwardsTable, #accordion .awardContainerHeader')) {
                return { action: "visible" };
            }
            if (typeof lb_go === "function") {
                lb_go("awards", "");
                return { action: "lb_go('awards', '')" };
            }
            var form = document.querySelector('form#lbmenu');
            if (form) {
                var op = form.querySelector('input[name="op"]');
                if (!op) {
                    op = document.createElement("input");
                    op.type = "hidden";
                    op.name = "op";
                    form.appendChild(op);
                }
                op.value = "awards";
                window.setTimeout(function() { form.submit(); }, 100);
                return { action: "awards-form fallback" };
            }
            return { action: "not-found", url: location.href, title: document.title };
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, self.continuation != nil else { return }
            if let error {
                self.finish(QRZAwardsFetchResult(
                    awards: [],
                    message: "Could not open QRZ Awards: \(error.localizedDescription)"
                ))
                return
            }

            let action = (result as? [String: Any])?["action"] as? String ?? ""
            if action == "not-found" {
                self.finish(QRZAwardsFetchResult(
                    awards: [],
                    message: "The QRZ Logbook page did not expose lb_go('awards', '')."
                ))
                return
            }

            let initialDelay = action == "visible" ? 0.1 : 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) {
                self.waitForAwardsDOM(attempt: 0, lastAction: action)
            }
        }
    }

    private func waitForAwardsDOM(attempt: Int, lastAction: String) {
        guard continuation != nil, stage == .loadingAwards else { return }

        let script = """
        (function() {
            var awardedRows = document.querySelectorAll('.issuedAwardsTable tr.awardRow, #issuedAwardsBlock tr.awardRow').length;
            var awardHeaders = document.querySelectorAll('#accordion .awardContainerHeader').length;
            return {
                ready: awardHeaders > 0,
                awardedRows: awardedRows,
                awardHeaders: awardHeaders,
                loginVisible: !!Array.from(document.querySelectorAll('#username, #password, input[name="username"], input[name="password"]')).find(function(el) {
                    var rect = el.getBoundingClientRect();
                    return rect.width > 1 && rect.height > 1;
                }),
                url: location.href,
                title: document.title
            };
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, self.continuation != nil, self.stage == .loadingAwards else { return }
            if let error {
                self.finish(QRZAwardsFetchResult(
                    awards: [],
                    message: "Could not inspect QRZ Awards: \(error.localizedDescription)"
                ))
                return
            }

            let payload = result as? [String: Any] ?? [:]
            let isReady = payload["ready"] as? Bool ?? false
            let loginVisible = payload["loginVisible"] as? Bool ?? false

            if isReady {
                self.startAwardAnalysis()
                return
            }

            if loginVisible {
                self.stage = .authenticating
                self.inspectLoginOrLogbook()
                return
            }

            if attempt >= 60 {
                let awardedRows = (payload["awardedRows"] as? NSNumber)?.intValue ?? 0
                let awardHeaders = (payload["awardHeaders"] as? NSNumber)?.intValue ?? 0
                let url = payload["url"] as? String ?? ""
                self.finish(QRZAwardsFetchResult(
                    awards: [],
                    message: "QRZ Awards did not finish loading after \(lastAction). Rows: \(awardedRows), award definitions: \(awardHeaders), page: \(url)"
                ))
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.waitForAwardsDOM(attempt: attempt + 1, lastAction: lastAction)
            }
        }
    }

    private func startAwardAnalysis() {
        guard continuation != nil, stage != .analyzingAwards else { return }
        stage = .analyzingAwards

        webView.callAsyncJavaScript(
            Self.awardAnalysisScript,
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            Task { @MainActor in
                self?.handleAwardAnalysisResult(result)
            }
        }
    }

    private func handleAwardAnalysisResult(_ result: Result<Any, Error>) {
        guard continuation != nil else { return }

        let value: Any
        switch result {
        case .success(let payload):
            value = payload
        case .failure(let error):
            finish(QRZAwardsFetchResult(
                awards: [],
                message: "QRZ award analysis failed: \(error.localizedDescription)"
            ))
            return
        }

        let payload = value as? [String: Any] ?? [:]
        let rawAwards = payload["awards"] as? [[String: Any]] ?? []
        let awards = rawAwards.compactMap(Self.awardSummary(from:))
        let uniqueAwards = Dictionary(grouping: awards, by: \.id).compactMap { _, candidates in
            candidates.max { lhs, rhs in
                let lhsScore = (lhs.earned ? 4 : 0) + (lhs.progressAvailable ? 2 : 0) + (lhs.detail.isEmpty ? 0 : 1)
                let rhsScore = (rhs.earned ? 4 : 0) + (rhs.progressAvailable ? 2 : 0) + (rhs.detail.isEmpty ? 0 : 1)
                return lhsScore < rhsScore
            }
        }
        .sorted {
            if $0.earned != $1.earned { return $0.earned && !$1.earned }
            if $0.progressAvailable != $1.progressAvailable { return $0.progressAvailable && !$1.progressAvailable }
            return $0.percentComplete > $1.percentComplete
        }

        if uniqueAwards.isEmpty {
            let pageError = payload["error"] as? String ?? "QRZ returned no award definitions."
            finish(QRZAwardsFetchResult(awards: [], message: pageError))
            return
        }

        let analyzed = uniqueAwards.filter(\.progressAvailable).count
        let awarded = uniqueAwards.filter(\.earned).count
        let failed = (payload["failed"] as? NSNumber)?.intValue ?? max(0, uniqueAwards.count - analyzed)
        let suffix = failed > 0 ? " \(failed) item(s) did not return analyzable progress." : ""
        finish(QRZAwardsFetchResult(
            awards: uniqueAwards,
            message: "Loaded \(uniqueAwards.count) QRZ awards: \(awarded) awarded and \(analyzed) with progress.\(suffix)"
        ))
    }

    private static func awardSummary(from payload: [String: Any]) -> QRZAwardSummary? {
        let title = (payload["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 140 else { return nil }

        let detail = (payload["detail"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let status = (payload["status"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let percent = min(max((payload["percent"] as? NSNumber)?.doubleValue ?? 0, 0), 100)
        let earned = (payload["earned"] as? Bool) ?? (percent >= 100)
        let progressAvailable = (payload["progressAvailable"] as? Bool) ?? earned
        let achievement = (payload["achievement"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let awardType = (payload["awardType"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ribbonURL = (payload["ribbonURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let awardID = (payload["awardID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let id = awardID.isEmpty ? slug : "qrz-award-\(awardID)"

        guard !id.isEmpty else { return nil }
        return QRZAwardSummary(
            id: id,
            title: title,
            detail: detail,
            percentComplete: earned ? max(percent, 100) : percent,
            status: status.isEmpty ? (earned ? "Award received" : "In progress") : status,
            earned: earned,
            progressAvailable: progressAvailable,
            achievement: achievement.isEmpty ? (earned ? "Award received" : "Not reported") : achievement,
            awardType: awardType,
            ribbonURL: ribbonURL
        )
    }

    private func saveCurrentQRZSession() {
        QRZWebKitSession.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let qrzCookies = cookies.filter { $0.domain.contains("qrz.com") }
            guard !qrzCookies.isEmpty else { return }
            DispatchQueue.main.async {
                _ = QRZSessionStore.save(cookies: qrzCookies)
            }
        }
    }

    private static let awardAnalysisScript = #"""
    function normalizedText(el) {
        return (el && (el.innerText || el.textContent || el.value) || "").replace(/\s+/g, " ").trim();
    }

    function cleanTitle(value) {
        return String(value || "")
            .replace(/\s+/g, " ")
            .replace(/\s+Type:\s*(CW|Digital|Mixed|Phone).*$/i, "")
            .trim();
    }

    function numeric(value) {
        var number = Number(String(value || "").replace(/,/g, "").trim());
        return Number.isFinite(number) ? number : null;
    }

    function clampPercent(value) {
        return Math.max(0, Math.min(100, value));
    }

    function formatNumber(value) {
        return Number(value).toLocaleString("en-US", { maximumFractionDigits: 2 });
    }

    function findRatio(doc, fullText) {
        var candidates = [];
        Array.from(doc.querySelectorAll("tr, li, p, .summary, .awardSummary, .awardStatus, .progressText, div")).forEach(function(el) {
            var value = normalizedText(el);
            if (value.length >= 3 && value.length <= 220 && /achievement|progress|confirmed|credit|worked|required|needed|goal|qualif/i.test(value)) {
                candidates.push(value);
            }
        });
        if (!candidates.length) { candidates.push(fullText); }

        for (var i = 0; i < candidates.length; i += 1) {
            var match = candidates[i].match(/([0-9][0-9,]*)\s*(?:\/|of|out\s+of)\s*([0-9][0-9,]*)/i);
            if (!match) { continue; }
            var current = numeric(match[1]);
            var target = numeric(match[2]);
            if (current !== null && target !== null && target > 0 && current >= 0) {
                return {
                    current: current,
                    target: target,
                    text: formatNumber(current) + " / " + formatNumber(target)
                };
            }
        }
        return null;
    }

    function explicitPercent(rawHTML, doc, awardID) {
        var escapedID = String(awardID).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        var originalPattern = new RegExp(
            "originalVal\\s*\\[\\s*['\\\"]?" + escapedID + "['\\\"]?\\s*\\]\\s*=\\s*['\\\"]?([0-9]+(?:\\.[0-9]+)?)",
            "i"
        );
        var originalMatch = rawHTML.match(originalPattern);
        if (originalMatch) {
            var original = numeric(originalMatch[1]);
            if (original !== null && original >= 0 && original <= 100) { return original; }
        }

        var knob = doc.querySelector("#knob-" + String(awardID) + ", input.knob, input.dial, [data-role='knob']");
        if (knob) {
            var knobValue = numeric(knob.getAttribute("value") || knob.value || knob.getAttribute("data-value"));
            if (knobValue !== null && knobValue >= 0 && knobValue <= 100) { return knobValue; }
        }

        var progressElements = Array.from(doc.querySelectorAll("[aria-valuenow], [data-percent], [data-progress], .progress-bar, meter, progress"));
        for (var i = 0; i < progressElements.length; i += 1) {
            var el = progressElements[i];
            var values = [
                el.getAttribute("aria-valuenow"),
                el.getAttribute("data-percent"),
                el.getAttribute("data-progress"),
                el.getAttribute("value")
            ];
            var widthMatch = (el.getAttribute("style") || "").match(/width\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*%/i);
            if (widthMatch) { values.push(widthMatch[1]); }
            for (var j = 0; j < values.length; j += 1) {
                var candidate = numeric(values[j]);
                if (candidate !== null && candidate >= 0 && candidate <= 100) { return candidate; }
            }
        }

        var pageText = normalizedText(doc.body);
        var textMatch = pageText.match(/(?:achievement|progress|complete)[^%]{0,60}?([0-9]+(?:\.[0-9]+)?)\s*%/i);
        if (!textMatch) { textMatch = pageText.match(/([0-9]+(?:\.[0-9]+)?)\s*%/); }
        if (textMatch) {
            var textValue = numeric(textMatch[1]);
            if (textValue !== null && textValue >= 0 && textValue <= 100) { return textValue; }
        }
        return null;
    }

    function usefulDetail(doc, fallback) {
        var details = [];
        Array.from(doc.querySelectorAll(".awardSummary, .summary, .awardStatus, .progressText, p, li, table tr")).forEach(function(el) {
            var value = normalizedText(el);
            if (value.length < 8 || value.length > 180) { return; }
            if (/analyzing|please wait|logbook handbook|purchase certificate/i.test(value)) { return; }
            if (!/achievement|progress|confirmed|contacts?|entities|countries|states|counties|grids|continents|prefix|letters|qso|needed|required|remaining|qualified|eligible|award/i.test(value)) { return; }
            if (details.indexOf(value) === -1) { details.push(value); }
        });
        if (details.length) { return details.slice(0, 2).join(" • "); }
        return fallback || "QRZ Logbook award analysis";
    }

    function parseAnalysis(descriptor, rawHTML, issued) {
        var doc = new DOMParser().parseFromString(rawHTML, "text/html");
        var fullText = normalizedText(doc.body);
        var loginResponse = !!doc.querySelector("#login-form, input[name='username'], input[name='password']") || /Please Sign In to QRZ/i.test(fullText);
        if (loginResponse) { throw new Error("QRZ session expired during award analysis"); }

        var ratio = findRatio(doc, fullText);
        var percent = explicitPercent(rawHTML, doc, descriptor.id);
        if (percent === null && ratio) {
            percent = clampPercent((ratio.current / ratio.target) * 100);
        }

        var earned = !!issued;
        var qualified = !earned && /congratulations|apply now|qualified|eligible to apply|you have achieved/i.test(fullText);
        if (earned) { percent = 100; }
        var progressAvailable = percent !== null;
        var achievement;
        if (earned) {
            achievement = "Award received";
        } else if (qualified) {
            achievement = ratio ? ratio.text : "Qualified";
        } else if (ratio) {
            achievement = ratio.text;
        } else if (progressAvailable) {
            achievement = Math.round(percent) + "% complete";
        } else {
            achievement = "Not reported";
        }

        return {
            awardID: descriptor.id,
            title: descriptor.title,
            detail: usefulDetail(doc, issued ? issued.info : ""),
            percent: progressAvailable ? clampPercent(percent) : 0,
            progressAvailable: progressAvailable,
            status: earned ? "Award received" : (qualified ? "Qualified to apply" : (progressAvailable ? "In progress" : "Progress unavailable")),
            earned: earned,
            achievement: achievement,
            awardType: "Mode: " + descriptor.mode,
            ribbonURL: descriptor.ribbonURL
        };
    }

    var issuedByID = {};
    Array.from(document.querySelectorAll(".issuedAwardsTable tr.awardRow, #issuedAwardsBlock tr.awardRow")).forEach(function(row) {
        var analyzeLink = Array.from(row.querySelectorAll("a")).find(function(link) {
            return /showAward\s*\(/i.test(link.getAttribute("href") || "");
        });
        var href = analyzeLink ? (analyzeLink.getAttribute("href") || "") : "";
        var match = href.match(/showAward\s*\(\s*['\"]([^'\"]*)['\"]\s*,\s*['\"]?([0-9]+)/i);
        if (!match) { return; }

        var nameElement = row.querySelector(".awardName");
        var nameClone = nameElement ? nameElement.cloneNode(true) : null;
        if (nameClone) {
            Array.from(nameClone.querySelectorAll("a, small, .awardInfo")).forEach(function(el) { el.remove(); });
        }
        issuedByID[match[2]] = {
            id: match[2],
            books: match[1],
            title: cleanTitle(normalizedText(nameClone)),
            info: normalizedText(row.querySelector(".awardInfo")) || "Issued by QRZ Logbook Awards"
        };
    });

    var descriptors = Array.from(document.querySelectorAll("#accordion .awardContainerHeader")).map(function(header) {
        var idMatch = (header.id || "").match(/header-([0-9]+)/);
        if (!idMatch) { return null; }
        var titleSpan = Array.from(header.children).find(function(child) {
            return child.tagName === "SPAN" && !child.classList.contains("ui-accordion-header-icon");
        });
        var selector = header.querySelector("select.awardTypeSelector");
        var image = header.querySelector("img");
        return {
            id: idMatch[1],
            title: cleanTitle(normalizedText(titleSpan) || normalizedText(header)),
            mode: selector ? (selector.value || "Mixed") : "Mixed",
            ribbonURL: image ? (image.src || image.getAttribute("src") || "") : ""
        };
    }).filter(function(item) { return item && item.title; });

    if (!descriptors.length) {
        return { awards: [], failed: 0, error: "QRZ returned the Awards page without any award definitions." };
    }

    var selectedBooks = Array.from(document.querySelectorAll("#listbooks option:checked")).map(function(option) { return option.value; });
    if (!selectedBooks.length) {
        selectedBooks = Array.from(document.querySelectorAll("#listbooks option")).map(function(option) { return option.value; });
    }
    var extraBooksInput = document.querySelector("#addlistbooks");
    var extraBooks = extraBooksInput ? extraBooksInput.value : "";
    if (extraBooks) { selectedBooks = selectedBooks.concat(extraBooks.split(",")); }
    selectedBooks = Array.from(new Set(selectedBooks.filter(Boolean))).sort(function(a, b) { return Number(a) - Number(b); });

    var books = selectedBooks.join(",");
    var sbookInput = document.querySelector("input[name='sbook']");
    var sbook = sbookInput ? sbookInput.value : "0";
    var endpoint = (typeof THIS === "string" && THIS) ? THIS : location.origin;
    var results = new Array(descriptors.length);
    var failed = 0;
    var nextIndex = 0;

    async function analyzeOne(descriptor) {
        var body = new URLSearchParams({
            op: "analyze",
            award: descriptor.id,
            books: books,
            sbook: sbook,
            incmode: descriptor.mode
        });
        var controller = new AbortController();
        var timer = setTimeout(function() { controller.abort(); }, 25000);
        try {
            var response = await fetch(endpoint, {
                method: "POST",
                credentials: "include",
                headers: {
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "X-Requested-With": "XMLHttpRequest"
                },
                body: body.toString(),
                signal: controller.signal
            });
            if (!response.ok) { throw new Error("HTTP " + response.status); }
            var html = await response.text();
            return parseAnalysis(descriptor, html, issuedByID[descriptor.id]);
        } catch (error) {
            failed += 1;
            var issued = issuedByID[descriptor.id];
            return {
                awardID: descriptor.id,
                title: descriptor.title,
                detail: issued ? issued.info : "QRZ did not return analysis for this award.",
                percent: issued ? 100 : 0,
                progressAvailable: !!issued,
                status: issued ? "Award received" : "Progress unavailable",
                earned: !!issued,
                achievement: issued ? "Award received" : "Not reported",
                awardType: "Mode: " + descriptor.mode,
                ribbonURL: descriptor.ribbonURL
            };
        } finally {
            clearTimeout(timer);
        }
    }

    async function worker() {
        while (true) {
            var index = nextIndex;
            nextIndex += 1;
            if (index >= descriptors.length) { return; }
            results[index] = await analyzeOne(descriptors[index]);
        }
    }

    var workerCount = Math.min(4, descriptors.length);
    await Promise.all(Array.from({ length: workerCount }, function() { return worker(); }));

    Object.keys(issuedByID).forEach(function(id) {
        if (descriptors.some(function(item) { return item.id === id; })) { return; }
        var issued = issuedByID[id];
        results.push({
            awardID: id,
            title: issued.title || ("QRZ Award " + id),
            detail: issued.info,
            percent: 100,
            progressAvailable: true,
            status: "Award received",
            earned: true,
            achievement: "Award received",
            awardType: "",
            ribbonURL: ""
        });
    });

    return { awards: results.filter(Boolean), failed: failed, total: descriptors.length };
    """#
}
