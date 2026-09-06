//
//  OperationsCenterViews.swift
//  YAAM
//

import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct QSLHubPanel: View {
    var body: some View {
        QSLHubStudioView()
    }
}

private struct QSLServiceSettings: View {
    @AppStorage("lotwUsername") private var lotwUsername = ""
    @AppStorage("tqslExecutablePath") private var tqslPath = ""
    @AppStorage("eqslUsername") private var eqslUsername = ""
    @AppStorage("clubLogEmail") private var clubLogEmail = ""
    @AppStorage("clubLogCallsign") private var clubLogCallsign = ""
    @AppStorage("qslAutoQueueQuickLog") private var autoQueue = false
    @AppStorage("qslAutomaticProviders") private var automaticProviders = ""
    @State private var lotwPassword = ""
    @State private var eqslPassword = ""
    @State private var clubLogPassword = ""
    @State private var clubLogAPIKey = ""
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    serviceLabel("LoTW", icon: "checkmark.seal")
                    TextField("Callsign", text: $lotwUsername)
                    SecureField("Password", text: $lotwPassword)
                    HStack {
                        TextField("TQSL executable", text: $tqslPath)
                        Button { chooseTQSL() } label: { Image(systemName: "folder") }
                            .help("Choose the TQSL executable")
                    }
                }
                GridRow { serviceLabel("eQSL", icon: "envelope.badge"); TextField("Username", text: $eqslUsername); SecureField("Password", text: $eqslPassword); Text("QTH nickname comes from Station Profile").font(.caption).foregroundStyle(.secondary) }
                GridRow { serviceLabel("Club Log", icon: "person.3"); TextField("Email", text: $clubLogEmail); SecureField("Application password", text: $clubLogPassword); TextField("Callsign", text: $clubLogCallsign) }
                GridRow { Text(""); Text(""); SecureField("Club Log API key", text: $clubLogAPIKey); Text("") }
            }

            Toggle("Queue enabled services after each Quick Log QSO", isOn: $autoQueue)
            if autoQueue {
                HStack {
                    ForEach(QSLProvider.allCases) { provider in
                        let enabled = automaticProviderSet.contains(provider)
                        Button {
                            var set = automaticProviderSet
                            if enabled { set.remove(provider) } else { set.insert(provider) }
                            automaticProviders = set.map(\.rawValue).sorted().joined(separator: ",")
                        } label: {
                            Label(provider.title, systemImage: enabled ? "checkmark.circle.fill" : provider.icon)
                        }
                        .buttonStyle(.bordered)
                        .tint(enabled ? .green : .secondary)
                    }
                }
            }

            HStack {
                Button("Save Securely") { save() }
                    .buttonStyle(.borderedProminent)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            lotwPassword = CredentialVault.value(for: .lotwPassword)
            eqslPassword = CredentialVault.value(for: .eqslPassword)
            clubLogPassword = CredentialVault.value(for: .clubLogPassword)
            clubLogAPIKey = CredentialVault.value(for: .clubLogAPIKey)
        }
    }

    private var automaticProviderSet: Set<QSLProvider> {
        Set(automaticProviders.split(separator: ",").compactMap { QSLProvider(rawValue: String($0)) })
    }

    private func serviceLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).frame(width: 95, alignment: .leading)
    }

    private func save() {
        let results = [
            CredentialVault.set(lotwPassword, for: .lotwPassword),
            CredentialVault.set(eqslPassword, for: .eqslPassword),
            CredentialVault.set(clubLogPassword, for: .clubLogPassword),
            CredentialVault.set(clubLogAPIKey, for: .clubLogAPIKey)
        ]
        status = results.allSatisfy { $0 } ? "Credentials saved in Keychain" : "One or more credentials could not be saved"
    }

    private func chooseTQSL() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose TQSL"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            tqslPath = url.path
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: "tqslExecutableBookmark")
            }
        }
    }
}

