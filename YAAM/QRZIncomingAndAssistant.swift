//
//  QRZIncomingAndAssistant.swift
//  YAAM
//

import AppKit
import Foundation
import SwiftUI
import WebKit

nonisolated struct QRZIncomingConfirmation: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let callsign: String
    let qsoDate: String
    let requestedAt: String
    let rawSummary: String
    let qsoID: String

    enum CodingKeys: String, CodingKey {
        case id, callsign, qsoDate, requestedAt, rawSummary, qsoID
    }

    init(callsign: String, qsoDate: String, requestedAt: String, rawSummary: String, qsoID: String = "") {
        self.callsign = callsign
        self.qsoDate = qsoDate
        self.requestedAt = requestedAt
        self.rawSummary = rawSummary
        self.qsoID = qsoID
        id = "\(callsign)|\(qsoDate)|\(requestedAt)|\(rawSummary)"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callsign = try container.decode(String.self, forKey: .callsign)
        qsoDate = try container.decode(String.self, forKey: .qsoDate)
        requestedAt = try container.decode(String.self, forKey: .requestedAt)
        rawSummary = try container.decode(String.self, forKey: .rawSummary)
        qsoID = (try? container.decode(String.self, forKey: .qsoID)) ?? ""
        id = (try? container.decode(String.self, forKey: .id)) ?? "\(callsign)|\(qsoDate)|\(requestedAt)|\(rawSummary)"
    }
}

nonisolated struct QRZIncomingFetchResult: Sendable {
    let requests: [QRZIncomingConfirmation]
    let message: String
    let succeeded: Bool
}

nonisolated struct QRZRejectResult: Sendable {
    let succeeded: Bool
    let message: String
}

private let qrzIncomingRequestsCacheKey = "qrzIncomingRequests.v1"

// QRZ Logbook intentionally has no public API for confirmation requests. This
// small, session-bound reader only navigates the page the operator can open in a browser.
@MainActor
final class QRZIncomingScraper: NSObject, WKNavigationDelegate {
    static let shared = QRZIncomingScraper()

    private var webView: WKWebView!
    private var continuation: CheckedContinuation<QRZIncomingFetchResult, Never>?
    private var rejectContinuation: CheckedContinuation<QRZRejectResult, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pollCount = 0
    private var hasOpenedIncoming = false

    private var pendingRejectTarget: QRZIncomingConfirmation?
    private var pendingRejectReason: String = ""
    private var pendingRejectComments: String = ""
    private var isSubmittingReject = false
    private var rejectVerifyCount = 0

