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

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                Text("QRZ.com Authenticator")
                    .font(.headline)

                Spacer()

                Button("Done / Save Session") {
                    appState.appendLog("QRZ session save requested from authenticator.")
                    statusText = "Checking QRZ session cookies..."
                    saveRequestID += 1
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("Cancel") {
                    dismiss()
                }
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            QRZWebViewStore(statusText: $statusText, saveRequestID: saveRequestID) { cookies in
                appState.saveQRZSessionCookies(cookies)
                appState.appendLog("✅ QRZ Session Cookie captured successfully via WKWebView!")
                appState.showNativeAlert(
                    title: "QRZ Authenticated! 🔐",
                    message: "Session cookie saved successfully. You can now use Enrich Data to fetch hidden emails."
                )
                dismiss()
            }

            Divider()

            HStack {
                ProgressView()
                    .scaleEffect(0.5)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 650)
    }
}

// MARK: - WKWebView Representable with Automatic Cookie Extractor
struct QRZWebViewStore: NSViewRepresentable {
    @Binding var statusText: String
    let saveRequestID: Int
    var onCookieCaptured: ([HTTPCookie]) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = QRZWebKitSession.browserLikeConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = QRZWebKitSession.userAgent
        webView.navigationDelegate = context.coordinator

        context.coordinator.loadLoginPage(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard context.coordinator.lastSaveRequestID != saveRequestID else { return }
        context.coordinator.lastSaveRequestID = saveRequestID
        context.coordinator.captureCookies(from: nsView, manual: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: QRZWebViewStore
        var lastSaveRequestID = 0
        private var loginRetryCount = 0

        init(_ parent: QRZWebViewStore) {
            self.parent = parent
        }

        func loadLoginPage(in webView: WKWebView) {
            guard let url = URL(string: "https://www.qrz.com/login") else { return }
            QRZSessionStore.restoreToWebKit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                webView.load(QRZWebKitSession.browserLikeRequest(url: url))
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
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
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { cookies in
                var cookiePairs: [String] = []
                var hasSessionCookie = false

                for cookie in cookies where cookie.domain.contains("qrz.com") {
                    cookiePairs.append("\(cookie.name)=\(cookie.value)")
                    let cookieName = cookie.name.lowercased()
                    if cookieName == "qrz_session" || cookieName.contains("session") || cookieName.contains("remember") || cookieName.contains("login") {
                        hasSessionCookie = true
                    }
                }

                DispatchQueue.main.async {
                    if hasSessionCookie && !cookiePairs.isEmpty {
                        self.parent.statusText = "Login detected! Capturing session cookie..."
                        self.parent.onCookieCaptured(cookies.filter { $0.domain.contains("qrz.com") })
                    } else if manual {
                        self.parent.statusText = "No QRZ login session cookie found yet. Please sign in first."
                    } else {
                        self.parent.statusText = "Navigated to: \(webView.url?.absoluteString ?? "")"
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
            let nsError = error as NSError
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