struct AwardCenterPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var family = "All"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(title: "Independent Award Engine", subtitle: "Worked, confirmed, credited, submitted, and granted are tracked separately", icon: "medal.fill", color: .orange)
                awardSummary
                Picker("Family", selection: $family) {
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 720)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 14)], spacing: 14) {
                    ForEach(filteredAwards) { award in
                        awardCard(award)
                    }
                }

                Label("These are local planning estimates. Issuing organizations remain authoritative for accepted credits and granted awards.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
        }
        .onAppear { appState.refreshAwardProgress() }
        .onChange(of: appState.qsoRecords.count) { _, _ in appState.refreshAwardProgress() }
    }

    private var awardSummary: some View {
        HStack(spacing: 10) {
            OperationsMetric(title: "Tracked", value: appState.awardProgress.count, icon: "scope", color: .blue)
            OperationsMetric(title: "Locally complete", value: appState.awardProgress.filter(\.earnedLocally).count, icon: "checkmark.seal.fill", color: .green)
            OperationsMetric(title: "Submitted", value: appState.awardProgress.filter { $0.effectiveStage == .submitted }.count, icon: "paperplane.fill", color: .orange)
            OperationsMetric(title: "Granted", value: appState.awardProgress.filter { $0.effectiveStage == .granted }.count, icon: "medal.fill", color: .purple)
        }
    }

    private var families: [String] {
        ["All"] + Array(Set(appState.awardProgress.map(\.family))).sorted()
    }

    private var filteredAwards: [AwardProgress] {
        family == "All" ? appState.awardProgress : appState.awardProgress.filter { $0.family == family }
    }

    private func awardCard(_ award: AwardProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Header (Icon, Title, Detail, Stage Menu) - Fixed Height
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: award.earnedLocally ? "checkmark.seal.fill" : award.icon)
                    .font(.title2)
                    .foregroundStyle(award.earnedLocally ? Color.green : progressColor(award.percent))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(award.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(award.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    ForEach(AwardLifecycleStage.allCases) { stage in
                        Button(stage.title) { appState.saveAwardStage(awardID: award.id, stage: stage) }
                    }
                } label: {
                    Text(award.effectiveStage.title)
                        .font(.caption.weight(.bold))
                }
                .menuStyle(.borderlessButton)
            }
            .frame(height: 36)

            // 2. Progress Bar & Percentage HUD - Fixed Height
            VStack(spacing: 4) {
                if let percent = award.percent {
                    ProgressView(value: percent, total: 100)
                        .tint(progressColor(percent))
                    HStack {
                        Text("\(Int(percent.rounded()))%")
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(progressColor(percent))
                        Spacer()
                        if let remaining = award.remaining {
                            Text(remaining == 0 ? "Target reached" : "\(remaining) remaining")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ProgressView(value: min(100.0, Double(award.worked) * 10.0), total: 100)
                        .tint(.orange)
                    HStack {
                        Text("\(award.worked)")
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(.orange)
                        + Text(" active").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("Milestone tracker")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 42)

            // 3. Metric Counters Box (Worked, Confirmed, Credited)
            HStack(spacing: 0) {
                awardMetric("Worked", award.worked)
                Divider().frame(height: 26)
                awardMetric("Confirmed", award.confirmed)
                Divider().frame(height: 26)
                awardMetric("Credited", award.credited)
            }
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            Spacer(minLength: 0)

            // 4. Source Note Footer - Fixed 2-line Height
            Text(award.sourceNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26, alignment: .topLeading)
        }
        .padding(14)
        .frame(height: 216)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(progressColor(award.percent).opacity(0.25), lineWidth: 1)
        )
    }

    private func awardMetric(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressColor(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        if percent >= 100 { return .green }
        let normalized = min(100, max(0, percent)) / 100
        return Color(
            hue: normalized * 0.33,
            saturation: 0.82,
            brightness: 0.88
        )
    }
}

struct PortableActivitiesPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var program = "All"

    private var summaries: [PortableActivitySummary] { appState.portableActivitySummaries }
    private var filtered: [PortableActivitySummary] { program == "All" ? summaries : summaries.filter { $0.program.rawValue == program } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(title: "Portable Activities", subtitle: "POTA, SOTA, IOTA, and VUCC references stay portable in standard ADIF", icon: "figure.hiking", color: .green)
                HStack(spacing: 10) {
                    OperationsMetric(title: "Activity days", value: summaries.count, icon: "calendar", color: .blue)
                    OperationsMetric(title: "POTA ready", value: summaries.filter { $0.program == .pota && $0.isActivationReady }.count, icon: "checkmark.circle.fill", color: .green)
                    OperationsMetric(title: "Portable QSOs", value: summaries.reduce(0) { $0 + $1.qsoCount }, icon: "antenna.radiowaves.left.and.right", color: .orange)
                }
                Picker("Program", selection: $program) {
                    Text("All").tag("All")
                    ForEach(PortableProgram.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                if filtered.isEmpty {
                    ContentUnavailableView("No Portable Activity Yet", systemImage: "figure.hiking", description: Text("Add references in Quick Log or import standard portable ADIF fields."))
                        .frame(minHeight: 260)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 12)], spacing: 12) {
                        ForEach(filtered) { summary in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: summary.program.icon).foregroundStyle(.green).font(.title2)
                                    VStack(alignment: .leading) {
                                        Text(summary.reference).font(.headline.monospaced())
                                        Text(portableDate(summary.date)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if summary.program == .pota {
                                        Label(summary.isActivationReady ? "Ready" : "\(max(0, 10 - summary.qsoCount)) needed", systemImage: summary.isActivationReady ? "checkmark.circle.fill" : "clock")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(summary.isActivationReady ? .green : .orange)
                                    }
                                }
                                HStack {
                                    portableMetric("QSOs", summary.qsoCount)
                                    portableMetric("Confirmed", summary.confirmedCount)
                                    portableMetric("Unique calls", summary.uniqueCallsigns)
                                }
                                Text(summary.bands.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                Button {
                                    appState.exportPortableActivity(summary)
                                } label: { Label("Export ADIF", systemImage: "square.and.arrow.up") }
                            }
                            .padding(15)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.green.opacity(0.2)))
                        }
                    }
                }
            }
            .padding(22)
        }
        .onAppear { appState.refreshAwardProgress() }
    }

    private func portableMetric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(value.formatted()).font(.headline.monospacedDigit()); Text(title).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func portableDate(_ value: String) -> String {
        guard value.count == 8 else { return value }
        return "\(value.prefix(4))-\(value.dropFirst(4).prefix(2))-\(value.suffix(2)) UTC"
    }
}

