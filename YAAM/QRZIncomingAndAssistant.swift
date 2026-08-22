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

    init(callsign: String, qsoDate: String, requestedAt: String, rawSummary: String) {
        self.callsign = callsign
        self.qsoDate = qsoDate
        self.requestedAt = requestedAt
        self.rawSummary = rawSummary
        id = "\(callsign)|\(qsoDate)|\(requestedAt)|\(rawSummary)"
    }
}

nonisolated struct QRZIncomingFetchResult: Sendable {
    let requests: [QRZIncomingConfirmation]
    let message: String
    let succeeded: Bool
}

private let qrzIncomingRequestsCacheKey = "qrzIncomingRequests.v1"

// QRZ Logbook intentionally has no public API for confirmation requests. This
// small, session-bound reader only navigates the page the operator can open in a browser.
@MainActor
final class QRZIncomingScraper: NSObject, WKNavigationDelegate {
    static let shared = QRZIncomingScraper()

    private var webView: WKWebView!
    private var continuation: CheckedContinuation<QRZIncomingFetchResult, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pollCount = 0
    private var hasOpenedIncoming = false

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

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.inspectPage() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            self.finish(QRZIncomingFetchResult(requests: [], message: "QRZ Incoming navigation failed: \(error.localizedDescription)", succeeded: false))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            self.finish(QRZIncomingFetchResult(requests: [], message: "QRZ Incoming navigation failed: \(error.localizedDescription)", succeeded: false))
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
                    rawSummary: row["summary"] as? String ?? ""
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
            rows.push({
                callsign: call,
                requestedAt: requestedIndex >= 0 ? (cells[requestedIndex] || "") : (dates[0] || ""),
                qsoDate: qsoIndex >= 0 ? firstDate(cells[qsoIndex] || "") : (dates.length > 1 ? firstDate(dates[1]) : firstDate(summary)),
                summary: summary
            });
          });
        });
        return { rows: rows };
    })();
    """#
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
        incomingEmailLookupCallsign = call
        Task { @MainActor in
            defer { self.incomingEmailLookupCallsign = nil }
            let contact = await self.fetchContactInfo(for: call, allowQRZWebKitFallback: true)
            guard let email = contact.email, !email.isEmpty else {
                self.alertTitle = "No Email Address Published"
                self.alertMessage = "QRZ/HAMQTH did not return a published email for \(call). The request remains available in QRZ Incoming for manual review."
                self.showAlert = true
                return
            }
            self.selectedEmailCallsign = call
            self.selectedEmailAddress = email
            self.selectedEmailQSO = nil
            self.selectedEmailUnconfirmedQSOs = []
            self.selectedEmailTemplate = "QRZ Incoming Details"
            self.selectedEmailIncomingRequest = incoming
            self.showEmailComposer = true
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

    private var outstanding: [QRZIncomingConfirmation] {
        appState.qrzIncomingRequests.filter { !appState.hasLocalQSO(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("QRZ Incoming Confirmation Requests", systemImage: "tray.and.arrow.down.fill")
                        .font(.title3.weight(.bold))
                    Text("Requests that do not match a local QSO can be followed up by email for the missing contact details.")
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
                .disabled(appState.isFetchingQRZIncoming)
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
                                    Label("Email for Details", systemImage: "envelope.fill")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.incomingEmailLookupCallsign != nil)
                        }

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
        .frame(minWidth: 760, minHeight: 500)
        .onAppear {
            if appState.qrzIncomingRequests.isEmpty { appState.fetchQRZIncomingRequests() }
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
        .frame(width: 760, height: 470)
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
        .frame(width: 720, height: 480)
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
