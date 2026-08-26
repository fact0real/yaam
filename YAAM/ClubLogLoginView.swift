//
//  ClubLogLoginView.swift
//  YAAM
//

import SwiftUI
import WebKit
import Combine

// MARK: - Native WebKit Club Log Login Window (Supports 2FA/MFA)
struct ClubLogLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var statusText: String = "Connecting to Club Log..."
    @State private var saveRequestID = 0
    @State private var autofillRequestID = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.blue)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Club Log Authenticator & 2FA")
                        .font(.headline)
                    Text("Enter your credentials and 2FA code. Session will be saved securely.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Fill Saved Credentials") {
                    autofillRequestID += 1
                }
                .buttonStyle(.bordered)
                .help("Re-inject saved email and password from settings")

                Button("Done / Save Session") {
                    appState.appendLog("Club Log session save requested from authenticator.")
                    statusText = "Saving Club Log session cookies..."
                    saveRequestID += 1
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button("Cancel") {
                    dismiss()
                }
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ClubLogWebViewStore(
                statusText: $statusText,
                saveRequestID: saveRequestID,
                autofillRequestID: autofillRequestID
            ) { cookies in
                appState.saveClubLogSessionCookies(cookies)
                appState.appendLog("✅ Club Log session saved successfully via WebKit Authenticator!")
                dismiss()
            }

            Divider()

            // Status Bar at Bottom
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.6)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(
            minWidth: 640,
            idealWidth: 860,
            maxWidth: .infinity,
            minHeight: 580,
            idealHeight: 820,
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 640, minHeight: 580)
    }
}

// MARK: - WKWebView Representable for Club Log Login
struct ClubLogWebViewStore: NSViewRepresentable {
    @Binding var statusText: String
    let saveRequestID: Int
    let autofillRequestID: Int
    var onCookieCaptured: ([HTTPCookie]) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = QRZWebKitSession.userAgent
        webView.navigationDelegate = context.coordinator

