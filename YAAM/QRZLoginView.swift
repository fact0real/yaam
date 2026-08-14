//
//  QRZLoginView.swift
//  YAAM
//

import SwiftUI
import WebKit

struct QRZLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var statusMessage: String = "Checking QRZ.com session status..."
    @State private var isLoggedIn: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Image(systemName: "shield.checkerboard")
                    .foregroundColor(.green)
                    .font(.title3)
                Text("QRZ.com Authenticator")
                    .font(.headline)

                Spacer()

                Button(action: finishLogin) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Done / Save Session")
                    }
                    .fontWeight(.bold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("Cancel") {
                    dismiss()
                }
                .padding(.leading, 6)
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            QRZWebViewRepresentable(
                statusMessage: $statusMessage,
                isLoggedIn: $isLoggedIn
            )

            Divider()

            HStack {
                if isLoggedIn {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                Text(statusMessage)
                    .font(.caption)
                    .fontWeight(isLoggedIn ? .bold : .regular)
                    .foregroundColor(isLoggedIn ? .green : .secondary)

                Spacer()

                Text("Once logged in, click 'Done / Save Session' above.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 820, height: 620)
    }

    private func finishLogin() {
        appState.appendLog("QRZ session saved to macOS WebKit persistent store.")
        appState.alertTitle = "QRZ Session Active"
        appState.alertMessage = "Your QRZ login session is saved. You can use Enrich Data to fetch emails."
        appState.showAlert = true
        dismiss()
    }
}

struct QRZWebViewRepresentable: NSViewRepresentable {
    @Binding var statusMessage: String
    @Binding var isLoggedIn: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = QRZWebKitSession.browserLikeConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = QRZWebKitSession.userAgent
        webView.navigationDelegate = context.coordinator
        context.coordinator.startStatusFallback()

        if let url = URL(string: "https://www.qrz.com/login") {
            let request = QRZWebKitSession.browserLikeRequest(url: url, timeoutInterval: 20)
            webView.load(request)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: QRZWebViewRepresentable
        private var statusTask: Task<Void, Never>?

        init(_ parent: QRZWebViewRepresentable) {
            self.parent = parent
        }

        func startStatusFallback() {
            statusTask?.cancel()
            statusTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 8_000_000_000)

                guard !Task.isCancelled, !parent.isLoggedIn else { return }
                parent.statusMessage = "QRZ loaded. If you see your account name, click Done / Save Session."
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            startStatusFallback()
            let jsCheck = """
            (function() {
                var currentUrl = window.location.href || "";
                var bodyText = document.body ? document.body.innerText : "";
                var hasLogout = bodyText.includes('Log Out') || bodyText.includes('Logout') || bodyText.includes('Sign Out');
                var hasLoginForm = document.querySelector('input[type="password"]') !== null ||
                                   document.querySelector('form[action*="login"]') !== null ||
                                   bodyText.includes('Sign in to QRZ');
                var hasUserMenu = document.querySelector('a[href*="op=logout"]') !== null ||
                                  document.querySelector('a[href*="logout"]') !== null ||
                                  document.querySelector('a[href*="/db/"]') !== null ||
                                  document.querySelector('#tquery') !== null ||
                                  document.querySelector('input[name="callsign"]') !== null;
                var looksLikeHome = currentUrl === "https://www.qrz.com/" ||
                                    currentUrl === "https://www.qrz.com" ||
                                    bodyText.includes('Database') ||
                                    bodyText.includes('Lookup');
                return !hasLoginForm && (hasLogout || hasUserMenu || looksLikeHome);
            })();
            """

            webView.evaluateJavaScript(jsCheck) { result, _ in
                let isAuthenticated = (result as? Bool) == true
                DispatchQueue.main.async {
                    if isAuthenticated {
                        self.parent.isLoggedIn = true
                        self.parent.statusMessage = "Authenticated. Session active on disk."
                    } else {
                        self.parent.isLoggedIn = false
                        self.parent.statusMessage = "Please sign in to your QRZ account."
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateFailureStatus(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            updateFailureStatus(error)
        }

        private func updateFailureStatus(_ error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoggedIn = false
                self.parent.statusMessage = "QRZ page load failed: \(error.localizedDescription)"
            }
        }

        deinit {
            statusTask?.cancel()
        }
    }
}