    override init() {
        super.init()
        let configuration = QRZWebKitSession.browserLikeConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration)
        webView.customUserAgent = QRZWebKitSession.userAgent
        webView.navigationDelegate = self
    }

    func fetchIncoming() async -> QRZIncomingFetchResult {
        if continuation != nil {
            finish(QRZIncomingFetchResult(requests: [], message: "The previous QRZ Incoming lookup was replaced.", succeeded: false))
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            pollCount = 0
            hasOpenedIncoming = false
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, self.continuation != nil else { return }
                self.webView.stopLoading()
                self.finish(QRZIncomingFetchResult(
                    requests: [],
                    message: "QRZ Incoming timed out. Open QRZ Login once if QRZ requires MFA or browser verification.",
                    succeeded: false
                ))
            }

            QRZSessionStore.restoreToWebKit { [weak self] in
                guard let self else { return }
                guard let url = URL(string: "https://logbook.qrz.com/logbook") else {
                    self.finish(QRZIncomingFetchResult(requests: [], message: "Invalid QRZ Logbook URL.", succeeded: false))
                    return
                }
                self.webView.load(QRZWebKitSession.browserLikeRequest(url: url, timeoutInterval: 30))
            }
        }
    }

    func rejectIncoming(request: QRZIncomingConfirmation, reason: String, comments: String) async -> QRZRejectResult {
        if rejectContinuation != nil {
            finishReject(QRZRejectResult(succeeded: false, message: "The previous QRZ rejection was replaced."))
        }
        if continuation != nil {
            finish(QRZIncomingFetchResult(requests: [], message: "Fetch cancelled by rejection.", succeeded: false))
        }

        return await withCheckedContinuation { continuation in
            self.rejectContinuation = continuation
            self.pendingRejectTarget = request
            self.pendingRejectReason = reason
            self.pendingRejectComments = comments
            self.isSubmittingReject = false
            self.rejectVerifyCount = 0
            self.pollCount = 0
            self.hasOpenedIncoming = false

            self.timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard !Task.isCancelled, self.rejectContinuation != nil else { return }
                self.webView.stopLoading()
                self.finishReject(QRZRejectResult(
                    succeeded: false,
                    message: "QRZ rejection timed out. Check your QRZ login session and connection."
                ))
            }

            QRZSessionStore.restoreToWebKit { [weak self] in
                guard let self else { return }
                // If webView is already on logbook.qrz.com, inspect immediately
                if let currentURL = self.webView.url, currentURL.host?.contains("qrz.com") == true {
                    self.inspectPageForReject()
                } else {
                    guard let url = URL(string: "https://logbook.qrz.com/logbook") else {
                        self.finishReject(QRZRejectResult(succeeded: false, message: "Invalid QRZ Logbook URL."))
                        return
                    }
                    self.webView.load(QRZWebKitSession.browserLikeRequest(url: url, timeoutInterval: 30))
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            if self.rejectContinuation != nil {
                self.inspectPageForReject()
            } else {
                self.inspectPage()
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            if self.rejectContinuation != nil {
                self.finishReject(QRZRejectResult(succeeded: false, message: "QRZ Incoming navigation failed: \(error.localizedDescription)"))
            } else {
                self.finish(QRZIncomingFetchResult(requests: [], message: "QRZ Incoming navigation failed: \(error.localizedDescription)", succeeded: false))
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            if self.rejectContinuation != nil {
                self.finishReject(QRZRejectResult(succeeded: false, message: "QRZ Incoming navigation failed: \(error.localizedDescription)"))
            } else {
                self.finish(QRZIncomingFetchResult(requests: [], message: "QRZ Incoming navigation failed: \(error.localizedDescription)", succeeded: false))
            }
        }
    }

    private func inspectPage() {
        guard continuation != nil else { return }
        webView.evaluateJavaScript(Self.navigationScript(shouldOpenRequests: !hasOpenedIncoming)) { [weak self] result, error in
            guard let self, self.continuation != nil else { return }
            if let error {
                self.finish(QRZIncomingFetchResult(requests: [], message: "Unable to inspect QRZ Incoming: \(error.localizedDescription)", succeeded: false))
                return
            }
            let payload = result as? [String: Any] ?? [:]
            switch payload["action"] as? String ?? "" {
            case "incoming-ready":
                self.readRequests()
            case "open-incoming":
                self.hasOpenedIncoming = true
                self.poll(after: 0.8)
            case "login-required":
                self.finish(QRZIncomingFetchResult(
                    requests: [],
                    message: "QRZ Login is required. Open QRZ Login, finish any MFA step, then refresh Incoming Requests.",
                    succeeded: false
                ))
            default:
                self.poll(after: 0.5)
            }
        }
    }

    private func inspectPageForReject() {
        guard rejectContinuation != nil else { return }

        // If we already triggered form submission, verify whether the request has been removed
        if isSubmittingReject {
            verifyRejection()
            return
        }

        webView.evaluateJavaScript(Self.navigationScript(shouldOpenRequests: !hasOpenedIncoming)) { [weak self] result, error in
            guard let self, self.rejectContinuation != nil else { return }
            if let error {
                self.finishReject(QRZRejectResult(succeeded: false, message: "Unable to inspect QRZ Incoming: \(error.localizedDescription)"))
                return
            }
            let payload = result as? [String: Any] ?? [:]
            switch payload["action"] as? String ?? "" {
            case "incoming-ready":
                self.executeReject()
            case "open-incoming":
                self.hasOpenedIncoming = true
                self.pollReject(after: 0.8)
            case "login-required":
                self.finishReject(QRZRejectResult(
                    succeeded: false,
                    message: "QRZ Login is required. Open QRZ Login, complete login, then retry rejection."
                ))
            default:
                self.pollReject(after: 0.5)
            }
        }
    }

    private func poll(after delay: TimeInterval) {
        pollCount += 1
        guard pollCount <= 50 else {
            finish(QRZIncomingFetchResult(requests: [], message: "QRZ Incoming did not finish loading. Open QRZ Login once, then retry.", succeeded: false))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.inspectPage()
        }
    }

    private func pollReject(after delay: TimeInterval) {
        pollCount += 1
        guard pollCount <= 50 else {
            finishReject(QRZRejectResult(succeeded: false, message: "QRZ Incoming did not finish loading. Open QRZ Login once, then retry."))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.inspectPageForReject()
        }
    }

    private func executeReject() {
        guard let target = pendingRejectTarget else {
            finishReject(QRZRejectResult(succeeded: false, message: "No target request specified for rejection."))
            return
        }

        let script = Self.buildRejectScript(
            qsoID: target.qsoID,
            callsign: target.callsign,
            qsoDate: target.qsoDate,
            reason: pendingRejectReason,
            comments: pendingRejectComments
        )

        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, self.rejectContinuation != nil else { return }
            if let error {
                self.finishReject(QRZRejectResult(succeeded: false, message: "Failed to execute QRZ rejection: \(error.localizedDescription)"))
                return
            }
            let payload = result as? [String: Any] ?? [:]
            let action = payload["action"] as? String ?? ""

            if action == "submitted" {
                self.isSubmittingReject = true
                // Check if page reloads or update happens in-place
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.verifyRejection()
                }
            } else if action == "not-found" {
                let msg = payload["message"] as? String ?? "Request not found on QRZ page."
                self.finishReject(QRZRejectResult(succeeded: false, message: msg))
            } else {
                let msg = payload["message"] as? String ?? "Unexpected response while submitting rejection."
                self.finishReject(QRZRejectResult(succeeded: false, message: msg))
            }
        }
    }

    private func verifyRejection() {
        guard let target = pendingRejectTarget, rejectContinuation != nil else { return }
        rejectVerifyCount += 1

        let script = Self.buildVerifyScript(qsoID: target.qsoID, callsign: target.callsign)
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self, self.rejectContinuation != nil else { return }
            if let error {
                if self.rejectVerifyCount <= 5 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        self?.verifyRejection()
                    }
                } else {
                    self.finishReject(QRZRejectResult(succeeded: false, message: "Verification error: \(error.localizedDescription)"))
                }
                return
            }
            let payload = result as? [String: Any] ?? [:]
            let verified = payload["verified"] as? Bool ?? false

            if verified {
                self.finishReject(QRZRejectResult(
                    succeeded: true,
                    message: "Successfully rejected confirmation request from \(target.callsign) on QRZ.com."
                ))
            } else if self.rejectVerifyCount <= 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.verifyRejection()
                }
            } else {
                self.finishReject(QRZRejectResult(
                    succeeded: false,
                    message: "The request for \(target.callsign) is still showing in your QRZ Incoming list."
                ))
            }
        }
    }

    private func readRequests() {
        webView.evaluateJavaScript(Self.parseScript) { [weak self] result, error in
            guard let self, self.continuation != nil else { return }
            if let error {
                self.finish(QRZIncomingFetchResult(requests: [], message: "QRZ Incoming could not be parsed: \(error.localizedDescription)", succeeded: false))
                return
            }
            let payload = result as? [String: Any] ?? [:]
            let rows = payload["rows"] as? [[String: Any]] ?? []
            let requests = rows.compactMap { row -> QRZIncomingConfirmation? in
                let call = (row["callsign"] as? String ?? "").uppercased()
                guard !call.isEmpty else { return nil }
                return QRZIncomingConfirmation(
                    callsign: call,
                    qsoDate: row["qsoDate"] as? String ?? "",
                    requestedAt: row["requestedAt"] as? String ?? "",
                    rawSummary: row["summary"] as? String ?? "",
                    qsoID: row["qsoID"] as? String ?? ""
                )
            }
            let unique = Dictionary(grouping: requests, by: \.id).compactMap { $0.value.first }
                .sorted { $0.requestedAt > $1.requestedAt }
            self.finish(QRZIncomingFetchResult(
                requests: unique,
                message: unique.isEmpty
                    ? "QRZ Incoming is current; no confirmation requests were returned."
                    : "Loaded \(unique.count) QRZ Incoming confirmation request(s).",
                succeeded: true
            ))
        }
    }

    private func finish(_ result: QRZIncomingFetchResult) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pollCount = 0
        hasOpenedIncoming = false
        let active = continuation
        continuation = nil
        active?.resume(returning: result)
    }

    private func finishReject(_ result: QRZRejectResult) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pollCount = 0
        hasOpenedIncoming = false
        isSubmittingReject = false
        rejectVerifyCount = 0
        pendingRejectTarget = nil
        pendingRejectReason = ""
        pendingRejectComments = ""
        let active = rejectContinuation
        rejectContinuation = nil
        active?.resume(returning: result)
    }

    private static func navigationScript(shouldOpenRequests: Bool) -> String {
        let shouldOpen = shouldOpenRequests ? "true" : "false"
        return #"""
    (function() {
        function visible(el) {
            if (!el) return false;
            var rect = el.getBoundingClientRect();
            return rect.width > 1 && rect.height > 1;
        }
        var body = (document.body && (document.body.innerText || document.body.textContent) || "").replace(/\s+/g, " ");
        if (Array.from(document.querySelectorAll("input[type=password], input[name=password], #password")).some(visible)) {
            return { action: "login-required" };
        }
        var requestTableReady = Array.from(document.querySelectorAll("table")).some(function(table) {
            var heading = (table.innerText || table.textContent || "").replace(/\s+/g, " ");
            return /Request Received/i.test(heading) && /QSO Date/i.test(heading) && /Callsign/i.test(heading);
        });
        var emptyRequestsReady = /Confirmation Requests/i.test(body)
            && /(?:no|0) (?:incoming |confirmation )?requests/i.test(body);
        if (requestTableReady || emptyRequestsReady) {
            return { action: "incoming-ready" };
        }
        if (\#(shouldOpen) && typeof lb_go === "function") {
            lb_go("requests", "");
            return { action: "open-incoming" };
        }
        if (\#(shouldOpen)) {
            var incomingLink = Array.from(document.querySelectorAll("[onclick], a, button")).find(function(el) {
                var handler = el.getAttribute("onclick") || "";
                return /lb_go\s*\(\s*['\"]requests['\"]/i.test(handler) || /^incoming$/i.test((el.innerText || "").trim());
            });
            if (incomingLink) {
                incomingLink.click();
                return { action: "open-incoming" };
            }
        }
        return { action: "waiting" };
    })();
    """#
    }

    private static let parseScript = #"""
    (function() {
        function text(el) { return (el && (el.innerText || el.textContent) || "").replace(/\s+/g, " ").trim(); }
        function firstDate(value) { var m = String(value).match(/\b\d{4}-\d{2}-\d{2}\b/); return m ? m[0] : ""; }
        function callFrom(value) {
            var matches = String(value).toUpperCase().match(/\b(?:[A-Z0-9]{1,4}\/)?[A-Z0-9]{1,3}\d[A-Z0-9/]{1,4}\b/g) || [];
            // QRZ renders the request as "MYCALL de THEIRCALL".
            return matches.length ? matches[matches.length - 1] : "";
        }
        var rows = [];
        var tables = Array.from(document.querySelectorAll("table"));
        var requestTables = tables.filter(function(table) {
            var heading = text(table.querySelector("tr"));
            return /Request Received/i.test(heading) && /QSO Date/i.test(heading) && /Callsign/i.test(heading);
        });
        (requestTables.length ? requestTables : tables).forEach(function(table) {
          var headings = Array.from(table.querySelectorAll("tr th, tr:first-child td")).map(text);
          var requestedIndex = headings.findIndex(function(value) { return /Request Received/i.test(value); });
          var qsoIndex = headings.findIndex(function(value) { return /QSO Date/i.test(value); });
          var callIndex = headings.findIndex(function(value) { return /^Callsign$/i.test(value); });
          Array.from(table.querySelectorAll("tr")).forEach(function(tr) {
            var cells = Array.from(tr.querySelectorAll("td")).map(text);
            var summary = cells.join(" | ");
            if (!summary || !/\b\d{4}-\d{2}-\d{2}\b/.test(summary)) return;
            var call = callFrom(callIndex >= 0 ? cells[callIndex] : summary);
            if (!call) return;
            var dates = summary.match(/\b\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2}:\d{2})?\b/g) || [];
            var qsoId = "";
            var rejButton = tr.querySelector("button[onclick*='lb_reject'], a[onclick*='lb_reject'], input[onclick*='lb_reject']");
            if (rejButton) {
                var m = (rejButton.getAttribute("onclick") || "").match(/lb_reject\s*\(\s*['\"]?(\d+)['\"]?\s*\)/);
                if (m) qsoId = m[1];
            }
            if (!qsoId) {
                var rcallInput = tr.querySelector("input[id^='rcall-']");
                if (rcallInput) {
                    var m2 = (rcallInput.id || "").match(/rcall-(\d+)/);
                    if (m2) qsoId = m2[1];
                }
            }
            rows.push({
                callsign: call,
                requestedAt: requestedIndex >= 0 ? (cells[requestedIndex] || "") : (dates[0] || ""),
                qsoDate: qsoIndex >= 0 ? firstDate(cells[qsoIndex] || "") : (dates.length > 1 ? firstDate(dates[1]) : firstDate(summary)),
                summary: summary,
                qsoID: qsoId
            });
          });
        });
        return { rows: rows };
    })();
    """#

    private static func buildRejectScript(
        qsoID: String,
        callsign: String,
        qsoDate: String,
        reason: String,
        comments: String
    ) -> String {
        let safeQsoID = qsoID.replacingOccurrences(of: "\"", with: "\\\"")
        let safeCall = callsign.uppercased().replacingOccurrences(of: "\"", with: "\\\"")
        let safeDate = qsoDate.replacingOccurrences(of: "\"", with: "\\\"")
        let safeReason = reason.replacingOccurrences(of: "\"", with: "\\\"")
        let safeComments = comments
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        return #"""
        (function() {
            var targetQso = "\#(safeQsoID)";
            var targetCall = "\#(safeCall)";
            var targetDate = "\#(safeDate)";
            var reasonVal = "\#(safeReason)";
            var commentsVal = "\#(safeComments)";

            // 1. Locate qsoId if not directly known
            if (!targetQso) {
                var rows = Array.from(document.querySelectorAll("table tr"));
                for (var i = 0; i < rows.length; i++) {
                    var tr = rows[i];
                    var rcall = tr.querySelector("input[id^='rcall-']");
                    var rdate = tr.querySelector("input[id^='rdate-']");
                    var callVal = rcall ? rcall.value.toUpperCase().trim() : "";
                    var dateVal = rdate ? rdate.value.trim() : "";
                    var text = (tr.innerText || tr.textContent || "").toUpperCase();

                    var matchCall = (callVal && callVal === targetCall) || text.indexOf(targetCall) >= 0;
                    var matchDate = (!targetDate) || (dateVal && dateVal === targetDate) || text.indexOf(targetDate) >= 0;

                    if (matchCall && matchDate) {
                        if (rcall) {
                            var m = (rcall.id || "").match(/rcall-(\d+)/);
                            if (m) { targetQso = m[1]; break; }
                        }
                        var btn = tr.querySelector("button[onclick*='lb_reject'], a[onclick*='lb_reject'], input[onclick*='lb_reject']");
                        if (btn) {
                            var m2 = (btn.getAttribute("onclick") || "").match(/lb_reject\s*\(\s*['\"]?(\d+)['\"]?\s*\)/);
                            if (m2) { targetQso = m2[1]; break; }
                        }
                    }
                }
            }

            if (!targetQso) {
                return { action: "not-found", message: "Could not locate confirmation request for " + targetCall + " on QRZ." };
            }

            // 2. Select reason radio
            var radio = document.querySelector('input[name=reason][value="' + reasonVal + '"]');
            if (radio) {
                radio.checked = true;
            } else {
                var firstRadio = document.querySelector('input[name=reason]');
                if (firstRadio) firstRadio.checked = true;
            }

            // 3. Set comments
            var commentsInput = document.getElementById('comments');
            if (commentsInput) {
                commentsInput.value = commentsVal;
            }

            // 4. Set rejid
            var rejidInput = document.getElementById('rejid');
            if (rejidInput) {
                rejidInput.value = targetQso;
            }

            // 5. Populate and submit #lbmenu form
            var form = document.getElementById('lbmenu');
            if (!form) {
                return { action: "error", message: "Logbook form #lbmenu was not found on QRZ page." };
            }

            var opInput = form.querySelector('input[name="op"]');
            if (opInput) opInput.value = 'reject';

            var rInput = form.querySelector('input[name="reason"]');
            if (rInput) rInput.value = reasonVal;

            var cInput = form.querySelector('input[name="comments"]');
            if (cInput) cInput.value = commentsVal;

            var qsoInput = form.querySelector('input[name="qso"]');
            if (qsoInput) {
                qsoInput.value = targetQso;
            } else {
                var newQso = document.createElement('input');
                newQso.type = 'hidden';
                newQso.name = 'qso';
                newQso.value = targetQso;
                form.appendChild(newQso);
            }

            if (typeof lb_reject2 === "function") {
                try {
                    lb_reject2();
                    return { action: "submitted", qsoID: targetQso };
                } catch(e) {}
            }

            form.submit();
            return { action: "submitted", qsoID: targetQso };
        })();
        """#
    }

    private static func buildVerifyScript(qsoID: String, callsign: String) -> String {
        let safeQso = qsoID.replacingOccurrences(of: "\"", with: "\\\"")
        let safeCall = callsign.uppercased().replacingOccurrences(of: "\"", with: "\\\"")

        return #"""
        (function() {
            var qso = "\#(safeQso)";
            var call = "\#(safeCall)";

            if (qso) {
                var el = document.getElementById('rcall-' + qso) || document.querySelector("button[onclick*='" + qso + "']");
                if (el) {
                    return { verified: false, message: "Request " + qso + " is still present on page." };
                }
            }

            return { verified: true };
        })();
        """#
    }
}

nonisolated struct ConfirmationReconciliationSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Date?
    var localTotal = 0
    var localConfirmed = 0
    var lotwLocal = 0
    var qrzLocal = 0
    var lotwReported = 0
    var qrzReported = 0
    var lotwMatched = 0
    var qrzMatched = 0
    var lotwUnmatched = 0
    var qrzUnmatched = 0
    var lotwMessage = "Run a sync to compare."
    var qrzMessage = "Run a sync to compare."

    static let empty = ConfirmationReconciliationSnapshot()
}

extension AppState {
    func loadQRZIncomingCache() {
        guard let data = UserDefaults.standard.data(forKey: qrzIncomingRequestsCacheKey),
              let cached = try? JSONDecoder().decode([QRZIncomingConfirmation].self, from: data) else { return }
        qrzIncomingRequests = cached
        if !cached.isEmpty {
            qrzIncomingStatus = "Showing \(cached.count) saved QRZ Incoming request(s). Refresh to check for changes."
        }
    }

    private func saveQRZIncomingCache() {
        guard let data = try? JSONEncoder().encode(qrzIncomingRequests) else { return }
        UserDefaults.standard.set(data, forKey: qrzIncomingRequestsCacheKey)
    }

    func fetchQRZIncomingRequests() {
        guard !isFetchingQRZIncoming else { return }
        isFetchingQRZIncoming = true
        qrzIncomingStatus = "Opening QRZ Logbook Incoming..."
        Task { @MainActor in
            let result = await QRZIncomingScraper.shared.fetchIncoming()
            self.isFetchingQRZIncoming = false
            if result.succeeded {
                self.qrzIncomingRequests = result.requests
                self.saveQRZIncomingCache()
                self.qrzIncomingStatus = result.message
            } else if self.qrzIncomingRequests.isEmpty {
                self.qrzIncomingStatus = result.message
            } else {
                self.qrzIncomingStatus = "\(result.message) Showing the last \(self.qrzIncomingRequests.count) saved request(s)."
            }
            self.appendLog("QRZ Incoming: \(result.message)")
            if result.requests.isEmpty && result.message.localizedCaseInsensitiveContains("required") {
                self.playActivitySound(.failure)
            } else {
                self.playActivitySound(.success)
            }
        }
    }

    func rejectQRZIncomingRequest(_ incoming: QRZIncomingConfirmation, reason: String, comments: String = "") {
        guard !isRejectingQRZIncoming else { return }
        isRejectingQRZIncoming = true
        rejectingQRZIncomingID = incoming.id
        qrzIncomingStatus = "Rejecting request from \(incoming.callsign) on QRZ.com..."
        appendLog("QRZ Incoming: rejecting confirmation request from \(incoming.callsign) (Reason: \(reason))...")

        Task { @MainActor in
            let result = await QRZIncomingScraper.shared.rejectIncoming(
                request: incoming,
                reason: reason,
                comments: comments
            )
            self.isRejectingQRZIncoming = false
            self.rejectingQRZIncomingID = nil

            if result.succeeded {
                self.qrzIncomingRequests.removeAll { $0.id == incoming.id }
                self.saveQRZIncomingCache()
                self.qrzIncomingStatus = "Rejected confirmation request from \(incoming.callsign) on QRZ.com."
                self.appendLog("QRZ Incoming: successfully rejected confirmation request from \(incoming.callsign) on QRZ.com.")
                self.playActivitySound(.success)
                self.fetchQRZIncomingRequests()
            } else {
                self.qrzIncomingStatus = "Failed to reject on QRZ.com: \(result.message)"
                self.appendLog("QRZ Incoming rejection error: \(result.message)")
                self.playActivitySound(.failure)
            }
        }
    }

    func hasLocalQSO(for incoming: QRZIncomingConfirmation) -> Bool {
        qsoRecords.contains { record in
            let sameCall = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == incoming.callsign
            guard sameCall else { return false }
            guard !incoming.qsoDate.isEmpty else { return true }
            return record["QSO_DATE"].replacingOccurrences(of: "-", with: "") == incoming.qsoDate.replacingOccurrences(of: "-", with: "")
        }
    }

    func draftIncomingQRZDetailsEmail(for incoming: QRZIncomingConfirmation) {
        let call = incoming.callsign
        guard incomingEmailLookupCallsign == nil else { return }

        let cachedEmail = qsoRecords.lazy
            .filter { $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == call }
            .map { $0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { address in
                let parts = address.split(separator: "@", omittingEmptySubsequences: false)
                return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
            }) ?? ""

        selectedEmailCallsign = call
        selectedEmailAddress = cachedEmail
        selectedEmailQSO = nil
        selectedEmailUnconfirmedQSOs = []
        selectedEmailTemplate = "QRZ Incoming Details"
        selectedEmailIncomingRequest = incoming
        incomingEmailDraftNotice = cachedEmail.isEmpty
            ? "Looking for a published address on QRZ and HAMQTH..."
            : "Using the saved address for \(call). Review the draft before sending."
        showIncomingEmailComposer = true

        guard cachedEmail.isEmpty else {
            appendLog("QRZ Incoming: prepared an editable details request for \(call) using its saved email address.")
            return
        }

        incomingEmailLookupCallsign = call
        Task { @MainActor in
            defer { self.incomingEmailLookupCallsign = nil }
            let contact = await self.fetchContactInfo(for: call, allowQRZWebKitFallback: true)

            guard self.showIncomingEmailComposer,
                  self.selectedEmailIncomingRequest?.id == incoming.id else {
                return
            }

            if let email = contact.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                let hadManualAddress = !self.selectedEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !hadManualAddress {
                    self.selectedEmailAddress = email
                }
                self.incomingEmailDraftNotice = hadManualAddress
                    ? "A published address was found, but the address you entered manually was kept. Review it before sending."
                    : "Published address found for \(call). Review the recipient and message before sending."
                self.appendLog("QRZ Incoming: prepared an editable details request for \(call); recipient resolved from QRZ/HAMQTH.")
            } else {
                let hasManualAddress = !self.selectedEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                self.incomingEmailDraftNotice = hasManualAddress
                    ? "No published address was found. The address you entered manually was kept for your review."
                    : "No published email was found for \(call). Enter an address manually or open the QRZ profile."
                self.appendLog(hasManualAddress
                    ? "QRZ Incoming: no published email was found for \(call); keeping the manually entered recipient."
                    : "QRZ Incoming: no published email was found for \(call); the editable draft remains open for manual addressing.")
            }
        }
    }

    func updateConfirmationReconciliation(with summary: ConfirmationSyncSummary) {
        let lotwLocal = qsoRecords.filter { $0["LOTW_QSL_RCVD"].uppercased() == "Y" }.count
        let qrzLocal = qsoRecords.filter {
            $0["QRZLOG_QSL_RCVD"].uppercased() == "Y" || $0["QRZCOM_QSL_RCVD"].uppercased() == "Y"
        }.count
        confirmationReconciliation = ConfirmationReconciliationSnapshot(
            generatedAt: Date(),
            localTotal: qsoRecords.count,
            localConfirmed: totalConfirmedCount,
            lotwLocal: lotwLocal,
            qrzLocal: qrzLocal,
            lotwReported: summary.lotwReported,
            qrzReported: summary.qrzReported,
            lotwMatched: summary.lotwMatched,
            qrzMatched: summary.qrzMatched,
            lotwUnmatched: summary.lotwUnmatched,
            qrzUnmatched: summary.qrzUnmatched,
            lotwMessage: summary.lotwMessage,
            qrzMessage: summary.qrzMessage
        )
    }
}

struct QRZIncomingRequestsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var requestToReject: QRZIncomingConfirmation?
    @State private var showRejectSheet = false

    private var outstanding: [QRZIncomingConfirmation] {
        appState.qrzIncomingRequests.filter { !appState.hasLocalQSO(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("QRZ Incoming Confirmation Requests", systemImage: "tray.and.arrow.down.fill")
                        .font(.title3.weight(.bold))
                    Text("Requests that do not match a local QSO can be followed up by email for the missing contact details or rejected directly on QRZ.com.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appState.fetchQRZIncomingRequests()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isFetchingQRZIncoming || appState.isRejectingQRZIncoming)
            }

            HStack(spacing: 10) {
                incomingSummary(title: "Returned", value: appState.qrzIncomingRequests.count, color: .blue, icon: "tray.full.fill")
                incomingSummary(title: "Need details", value: outstanding.count, color: .orange, icon: "envelope.badge.fill")
                incomingSummary(
                    title: "Matched locally",
                    value: appState.qrzIncomingRequests.count - outstanding.count,
                    color: .green,
                    icon: "checkmark.circle.fill"
                )
            }

            if appState.isRejectingQRZIncoming {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(appState.qrzIncomingStatus)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            if appState.isFetchingQRZIncoming {
                ProgressView(appState.qrzIncomingStatus)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if appState.qrzIncomingRequests.isEmpty {
                ContentUnavailableView("No Incoming Requests Loaded", systemImage: "tray", description: Text(appState.qrzIncomingStatus))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                List(appState.qrzIncomingRequests) { request in
                    HStack(spacing: 12) {
                        Image(systemName: appState.hasLocalQSO(for: request) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(appState.hasLocalQSO(for: request) ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(request.callsign).font(.headline.monospaced())
                            Text("QSO \(request.qsoDate.isEmpty ? "date not reported" : request.qsoDate) · requested \(request.requestedAt.isEmpty ? "unknown" : request.requestedAt)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(appState.hasLocalQSO(for: request) ? "A matching local QSO exists." : "No local QSO matched. Request the QSO details before adding anything.")
                                .font(.caption)
                                .foregroundStyle(appState.hasLocalQSO(for: request) ? .green : .orange)
                        }
                        Spacer()
                        if !appState.hasLocalQSO(for: request) {
                            Button {
                                appState.draftIncomingQRZDetailsEmail(for: request)
                            } label: {
                                if appState.incomingEmailLookupCallsign == request.callsign {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Compose Email", systemImage: "square.and.pencil")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.incomingEmailLookupCallsign != nil)
                            .help("Prepare an editable email requesting the missing QSO details")
                        }

                        Button(role: .destructive) {
                            requestToReject = request
                            showRejectSheet = true
                        } label: {
                            if appState.rejectingQRZIncomingID == request.id {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Reject", systemImage: "xmark.circle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(appState.isRejectingQRZIncoming || appState.isFetchingQRZIncoming)
                        .help("Reject confirmation request from \(request.callsign) on QRZ.com")

                        Button {
                            guard let url = URL(string: "https://www.qrz.com/db/\(request.callsign)") else { return }
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .buttonStyle(.bordered)
                        .help("Open \(request.callsign) on QRZ.com")
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }

            HStack {
                Text("\(outstanding.count) request(s) need a local-log review")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(20)
        .frame(
            minWidth: 760,
            idealWidth: 980,
            maxWidth: .infinity,
            minHeight: 500,
            idealHeight: 680,
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 760, minHeight: 500)
        .onAppear {
            if appState.qrzIncomingRequests.isEmpty { appState.fetchQRZIncomingRequests() }
        }
        .sheet(isPresented: $appState.showIncomingEmailComposer) {
            EmailComposerView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showRejectSheet) {
            if let req = requestToReject {
                QRZRejectRequestSheet(request: req) { reason, comments in
                    appState.rejectQRZIncomingRequest(req, reason: reason, comments: comments)
                }
            }
        }
    }

    private func incomingSummary(title: String, value: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted())
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.2)))
    }
}

struct QRZRejectRequestSheet: View {
    let request: QRZIncomingConfirmation
    let onConfirm: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason = "Not in my logbook"
    @State private var comments = ""

    private let reasons: [(value: String, title: String, subtitle: String)] = [
        ("Not in my logbook", "Not in my logbook", "The contact is not recorded in your station log."),
        ("Incorrect data", "Incorrect data", "Date, time, frequency, or mode does not match."),
        ("Other", "Other", "Other log discrepancy or duplicate request.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reject Confirmation Request")
                        .font(.title3.weight(.bold))
                    Text("Station: \(request.callsign) · QSO Date: \(request.qsoDate.isEmpty ? "Unknown" : request.qsoDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("This action will submit the rejection directly to QRZ.com using your active logbook session.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Rejection Reason on QRZ.com:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(reasons, id: \.value) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selectedReason == item.value ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selectedReason == item.value ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.body.weight(selectedReason == item.value ? .semibold : .regular))
                            Text(item.subtitle).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedReason = item.value }
                    .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Comments to requestor (optional):")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Enter note to send to \(request.callsign)...", text: $comments)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button(role: .destructive) {
                    dismiss()
                    onConfirm(selectedReason, comments)
                } label: {
                    Label("Reject on QRZ.com", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

struct ConfirmationReconciliationView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showFullSyncPrompt = false

    private var snapshot: ConfirmationReconciliationSnapshot { appState.confirmationReconciliation }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Confirmation Reconciliation", systemImage: "checklist")
                        .font(.title3.weight(.bold))
                    Text("Provider totals, local flags, and unmatched cloud records are kept separate so differences can be investigated.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Full History", systemImage: "arrow.triangle.2.circlepath") { showFullSyncPrompt = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isSyncingAPI || appState.qsoRecords.isEmpty)
            }

            HStack(spacing: 12) {
                reconciliationMetric("Local QSOs", snapshot.localTotal.formatted(), .blue)
                reconciliationMetric("Confirmed", snapshot.localConfirmed.formatted(), .green)
                reconciliationMetric("LoTW flags", snapshot.lotwLocal.formatted(), .orange)
                reconciliationMetric("QRZ flags", snapshot.qrzLocal.formatted(), .purple)
            }

            Grid(horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Provider").fontWeight(.semibold)
                    Text("Downloaded").fontWeight(.semibold)
                    Text("Reported total").fontWeight(.semibold)
                    Text("Matched").fontWeight(.semibold)
                    Text("Unmatched").fontWeight(.semibold)
                }
                Divider().gridCellColumns(5)
                providerRow("LoTW", snapshot.lotwMessage, snapshot.lotwReported, snapshot.lotwMatched, snapshot.lotwUnmatched, .orange)
                providerRow("QRZ Logbook", snapshot.qrzMessage, snapshot.qrzReported, snapshot.qrzMatched, snapshot.qrzUnmatched, .blue)
            }
            .font(.subheadline)
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Text("A full-history sync paginates both providers from the beginning, imports safe confirmed contacts that are absent locally, and leaves ambiguous records visible as unmatched instead of guessing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            HStack {
                if let date = snapshot.generatedAt {
                    Text("Last comparison: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(20)
        .frame(
            minWidth: 720,
            idealWidth: 900,
            maxWidth: .infinity,
            minHeight: 440,
            idealHeight: 600,
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 720, minHeight: 440)
        .confirmationDialog("Rebuild complete confirmation history?", isPresented: $showFullSyncPrompt, titleVisibility: .visible) {
            Button("Download Full LoTW & QRZ History") {
                appState.syncConfirmations(forceFullSync: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("YAAM will start at the beginning of both confirmation histories and then refresh this comparison.")
        }
    }

    private func reconciliationMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(color)
            Text(value).font(.title3.monospacedDigit().weight(.bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25)))
    }

    @ViewBuilder
    private func providerRow(_ provider: String, _ detail: String, _ reported: Int, _ matched: Int, _ unmatched: Int, _ color: Color) -> some View {
        GridRow {
            VStack(alignment: .leading) {
                Text(provider).fontWeight(.semibold)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Text("-")
            Text(reported == 0 ? "Not reported" : reported.formatted())
            Text(matched.formatted()).foregroundStyle(color)
            Text(unmatched.formatted()).foregroundStyle(unmatched == 0 ? Color.secondary : Color.orange)
        }
    }
}

struct LogAssistantView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("logAssistantEndpoint") private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("logAssistantModel") private var model = "gpt-5-mini"
    @State private var prompt = ""
    @State private var response = "Ask about the active log, or use one of the suggested actions below."
    @State private var pendingAction: LogAssistantAction?
    @State private var isThinking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Log Assistant", systemImage: "bubble.left.and.text.bubble.right.fill")
                        .font(.title3.weight(.bold))
                    Text("Local actions are always shown before they run. Add an OpenAI-compatible account in Settings for explanatory chat.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                SettingsLink { Label("Configure", systemImage: "gearshape") }
            }

            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 90, maxHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))

            HStack {
                Button("Understand", systemImage: "sparkles") {
                    understandPrompt()
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if isThinking { ProgressView().controlSize(.small) }
                Button("Show unconfirmed") { prompt = "Show unconfirmed QSOs" }
                Button("Compare confirmations") { prompt = "Compare LoTW and QRZ confirmations" }
                Button("Open contest calendar") { prompt = "Open contest calendar" }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(response).fixedSize(horizontal: false, vertical: true)
                if let action = pendingAction {
                    Button(action.buttonTitle, systemImage: action.icon) {
                        action.execute(appState: appState)
                        pendingAction = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Spacer()
            HStack { Spacer(); Button("Done") { dismiss() } }
        }
        .padding(20)
        .frame(
            minWidth: 680,
            idealWidth: 860,
            maxWidth: .infinity,
            minHeight: 440,
            idealHeight: 600,
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 680, minHeight: 440)
    }

    private func understandPrompt() {
        let outcome = LogAssistantAction.interpret(prompt: prompt, appState: appState)
        pendingAction = outcome.action
        let apiKey = CredentialVault.valueIfAvailableWithoutPrompt(for: .logAssistantAPIKey)
        guard !apiKey.isEmpty else {
            response = outcome.message
            return
        }

        isThinking = true
        response = "Preparing an explanation from your configured assistant..."
        let context = """
        Active station: \(appState.currentStationCallsign)
        Total QSOs: \(appState.qsoRecords.count)
        Confirmed QSOs: \(appState.qsoRecords.filter(\.isConfirmed).count)
        LoTW confirmations in local log: \(appState.confirmationReconciliation.lotwLocal)
        QRZ confirmations in local log: \(appState.confirmationReconciliation.qrzLocal)
        QRZ Incoming requests loaded: \(appState.qrzIncomingRequests.count)
        Contest calendar entries: \(appState.contestCalendarEntries.count)
        DXpeditions loaded: \(appState.dxpeditionEntries.count)
        """
        Task {
            do {
                let explanation = try await LogAssistantClient.ask(
                    prompt: prompt,
                    context: context,
                    endpoint: endpoint,
                    model: model,
                    apiKey: apiKey
                )
                await MainActor.run {
                    self.response = outcome.message + "\n\nAssistant: " + explanation
                    self.isThinking = false
                }
            } catch {
                await MainActor.run {
                    self.response = outcome.message + "\n\nThe configured assistant was unavailable: \(error.localizedDescription)"
                    self.isThinking = false
                }
            }
        }
    }
}

nonisolated enum LogAssistantClient {
    private struct ChatRequest: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    static func ask(prompt: String, context: String, endpoint: String, model: String, apiKey: String) async throws -> String {
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https" else {
            throw URLError(.badURL)
        }
        let system = "You are YAAM's ham-radio log assistant. Be concise. You receive only aggregate log context. Do not claim an action happened; YAAM requires explicit confirmation for every action."
        let requestBody = ChatRequest(
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: "Context:\n\(context)\n\nRequest:\n\(prompt)")
            ],
            temperature: 0.2
        )
        var request = URLRequest(url: url, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let answer = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No assistant response was returned."
        return String(answer.prefix(1_600))
    }
}

private enum LogAssistantAction {
    case unconfirmed, confirmationReport, syncConfirmations, calendar, incoming

    var buttonTitle: String {
        switch self {
        case .unconfirmed: return "Apply confirmation filter"
        case .confirmationReport: return "Open reconciliation"
        case .syncConfirmations: return "Sync confirmations"
        case .calendar: return "Open Calendar / 6m"
        case .incoming: return "Open QRZ Incoming"
        }
    }

    var icon: String {
        switch self {
        case .unconfirmed: return "line.3.horizontal.decrease.circle"
        case .confirmationReport: return "checklist"
        case .syncConfirmations: return "arrow.clockwise.icloud"
        case .calendar: return "calendar"
        case .incoming: return "tray.and.arrow.down"
        }
    }

    static func interpret(prompt: String, appState: AppState) -> (message: String, action: LogAssistantAction?) {
        let normalized = prompt.lowercased()
        if normalized.contains("unconfirmed") || prompt.contains("تایید نشده") {
            let count = appState.qsoRecords.filter { !$0.isConfirmed }.count
            return ("There are \(count.formatted()) unconfirmed QSOs in the active log. I can apply the confirmation filter.", .unconfirmed)
        }
        if normalized.contains("incoming") || prompt.contains("ورودی") {
            return ("I can open QRZ Incoming and identify requests that do not have a local QSO yet.", .incoming)
        }
        if normalized.contains("sync") || prompt.contains("همگام") {
            return ("I can download the latest LoTW and QRZ confirmations. A full-history rebuild remains a separate explicit action.", .syncConfirmations)
        }
        if normalized.contains("contest") || prompt.contains("مسابق") || normalized.contains("calendar") {
            return ("I can open the contest calendar and the 6m propagation workspace.", .calendar)
        }
        if normalized.contains("lotw") || normalized.contains("qrz") || prompt.contains("تایید") {
            return ("I can open the provider reconciliation report, which separates downloaded, matched, and unmatched records.", .confirmationReport)
        }
        return ("I can help with confirmations, QRZ Incoming, the contest calendar, and active-log confirmation filtering. Try a direct request such as ‘show unconfirmed QSOs’.", nil)
    }

    func execute(appState: AppState) {
        switch self {
        case .unconfirmed:
            appState.filterCriteria.useConfirmation = true
            appState.filterCriteria.confirmationType = "Any Method"
            appState.filterCriteria.confirmationState = "Unconfirmed (N/Blank)"
        case .confirmationReport:
            appState.showConfirmationReconciliationSheet = true
        case .syncConfirmations:
            appState.syncConfirmations()
        case .calendar:
            appState.selectedTab = 5
            appState.operatorDeskSection = 9
        case .incoming:
            appState.showQRZIncomingSheet = true
        }
    }
}