        context.coordinator.loadInitialPage(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastSaveRequestID != saveRequestID {
            context.coordinator.lastSaveRequestID = saveRequestID
            context.coordinator.captureCookies(from: nsView, manual: true)
        }
        if context.coordinator.lastAutofillRequestID != autofillRequestID {
            context.coordinator.lastAutofillRequestID = autofillRequestID
            context.coordinator.autofillCredentials(in: nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ClubLogWebViewStore
        var lastSaveRequestID = 0
        var lastAutofillRequestID = 0
        private var hasCompletedLogin = false

        init(_ parent: ClubLogWebViewStore) {
            self.parent = parent
        }

        func loadInitialPage(in webView: WKWebView) {
            ClubLogSessionStore.restoreToWebKit {
                guard let url = URL(string: "https://clublog.org/personal_spots.php") else { return }
                var req = URLRequest(url: url)
                let header = ClubLogSessionStore.savedCookieHeader()
                if !header.isEmpty {
                    req.setValue(header, forHTTPHeaderField: "Cookie")
                }
                webView.load(req)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.statusText = "Loading Club Log..."
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.statusText = "Rendering Club Log page..."
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasCompletedLogin else { return }

            // Evaluate the page state through comprehensive DOM inspection
            let inspectDOMJS = """
            (function() {
                var text = document.body ? document.body.innerText.toLowerCase() : '';
                var hasLogout = !!document.querySelector('a[href*="logout"]') || text.includes('log out') || text.includes('logout');
                var hasLoginForm = !!document.querySelector('#clublogform') || !!document.querySelector('input[type="password"]');

                var inputs = Array.from(document.querySelectorAll('input'));
                var has2FAInput = inputs.some(function(i) {
                    var n = (i.name || '').toLowerCase();
                    var id = (i.id || '').toLowerCase();
                    var p = (i.placeholder || '').toLowerCase();
                    return n.includes('2fa') || n.includes('otp') || n.includes('code') || 
                           id.includes('2fa') || id.includes('otp') || id.includes('code') ||
                           p.includes('code') || p.includes('token');
                });
                var mentions2FA = text.includes('two-factor') || text.includes('verification code') || text.includes('authenticator') || text.includes('security code');

                var isSpotsPage = window.location.href.includes('personal_spots') && !hasLoginForm;

                return {
                    isLoggedIn: (hasLogout || isSpotsPage) && !hasLoginForm && !has2FAInput,
                    is2FAPrompt: has2FAInput || mentions2FA,
                    hasLoginForm: hasLoginForm
                };
            })();
            """

            webView.evaluateJavaScript(inspectDOMJS) { [weak self] result, _ in
                guard let self = self else { return }
                guard let dict = result as? [String: Any] else {
                    DispatchQueue.main.async {
                        self.parent.statusText = "Please log in and enter your 2FA code."
                    }
                    return
                }

                let isLoggedIn = dict["isLoggedIn"] as? Bool ?? false
                let is2FAPrompt = dict["is2FAPrompt"] as? Bool ?? false
                let hasLoginForm = dict["hasLoginForm"] as? Bool ?? false

                if isLoggedIn {
                    // Only trigger completion when truly logged in!
                    self.hasCompletedLogin = true
                    self.saveSessionAndDismiss(from: webView)
                } else if is2FAPrompt {
                    DispatchQueue.main.async {
                        self.parent.statusText = "🔑 2FA Required: Enter your verification code from your authenticator app and submit."
                    }
                    // NEVER dismiss when 2FA code is requested!
                } else if hasLoginForm {
                    self.autofillCredentials(in: webView)
                    DispatchQueue.main.async {
                        self.parent.statusText = "Please click Login (credentials autofilled). Enter 2FA code if prompted."
                    }
                    // NEVER dismiss while on login form!
                } else {
                    DispatchQueue.main.async {
                        self.parent.statusText = "Page loaded. Enter credentials or 2FA code if prompted."
                    }
                }
            }
        }

        private func saveSessionAndDismiss(from webView: WKWebView) {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { [weak self] cookies in
                guard let self = self else { return }
                let clubLogCookies = cookies.filter { $0.domain.contains("clublog.org") }

                _ = ClubLogSessionStore.save(cookies: clubLogCookies)
                DispatchQueue.main.async {
                    self.parent.statusText = "✅ 2FA Verified! Login successful."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        self.parent.onCookieCaptured(clubLogCookies)
                    }
                }
            }
        }

        func autofillCredentials(in webView: WKWebView) {
            let email = UserDefaults.standard.string(forKey: "clubLogEmail") ?? ""
            let password = CredentialVault.value(for: .clubLogPassword)
            guard !email.isEmpty || !password.isEmpty else { return }

            let js = """
            (function() {
                var emailVal = \(jsonString(email));
                var passVal = \(jsonString(password));

                // 1. Locate email input (ClubLog uses dynamic input names like n_e_...)
                var emailInput = document.querySelector('input[autocomplete="username"]');
                if (!emailInput) {
                    var rows = document.querySelectorAll('tr');
                    for (var r = 0; r < rows.length; r++) {
                        var text = (rows[r].innerText || '').toLowerCase();
                        if (text.includes('email') || text.includes('callsign')) {
                            var inp = rows[r].querySelector('input[type="text"]');
                            if (inp) { emailInput = inp; break; }
                        }
                    }
                }
                if (!emailInput) {
                    var allInputs = document.querySelectorAll('#clublogform input[type="text"], form input[type="text"]');
                    for (var i = 0; i < allInputs.length; i++) {
                        var rect = allInputs[i].getBoundingClientRect();
                        var style = window.getComputedStyle(allInputs[i]);
                        if (style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0) {
                            emailInput = allInputs[i];
                            break;
                        }
                    }
                }

                // 2. Locate password input
                var passInput = document.querySelector('input[type="password"]');

                if (emailInput && emailVal && !emailInput.value) {
                    emailInput.value = emailVal;
                    emailInput.dispatchEvent(new Event('input', { bubbles: true }));
                    emailInput.dispatchEvent(new Event('change', { bubbles: true }));
                }

                if (passInput && passVal && !passInput.value) {
                    passInput.value = passVal;
                    passInput.dispatchEvent(new Event('input', { bubbles: true }));
                    passInput.dispatchEvent(new Event('change', { bubbles: true }));
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func jsonString(_ text: String) -> String {
            if let data = try? JSONEncoder().encode(text), let s = String(data: data, encoding: .utf8) {
                return s
            }
            return "\"\""
        }

        func captureCookies(from webView: WKWebView, manual: Bool) {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { [weak self] cookies in
                guard let self = self else { return }
                let clubLogCookies = cookies.filter { $0.domain.contains("clublog.org") }

                if !clubLogCookies.isEmpty {
                    _ = ClubLogSessionStore.save(cookies: clubLogCookies)
                    DispatchQueue.main.async {
                        self.parent.statusText = "✅ Session saved successfully!"
                        self.parent.onCookieCaptured(clubLogCookies)
                    }
                } else if manual {
                    DispatchQueue.main.async {
                        self.parent.statusText = "No Club Log cookies found yet. Please complete login first."
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.statusText = "Page load error: \(error.localizedDescription)"
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.statusText = "Connection error: \(error.localizedDescription)"
            }
        }
    }
}
