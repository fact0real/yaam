//
//  QRZLoginView.swift
//  YAAM
//
//  Created by EP2AES on 8/9/26.
//

import SwiftUI
import WebKit

// MARK: - Native WebKit QRZ Login Window
struct QRZLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var statusText: String = "Please log in to QRZ.com (supports MFA/2FA)..."

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                Text("QRZ.com Authenticator")
                    .font(.headline)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Embedded Browser View
            QRZWebViewStore(statusText: $statusText) { cookieString in
                // Save captured cookie string to persistent storage
                UserDefaults.standard.set(cookieString, forKey: "qrzSessionCookie")
                appState.appendLog("✅ QRZ Session Cookie captured successfully via WKWebView!")
                appState.showNativeAlert(
                    title: "QRZ Authenticated! 🔐",
                    message: "Session cookie saved successfully. You can now use 'Enrich Data' to fetch hidden emails."
                )
                dismiss()
            }
            
            Divider()
            
            // Footer Status Bar
            HStack {
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
    var onCookieCaptured: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        
        // Load official QRZ Login Page
        if let url = URL(string: "https://www.qrz.com/login") {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - WKNavigationDelegate Coordinator
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: QRZWebViewStore

        init(_ parent: QRZWebViewStore) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let store = webView.configuration.websiteDataStore.httpCookieStore
            
            store.getAllCookies { cookies in
                var cookiePairs: [String] = []
                var hasSessionCookie = false
                
                for cookie in cookies where cookie.domain.contains("qrz.com") {
                    cookiePairs.append("\(cookie.name)=\(cookie.value)")
                    if cookie.name == "qrz_session" || cookie.name.contains("session") {
                        hasSessionCookie = true
                    }
                }
                
                if hasSessionCookie && !cookiePairs.isEmpty {
                    let fullCookieString = cookiePairs.joined(separator: "; ")
                    DispatchQueue.main.async {
                        self.parent.statusText = "Login detected! Capturing session cookie..."
                        self.parent.onCookieCaptured(fullCookieString)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.parent.statusText = "Navigated to: \(webView.url?.absoluteString ?? "")"
                    }
                }
            }
        }
    }
}
