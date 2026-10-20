//
//  QRZLoginView.swift
//  YAAM
//

import SwiftUI
import WebKit

// MARK: - Native WebKit QRZ Login Window
struct QRZLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var statusText: String = "Please log in to QRZ.com (supports MFA/2FA)..."
    @State private var saveRequestID = 0
    @State private var reloadRequestID = 0
    @State private var authState = QRZAuthenticationState.signIn

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(authState == .authenticated ? Color.green : Color.accentColor)
                Text("QRZ.com Authenticator")
                    .font(.headline)

                Spacer()

                Button("Verify & Save") {
                    appState.appendLog("QRZ session save requested from authenticator.")
                    statusText = "Checking the authenticated QRZ page…"
                    authState = .loading
                    saveRequestID += 1
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)

                Button("Retry", systemImage: "arrow.clockwise") {
                    reloadRequestID += 1; authState = .loading
                }
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            QRZWebViewStore(statusText: $statusText, authState: $authState, saveRequestID: saveRequestID, reloadRequestID: reloadRequestID) { cookies in
                guard appState.saveQRZSessionCookies(cookies) else {
                    authState = .failed
                    statusText = "The authenticated session could not be saved. Unlock the credential vault, then Verify & Save again."
                    return false
                }
                appState.appendLog("QRZ authenticated page verified; session saved.")
                dismiss()
                return true
            }

            Divider()

            HStack(alignment: .top, spacing: 10) {
                if authState == .loading { ProgressView().controlSize(.small) }
                else { Image(systemName: authState.symbol).foregroundStyle(authState == .failed ? Color.orange : Color.accentColor) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(authState.title).font(.caption.weight(.semibold))
                    Text(statusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(
            minWidth: 540,
            idealWidth: 760,
            maxWidth: .infinity,
            minHeight: 520,
            idealHeight: 760,
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 540, minHeight: 520)
    }
}

// MARK: - WKWebView Representable with Automatic Cookie Extractor
struct QRZWebViewStore: NSViewRepresentable {
    @Binding var statusText: String
    @Binding var authState: QRZAuthenticationState
    let saveRequestID: Int
    let reloadRequestID: Int
    var onCookieCaptured: ([HTTPCookie]) -> Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = QRZWebKitSession.browserLikeConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = QRZWebKitSession.userAgent
        webView.navigationDelegate = context.coordinator

        context.coordinator.loadLoginPage(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastReloadRequestID != reloadRequestID {
            context.coordinator.lastReloadRequestID = reloadRequestID
            context.coordinator.loadLoginPage(in: nsView)
        }
        guard context.coordinator.lastSaveRequestID != saveRequestID else { return }
        context.coordinator.lastSaveRequestID = saveRequestID
        context.coordinator.captureCookies(from: nsView, manual: true)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.attempt.cancel()
        nsView.stopLoading(); nsView.navigationDelegate = nil
    }
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: QRZWebViewStore
        var lastSaveRequestID = 0
        var lastReloadRequestID = 0
        var attempt = QRZAuthenticationAttempt()
        private var loginRetryCount = 0

        init(_ parent: QRZWebViewStore) {
            self.parent = parent
        }

        func loadLoginPage(in webView: WKWebView) {
            guard let url = URL(string: "https://www.qrz.com/login") else { return }
            QRZSessionStore.restoreToWebKit { [weak self, weak webView] in
                guard let self, !self.attempt.cancelled, let webView else { return }
                webView.load(QRZWebKitSession.browserLikeRequest(url: url))
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            attempt.navigate()
            parent.authState = .loading
            DispatchQueue.main.async {
                self.parent.statusText = "Loading QRZ.com login page..."
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            loginRetryCount = 0
            DispatchQueue.main.async {
                self.parent.statusText = "QRZ page is rendering..."
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loginRetryCount = 0
            captureCookies(from: webView, manual: false)
        }

        func captureCookies(from webView: WKWebView, manual: Bool) {
            guard attempt.canCapture(ticket: attempt.generation) else { return }
            let ticket = attempt.generation, pageURL = webView.url
            webView.evaluateJavaScript(QRZAuthenticationPolicy.inspectionScript) { [weak self, weak webView] value, error in
                guard let self, let webView, self.attempt.canCapture(ticket: ticket), webView.url == pageURL else { return }
                guard error == nil, let evidence = value as? [String: Bool] else {
                    self.parent.authState = .failed
                    self.parent.statusText = "Could not verify this page. Complete QRZ sign-in and select Verify & Save, or retry."
                    return
                }
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self, weak webView] cookies in
                    guard let self, let webView, self.attempt.canCapture(ticket: ticket), webView.url == pageURL else { return }
                    let qrzCookies = cookies.filter { QRZAuthenticationPolicy.trustedHost($0.domain) && ($0.expiresDate ?? .distantFuture) > Date() }
                    let session = qrzCookies.contains {
                        let name = $0.name.lowercased()
                        return name.contains("session") || name.contains("remember") || name.contains("login")
                    }
                    let state = QRZAuthenticationPolicy.evaluate(url: pageURL, logout: evidence["logout"] == true,
                        loginForm: evidence["loginForm"] == true, challenge: evidence["challenge"] == true, sessionCookie: session)
                    self.parent.authState = state
                    if state == .authenticated {
                        self.parent.statusText = "Authenticated QRZ account verified. Saving its session…"
                        self.attempt.saved(self.parent.onCookieCaptured(qrzCookies))
                    } else {
                        self.parent.statusText = state == .challenge
                            ? "Complete MFA or the browser challenge here. This window stays open until the account is verified."
                            : "Continue signing in here, then select Verify & Save. A pre-login cookie is not proof of authentication."
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateFailureStatus(error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateFailureStatus(error, webView: webView)
        }

        private func updateFailureStatus(_ error: Error, webView: WKWebView? = nil) {
            guard !attempt.cancelled else { return }
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            parent.authState = .failed
            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorNetworkConnectionLost,
               loginRetryCount < 2,
               let webView {
                loginRetryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.parent.statusText = "QRZ connection dropped. Retrying login page..."
                    self.loadLoginPage(in: webView)
                }
                return
            }

            DispatchQueue.main.async {
                self.parent.statusText = "QRZ page load failed: \(error.localizedDescription)"
            }
        }
    }
}
