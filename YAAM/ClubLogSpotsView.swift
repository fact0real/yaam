//
//  ClubLogSpotsView.swift
//  YAAM
//

import SwiftUI
import WebKit

struct ClubLogSpotsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var spotsService = ClubLogSpotsService()
    
    @State private var viewMode: Int = 0 // 0: Native Spots Table, 1: Live Web Page
    @State private var filterBand: String = "All"
    @State private var filterText: String = ""

    private var availableBands: [String] {
        let bands = Set(spotsService.spots.map { $0.band.uppercased() }).filter { !$0.isEmpty }
        return ["All"] + bands.sorted()
    }

    private var filteredSpots: [ClubLogSpotModel] {
        spotsService.spots.filter { spot in
            if filterBand != "All" && spot.band.uppercased() != filterBand.uppercased() {
                return false
            }
            if !filterText.isEmpty {
                let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return spot.callsign.lowercased().contains(query) ||
                    spot.dxcc.lowercased().contains(query) ||
                    spot.spotter.lowercased().contains(query) ||
                    spot.comment.lowercased().contains(query)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Toolbar Header
            HStack(spacing: 14) {
                Label("Club Log Personal Spots", systemImage: "person.3.fill")
                    .font(.headline)
                    .foregroundColor(.accentColor)

                Picker("", selection: $viewMode) {
                    Label("Native Spots", systemImage: "tablecells").tag(0)
                    Label("Live Web View", systemImage: "globe").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)

                Spacer()

                if viewMode == 0 {
                    HStack(spacing: 8) {
                        Picker("", selection: $filterBand) {
                            ForEach(availableBands, id: \.self) { band in
                                Text(band).tag(band)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)

                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            TextField("Filter spots...", text: $filterText)
                                .textFieldStyle(.plain)
                                .font(.caption)
                            if !filterText.isEmpty {
                                Button(action: { filterText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .frame(width: 150)

                        Button {
                            Task {
                                await refreshSpots()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(spotsService.isLoading)

                        if ClubLogSessionStore.hasSavedSession() {
                            Button {
                                appState.showClubLogLoginSheet = true
                            } label: {
                                Label("2FA Active", systemImage: "checkmark.shield.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                            .help("Club Log 2FA session is active. Click to verify or manage session.")
                        } else {
                            Button {
                                appState.showClubLogLoginSheet = true
                            } label: {
                                Label("2FA Login", systemImage: "lock.shield.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                            .help("Open Club Log WebKit Authenticator to sign in with 2FA/MFA")
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Warning / Credentials Banner
            if let errorMsg = spotsService.errorMessage, viewMode == 0 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMsg)
                        .font(.caption)
                    Spacer()
                    Button("2FA / Web Authenticator") {
                        appState.showClubLogLoginSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .font(.caption)

                    Button("Open Settings") {
                        appState.selectedTab = 5
                        appState.operatorDeskSection = 5
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                Divider()
            }

            if viewMode == 0 {
                nativeSpotsTable
            } else {
                ClubLogWebViewContainer { extractedSpots in
                    if !extractedSpots.isEmpty {
                        spotsService.spots = extractedSpots
                        spotsService.lastRefreshed = Date()
                        spotsService.errorMessage = nil
                    }
                }
            }
        }
        .task {
            if spotsService.spots.isEmpty {
                await refreshSpots()
            }
        }
        .sheet(isPresented: $appState.showClubLogLoginSheet, onDismiss: {
            Task {
                await refreshSpots()
            }
        }) {
            ClubLogLoginView()
                .environmentObject(appState)
        }
    }

    private var nativeSpotsTable: some View {
        Group {
            if spotsService.isLoading && spotsService.spots.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Fetching Personal Spots from Club Log...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if spotsService.spots.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.accentColor.opacity(0.8))
                    Text("No Personal Spots Found")
                        .font(.title3.weight(.bold))
                    Text("Ensure your Club Log credentials (Email & Application Password) are configured, or use the 2FA WebKit Authenticator to sign in directly.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                    HStack(spacing: 12) {
                        Button("Refresh Spots Now") {
                            Task { await refreshSpots() }
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            appState.showClubLogLoginSheet = true
                        } label: {
                            Label("Sign in with 2FA / Authenticator", systemImage: "lock.shield.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        if let lastRefreshed = spotsService.lastRefreshed {
                            Text("Showing \(filteredSpots.count) of \(spotsService.spots.count) spots • Refreshed: \(lastRefreshed.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    Table(filteredSpots) {
                        TableColumn("Callsign") { spot in
                            HStack(spacing: 6) {
                                Text(countryToFlag(spot.dxcc.isEmpty ? spot.callsign : spot.dxcc))
                                Text(spot.callsign)
                                    .fontWeight(.bold)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .width(min: 120, ideal: 140)

                        TableColumn("Freq (MHz)") { spot in
                            Text(spot.frequency)
                                .font(.system(.body, design: .monospaced))
                        }
                        .width(min: 80, ideal: 100)

                        TableColumn("Band") { spot in
                            Text(spot.band)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(4)
                        }
                        .width(min: 60, ideal: 75)

                        TableColumn("Mode") { spot in
                            Text(spot.mode)
                                .font(.caption)
                        }
                        .width(min: 60, ideal: 75)

                        TableColumn("DXCC Entity") { spot in
                            Text(spot.dxcc)
                                .font(.caption)
                        }
                        .width(min: 100, ideal: 140)

                        TableColumn("Spotter") { spot in
                            Text(spot.spotter)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .width(min: 80, ideal: 110)

                        TableColumn("Comment") { spot in
                            Text(spot.comment)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .width(min: 100, ideal: 160)

                        TableColumn("Status") { spot in
                            let isNeeded = spot.status.lowercased().contains("needed") || spot.status.lowercased().contains("most-wanted")
                            let isLoTW = spot.status.lowercased().contains("lotw")
                            let color: Color = isNeeded ? .orange : (isLoTW ? .blue : .green)
                            Text(spot.status)
                                .font(.caption2.bold())
                                .foregroundColor(color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color.opacity(0.12))
                                .cornerRadius(4)
                        }
                        .width(min: 80, ideal: 110)

                        TableColumn("Time (UTC)") { spot in
                            Text(spot.timeStr)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .width(min: 70, ideal: 90)

                        TableColumn("Actions") { spot in
                            HStack(spacing: 6) {
                                Button {
                                    appState.selectedTab = 0
                                    appState.logSearchMode = .callsign
                                    appState.searchText = spot.callsign
                                } label: {
                                    Label("Find in Log", systemImage: "magnifyingglass")
                                        .font(.caption2)
                                }
                                .buttonStyle(.borderless)

                                if let freqDouble = Double(spot.frequency) {
                                    Button {
                                        let freqHz = UInt64(freqDouble * 1_000_000)
                                        appState.rigControlClient.setFrequencyHz(freqHz)
                                        if !spot.mode.isEmpty {
                                            appState.rigControlClient.setMode(spot.mode)
                                        }
                                    } label: {
                                        Label("Tune", systemImage: "radio")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .width(min: 140, ideal: 170)
                    }
                }
            }
        }
    }

    private func refreshSpots() async {
        let creds = appState.qslServiceCredentials(for: [.clubLog])
        await spotsService.fetchPersonalSpots(credentials: creds)
    }
}

// MARK: - Club Log Web View Container
struct ClubLogWebViewContainer: View {
    @EnvironmentObject private var appState: AppState
    var onSpotsExtracted: (([ClubLogSpotModel]) -> Void)?
    @State private var webView: WKWebView = WKWebView()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    webView.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!webView.canGoBack)

                Button {
                    webView.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!webView.canGoForward)

                Button {
                    webView.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }

                Spacer()

                if ClubLogSessionStore.hasSavedSession() {
                    Button {
                        appState.showClubLogLoginSheet = true
                    } label: {
                        Label("2FA Active", systemImage: "checkmark.shield.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                } else {
                    Button {
                        appState.showClubLogLoginSheet = true
                    } label: {
                        Label("2FA Authenticator", systemImage: "lock.shield.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ClubLogRawWebView(webView: webView, onSpotsExtracted: onSpotsExtracted)
        }
    }
}

struct ClubLogRawWebView: NSViewRepresentable {
    let webView: WKWebView
    var onSpotsExtracted: (([ClubLogSpotModel]) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        ClubLogSessionStore.restoreToWebKit {
            guard let url = URL(string: "https://clublog.org/personal_spots.php") else { return }
            var req = URLRequest(url: url)
            let cookieHeader = ClubLogSessionStore.savedCookieHeader()
            if !cookieHeader.isEmpty {
                req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            webView.load(req)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ClubLogRawWebView

        init(_ parent: ClubLogRawWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(ClubLogSpotsService.domSpotsExtractorJS) { [weak self] result, _ in
                guard let self = self else { return }
                if let jsonString = result as? String, !jsonString.isEmpty && jsonString != "[]" {
                    let spots = ClubLogSpotsService.parseSpotsFromJSON(jsonString)
                    DispatchQueue.main.async {
                        self.parent.onSpotsExtracted?(spots)
                    }
                }
            }
        }
    }
}