struct ConnectivityPanel: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("cloudSyncAutomatic") private var cloudAutomatic = false
    @AppStorage("cloudSyncMinutes") private var cloudMinutes = 15
    @AppStorage("mobileCompanionPort") private var mobilePort = 7373
    @AppStorage("mobileCompanionAllowLogging") private var allowMobileLogging = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(title: "Connected Station", subtitle: "Versioned cloud packages, local API, and a phone-ready companion", icon: "network", color: .blue)
                cloudSection
                mobileSection
                apiReference
            }
            .padding(22)
        }
        .onAppear { appState.updateMobileCompanionSnapshot() }
    }

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("iCloud Drive package sync", systemImage: "icloud.and.arrow.up")
                    .font(.headline)
                Spacer()
                if appState.isCloudSyncRunning { ProgressView().controlSize(.small) }
                Text(appState.cloudSyncStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("YAAM writes a versioned, mergeable package to your chosen synchronized folder. The live SQLite database never travels through iCloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button { appState.chooseCloudSyncFolder() } label: { Label("Choose Folder", systemImage: "folder") }
                Button { Task { _ = await appState.pullCloudPackage() } } label: { Label("Pull & Merge", systemImage: "arrow.down.circle") }
                    .disabled(appState.isCloudSyncRunning)
                Button { Task { await appState.pushCloudPackage() } } label: { Label("Push", systemImage: "arrow.up.circle") }
                    .disabled(appState.isCloudSyncRunning)
                Button { Task { await appState.syncCloudPackage() } } label: { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isCloudSyncRunning)
                Button(role: .destructive) { appState.disconnectCloudSyncFolder() } label: { Image(systemName: "xmark.circle") }
                    .help("Disconnect the selected cloud folder")
            }
            HStack {
                Toggle("Automatic sync", isOn: $cloudAutomatic)
                    .onChange(of: cloudAutomatic) { _, _ in appState.configureCloudSyncTimer() }
                Stepper("Every \(max(5, cloudMinutes)) min", value: $cloudMinutes, in: 5...120, step: 5)
                    .onChange(of: cloudMinutes) { _, _ in appState.configureCloudSyncTimer() }
                    .disabled(!cloudAutomatic)
                Spacer()
                if let date = appState.cloudSyncLastRun { Text("Last: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .operationsBand(color: .blue)
    }

    private var mobileSection: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Mobile companion", systemImage: "iphone.gen3")
                        .font(.headline)
                    Spacer()
                    Circle().fill(appState.isMobileCompanionRunning ? Color.green : Color.secondary).frame(width: 8, height: 8)
                    Text(appState.mobileCompanionStatus).font(.caption).foregroundStyle(.secondary)
                }
                Text("Open the private link on a phone connected to the same local network. The token is stored in Keychain and the server is off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Stepper("Port \(mobilePort)", value: $mobilePort, in: 1024...65_535)
                        .frame(width: 150)
                        .disabled(appState.isMobileCompanionRunning)
                    Toggle("Allow Quick Log", isOn: $allowMobileLogging)
                    Spacer()
                }
                HStack {
                    Button {
                        appState.isMobileCompanionRunning ? appState.stopMobileCompanion() : appState.startMobileCompanion()
                    } label: {
                        Label(appState.isMobileCompanionRunning ? "Stop" : "Start", systemImage: appState.isMobileCompanionRunning ? "stop.circle.fill" : "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Button { copyLink() } label: { Image(systemName: "doc.on.doc") }.help("Copy private mobile link").disabled(appState.mobileCompanionURL.isEmpty)
                    Button { openLink() } label: { Image(systemName: "safari") }.help("Open mobile companion").disabled(appState.mobileCompanionURL.isEmpty)
                    Button { appState.rotateMobileCompanionToken() } label: { Image(systemName: "arrow.triangle.2.circlepath.key") }.help("Rotate access token")
                }
                if !appState.mobileCompanionURL.isEmpty {
                    Text(appState.mobileCompanionURL)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
            if let image = QRCodeRenderer.image(for: appState.mobileCompanionURL), appState.isMobileCompanionRunning {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 150, height: 150)
                    .accessibilityLabel("QR code for the private mobile companion link")
            }
        }
        .operationsBand(color: .green)
    }

    private var apiReference: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Local API v1", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)
            Text("GET /api/v1/status   ·   GET /api/v1/qsos?offset=0&limit=100   ·   GET /api/v1/awards   ·   POST /api/v1/qsos")
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Text("Authorization: Bearer <token>. QSO pages are capped at 500 records; requests are accepted only while the local companion is running.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.mobileCompanionURL, forType: .string)
        appState.mobileCompanionStatus = "Private link copied"
    }

    private func openLink() {
        guard let url = URL(string: appState.mobileCompanionURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

private enum QRCodeRenderer {
    static func image(for value: String) -> NSImage? {
        guard !value.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

private struct OperationsMetric: View {
    var title: String
    var value: Int
    var icon: String
    var color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).font(.title3).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted()).font(.headline.monospacedDigit())
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.22)))
    }
}

private func sectionHeader(title: String, subtitle: String, icon: String, color: Color) -> some View {
    HStack(spacing: 14) {
        Image(systemName: icon)
            .font(.title2)
            .foregroundStyle(color)
            .frame(width: 46, height: 46)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.weight(.bold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func operationsBand(color: Color) -> some View {
        padding(15)
            .background(color.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.18)))
    }
}
