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

            // Embedded Persistent WebKit Browser
            QRZWebViewRepresentable(
                statusMessage: $statusMessage,
                isLoggedIn: $isLoggedIn
            )

            Divider()

            // Bottom Status Bar
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
        appState.appendLog("🟢 QRZ Session saved to macOS WebKit Persistent Store!")
        appState.alertTitle = "QRZ Session Active 🟢"
        appState.alertMessage = "Your QRZ login session is now saved permanently on disk. You can use 'Enrich Data' to fetch emails!"
        appState.showAlert = true
        dismiss()
    }
}

// MARK: - Native WebKit Persistent Browser View
struct QRZWebViewRepresentable: NSViewRepresentable {
    @Binding var statusMessage: String
    @Binding var isLoggedIn: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Native Persistent Disk-Backed Store
        config.websiteDataStore = .default()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        
        if let url = URL(string: "https://www.qrz.com/login") {
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: QRZWebViewRepresentable

        init(_ parent: QRZWebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let jsCheck = """
            (function() {
                var bodyText = document.body ? document.body.innerText : "";
                var hasLogout = bodyText.includes('Log Out') || bodyText.includes('Logout') || bodyText.includes('Sign Out');
                var hasUserMenu = document.querySelector('a[href*="op=logout"]') !== null || 
                                  document.querySelector('a[href*="logout"]') !== null ||
                                  document.querySelector('#qem') !== null;
                return (hasLogout || hasUserMenu);
            })();
            """
            
            webView.evaluateJavaScript(jsCheck) { result, _ in
                let isAuthenticated = (result as? Bool) == true
                DispatchQueue.main.async {
                    if isAuthenticated {
                        self.parent.isLoggedIn = true
                        self.parent.statusMessage = "Authenticated! Session active on disk 🟢"
                    } else {
                        self.parent.isLoggedIn = false
                        self.parent.statusMessage = "Please sign in to your QRZ account..."
                    }
                }
            }
        }
    }
}
