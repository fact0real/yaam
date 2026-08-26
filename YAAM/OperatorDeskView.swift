//
//  OperatorDeskView.swift
//  YAAM
//

import AppKit
import SwiftUI

private let clusterUTCTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "HH:mm"
    return formatter
}()

struct OperatorDeskView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    stationLabel
                    deskPicker
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 1100)
                    Spacer(minLength: 8)
                    deskStatus
                        .frame(maxWidth: 220, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    stationLabel
                    Spacer(minLength: 6)
                    deskPicker
                        .pickerStyle(.menu)
                        .frame(maxWidth: 260)
                    deskStatus
                        .frame(maxWidth: 180, alignment: .trailing)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            switch appState.operatorDeskSection {
            case 1:
                DXClusterPanel(client: appState.dxClusterClient)
            case 2:
                SyncCenterPanel()
            case 3:
                RadioBridgePanel(rig: appState.rigControlClient, wsjtx: appState.wsjtxListener)
            case 4:
                ContestPanel()
            case 5:
                QSLHubPanel()
            case 6:
                AwardCenterPanel()
            case 7:
                PortableActivitiesPanel()
            case 8:
                ConnectivityPanel()
            case 9:
                ContestCalendarAndPropagationPanel()
            case 10:
                ClubLogSpotsView()
            default:
                QuickLogPanel()
            }
        }
    }

    private var stationLabel: some View {
        Label(appState.currentStationCallsign, systemImage: "antenna.radiowaves.left.and.right")
            .font(.system(.headline, design: .monospaced).weight(.bold))
            .foregroundStyle(.green)
            .lineLimit(1)
    }

    private var deskPicker: some View {
        Picker("Operator workspace", selection: $appState.operatorDeskSection) {
            Label("Quick Log", systemImage: "plus.circle.fill").tag(0)
            Label("DX Cluster", systemImage: "dot.radiowaves.left.and.right").tag(1)
            Label("Club Log Spots", systemImage: "person.3.fill").tag(10)
            Label("Sync Center", systemImage: "arrow.triangle.2.circlepath").tag(2)
            Label("Radio Bridge", systemImage: "wave.3.right.circle").tag(3)
            Label("Contest", systemImage: "flag.checkered").tag(4)
            Label("QSL", systemImage: "arrow.left.arrow.right.circle").tag(5)
            Label("Awards", systemImage: "medal").tag(6)
            Label("Portable", systemImage: "figure.hiking").tag(7)
            Label("Connect", systemImage: "network").tag(8)
            Label("Calendar/6m", systemImage: "calendar.badge.clock").tag(9)
        }
        .labelsHidden()
        .onChange(of: appState.operatorDeskSection) { _, value in
            UserDefaults.standard.set(value, forKey: "operatorDeskSection")
        }
    }

    @ViewBuilder
    private var deskStatus: some View {
        let status: (Bool, String) = switch appState.operatorDeskSection {
        case 3:
            (appState.rigControlClient.state.isConnected || appState.wsjtxListener.state.isListening,
             appState.rigControlClient.state.isConnected ? appState.rigControlClient.state.title : appState.wsjtxListener.state.title)
        case 4:
            (appState.currentContestSession?.isActive == true,
             appState.currentContestSession?.isActive == true ? "Contest active" : "No active contest")
        case 5:
            (!appState.qslQueueJobs.contains(where: { $0.state == .blocked || $0.state == .failed }), appState.qslHubStatus)
        case 6:
            (!appState.awardProgress.isEmpty, appState.awardEngineStatus)
        case 7:
            (!appState.portableActivitySummaries.isEmpty, "Portable activity log")
        case 8:
            (appState.isMobileCompanionRunning || appState.cloudSyncLastRun != nil, appState.isMobileCompanionRunning ? appState.mobileCompanionStatus : appState.cloudSyncStatus)
        case 9:
            (appState.sixMeterAssessment.isOpen, appState.sixMeterAssessment.title)
        default:
            (appState.dxClusterClient.state.isConnected, appState.dxClusterClient.state.title)
        }
        HStack(spacing: 5) {
            Circle()
                .fill(status.0 ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(status.1)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(status.1)
    }
}

private struct QuickLogPanel: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedField: Field?
    @State private var lookupTask: Task<Void, Never>?
    @State private var showDuplicateConfirmation = false
    @State private var duplicateWasAcknowledged = false
    @State private var showPortableFields = false

    private enum Field { case callsign, frequency, rstSent, rstReceived, exchange, comment }
    private let modes = ["SSB", "CW", "DIGI", "FM", "AM", "RTTY", "MFSK", "SSTV", "SAT"]

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 920 {
                HSplitView {
                    ScrollView {
                        entryFields
                            .padding(22)
                    }
                    .frame(minWidth: 620)

                    historyPanel
                        .frame(minWidth: 280, idealWidth: 330, maxWidth: 390)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        entryFields
                            .padding(22)
                        Divider()
                        historyPanel
                            .frame(minHeight: 280)
                    }
                }
            }
        }
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .onAppear {
            focusedField = .callsign
            appState.refreshQuickLogAssessment()
        }
        .onChange(of: appState.quickLogDraft.callsign) { _, newValue in
            duplicateWasAcknowledged = false
            lookupTask?.cancel()
            appState.quickLogLookup = nil
            appState.refreshQuickLogAssessment()
            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard appState.isValidOperatorCallsign(normalized) else {
                appState.quickLogStatus = normalized.isEmpty ? "Ready" : "Waiting for a complete callsign"
                return
            }
            lookupTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await appState.lookupQuickLogCallsign(normalized)
            }
        }
        .onChange(of: appState.quickLogDraft.band) { _, _ in
            duplicateWasAcknowledged = false
            appState.refreshQuickLogAssessment()
        }
        .onChange(of: appState.quickLogDraft.mode) { _, _ in
            duplicateWasAcknowledged = false
            appState.refreshQuickLogAssessment()
        }
        .confirmationDialog(
            "Possible duplicate QSO",
            isPresented: $showDuplicateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log Anyway") {
                duplicateWasAcknowledged = true
                save()
            }
            Button("Review Entry", role: .cancel) { focusedField = .callsign }
        } message: {
            Text(appState.quickLogAssessment.contestDuplicate
                 ? "This callsign is already in the active contest log on the same band and mode."
                 : "This callsign was logged on the same band and mode within 30 minutes.")
        }
    }

    private var entryFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            quickEntryHeader
            operatingFields
            reportFields
            contestFields
            portableFields
            contactFields
            notesAndSave
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var portableFields: some View {
        DisclosureGroup(isExpanded: $showPortableFields) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Operating role", selection: $appState.quickLogDraft.portableRole) {
                    ForEach(PortableOperatingRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        labeledField("My POTA reference", text: $appState.quickLogDraft.myPOTAReference)
                        labeledField("Contacted POTA reference", text: $appState.quickLogDraft.contactedPOTAReference)
                    }
                    GridRow {
                        labeledField("My SOTA reference", text: $appState.quickLogDraft.mySOTAReference)
                        labeledField("Contacted SOTA reference", text: $appState.quickLogDraft.contactedSOTAReference)
                    }
                    GridRow {
                        labeledField("My IOTA reference", text: $appState.quickLogDraft.myIOTAReference)
                        labeledField("Contacted IOTA reference", text: $appState.quickLogDraft.contactedIOTAReference)
                    }
                    GridRow {
                        labeledField("My VUCC grids", text: $appState.quickLogDraft.myVUCCGrids)
                        labeledField("Contacted VUCC grids", text: $appState.quickLogDraft.contactedVUCCGrids)
                    }
                }

                Text("Activator references stay in the next entry; contacted references are cleared after each QSO.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        } label: {
            Label("Portable Activity", systemImage: "figure.hiking")
                .font(.headline)
        }
        .padding(12)
        .background(Color.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.18)))
    }

    private var quickEntryHeader: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CALLSIGN")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                TextField("DX callsign", text: $appState.quickLogDraft.callsign)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .focused($focusedField, equals: .callsign)
                    .onSubmit { moveAfterCallsign() }
                    .frame(minWidth: 260)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("START UTC")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $appState.quickLogDraft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            Button {
                appState.quickLogDraft.startedAt = Date()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Set start time to now")

            if appState.isLookingUpQuickLogCallsign {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var operatingFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Operating", systemImage: "waveform.path.ecg")
                .font(.headline)

            HStack(spacing: 12) {
                compactField("Frequency (MHz)", width: 150) {
                    TextField("14.074", text: $appState.quickLogDraft.frequencyMHz)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: .frequency)
                        .onChange(of: appState.quickLogDraft.frequencyMHz) { _, value in
                            if let band = AmateurBandPlan.band(for: value) {
                                appState.quickLogDraft.band = band
                            }
                        }
                }

                compactField("Band", width: 120) {
                    Picker("", selection: $appState.quickLogDraft.band) {
                        ForEach(AmateurBandPlan.commonBands, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }

                compactField("Mode", width: 120) {
                    Picker("", selection: $appState.quickLogDraft.mode) {
                        ForEach(modes, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: appState.quickLogDraft.mode) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        appState.quickLogDraft.rstSent = AmateurBandPlan.defaultRST(for: newValue)
                        appState.quickLogDraft.rstReceived = AmateurBandPlan.defaultRST(for: newValue)
                    }
                }

                compactField("Submode", width: 130) {
                    TextField("FT8", text: $appState.quickLogDraft.submode)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var reportFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Signal Report", systemImage: "gauge.with.dots.needle.50percent")
                .font(.headline)
            HStack(spacing: 12) {
                compactField("RST Sent", width: 130) {
                    TextField("59", text: $appState.quickLogDraft.rstSent)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: .rstSent)
                }
                compactField("RST Received", width: 130) {
                    TextField("59", text: $appState.quickLogDraft.rstReceived)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: .rstReceived)
                }
            }
        }
    }

    @ViewBuilder
    private var contestFields: some View {
        if let session = appState.currentContestSession, session.isActive {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Contest Exchange", systemImage: "flag.checkered")
                        .font(.headline)
                    Spacer()
                    Text(session.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 12) {
                    compactValue("Serial", value: String(ContestWorkspaceLogic.nextSerial(in: session, records: appState.qsoRecords)))
                    compactValue("Sent", value: session.sentExchange.isEmpty ? "--" : session.sentExchange)
                    compactField("Received", width: 180) {
                        TextField("Exchange", text: $appState.quickLogDraft.receivedExchange)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .focused($focusedField, equals: .exchange)
                    }
                    if appState.quickLogAssessment.contestDuplicate {
                        Label("Dupe", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.22)))
        }
    }

    private var contactFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Callbook Details", systemImage: "person.text.rectangle")
                    .font(.headline)
                Spacer()
                if let lookup = appState.quickLogLookup, !lookup.sources.isEmpty {
                    Text(lookup.sources.joined(separator: " + "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    labeledField("Name", text: $appState.quickLogDraft.name)
                    labeledField("QTH", text: $appState.quickLogDraft.qth)
                    labeledField("Grid", text: $appState.quickLogDraft.grid)
                }
                GridRow {
                    labeledField("Country", text: $appState.quickLogDraft.country)
                    labeledField("DXCC", text: $appState.quickLogDraft.dxcc)
                    HStack(spacing: 8) {
                        labeledField("CQ", text: $appState.quickLogDraft.cqZone)
                        labeledField("ITU", text: $appState.quickLogDraft.ituZone)
                    }
                }
            }
        }
    }

    private var notesAndSave: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("QSO notes", text: $appState.quickLogDraft.comment)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .comment)

            HStack(spacing: 10) {
                Button {
                    attemptSave()
                } label: {
                    Label("Log QSO", systemImage: "checkmark.circle.fill")
                        .frame(minWidth: 105)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])

                Button {
                    appState.quickLogDraft.resetForNextQSO(keepingOperatingContext: true)
                    appState.quickLogLookup = nil
                    appState.refreshQuickLogAssessment()
                    focusedField = .callsign
                } label: {
                    Label("Clear", systemImage: "arrow.counterclockwise")
                }

                Spacer()

                Text(appState.quickLogStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Worked Before", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.headline)

            let assessment = appState.quickLogAssessment
            if appState.quickLogDraft.normalizedCallsign.isEmpty {
                ContentUnavailableView(
                    "Enter a Callsign",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("History and duplicate checks appear here.")
                )
            } else if assessment.isNewCallsign {
                statusBanner("New callsign", detail: "No previous QSO in this station log", icon: "sparkles", color: .blue)
            } else {
                metricRow("All QSOs", value: assessment.totalWorked, color: .primary)
                metricRow("Confirmed", value: assessment.confirmed, color: .green)
                metricRow("This band", value: assessment.sameBand, color: .blue)
                metricRow("Band + mode", value: assessment.sameBandMode, color: .purple)
                if let lastWorked = assessment.lastWorkedAt {
                    Divider()
                    Text("Last worked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lastWorked.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                }
                if assessment.hasRecentDuplicate {
                    statusBanner(
                        "Recent duplicate",
                        detail: "Same band and mode within 30 minutes",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
                if assessment.contestDuplicate {
                    statusBanner(
                        "Contest duplicate",
                        detail: "Already worked on this band and mode in the active session",
                        icon: "flag.checkered",
                        color: .orange
                    )
                }
            }

            Spacer()

            if let saved = appState.quickLogLastSaved {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LAST SAVED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(saved["CALL"])
                        .font(.system(.title3, design: .monospaced).weight(.bold))
                    Text("\(saved["BAND"]) · \(saved["MODE"]) · \(saved["TIME_ON"]) UTC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    @ViewBuilder
    private func compactField<Content: View>(_ title: String, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .leading)
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text).textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.bold))
                .frame(minWidth: 80, minHeight: 22, alignment: .leading)
        }
    }

    private func metricRow(_ title: String, value: Int, color: Color) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value.formatted())
                .font(.system(.body, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
        }
    }

    private func statusBanner(_ title: String, detail: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.25)))
    }

    private func moveAfterCallsign() {
        if appState.isValidOperatorCallsign(appState.quickLogDraft.normalizedCallsign) {
            focusedField = .frequency
        }
    }

    private func attemptSave() {
        if (appState.quickLogAssessment.hasRecentDuplicate || appState.quickLogAssessment.contestDuplicate), !duplicateWasAcknowledged {
            showDuplicateConfirmation = true
            return
        }
        save()
    }

    private func save() {
        do {
            _ = try appState.saveQuickLog()
            duplicateWasAcknowledged = false
            focusedField = .callsign
        } catch {
            appState.quickLogStatus = error.localizedDescription
            appState.playActivitySound(.failure)
        }
    }
}

private struct DXClusterPanel: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var client: DXClusterClient
    @AppStorage("dxClusterHost") private var host = "dxc.nc7j.com"
    @AppStorage("dxClusterPort") private var port = 7373
    @AppStorage("dxClusterNeededAlerts") private var neededAlerts = true
    @AppStorage("dxClusterWatchlist") private var watchlistText = ""
    @State private var showConnectionSettings = false
    @State private var bandFilter = "All"
    @State private var needFilter = "All"
    @State private var searchText = ""
    @State private var workIndex = LogWorkIndex(records: [])
    @State private var alertedSpotIDs: Set<String> = []

    private var watchlist: Set<String> {
        Set(watchlistText
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
            .map { $0.uppercased() })
    }

    private var filteredSpots: [DXSpot] {
        let cutoff = Date().addingTimeInterval(-60 * 60)
        return client.spots.filter { spot in
            guard spot.lastSeenAt >= cutoff else { return false }
            if bandFilter != "All", spot.band != bandFilter { return false }
            let status = workIndex.status(for: spot.callsign, band: spot.band)
            if needFilter == "Needed", status != .newCallsign, status != .newBand { return false }
            if needFilter == "Unconfirmed", status == .confirmed { return false }
            if needFilter == "Watchlist", !watchlist.contains(spot.callsign) { return false }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return spot.callsign.lowercased().contains(query) ||
                    spot.comment.lowercased().contains(query) ||
                    spot.spotter.lowercased().contains(query)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            clusterToolbar
            Divider()
            columnHeader
            Divider()

            if client.spots.isEmpty {
                ContentUnavailableView(
                    client.state.isConnected ? "Waiting for DX Spots" : "DX Cluster Offline",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text(client.lastMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSpots.isEmpty {
                ContentUnavailableView.search(text: searchText.isEmpty ? needFilter : searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSpots) { spot in
                            spotRow(spot)
                            Divider()
                        }
                    }
                }
            }

            Divider()
            HStack {
                Label(client.lastMessage, systemImage: client.state.isConnected ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(client.state.isConnected ? .green : .secondary)
                Spacer()
                Text("Showing \(filteredSpots.count) of \(client.spots.count) · \(client.receivedSpotCount) received")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .onAppear { rebuildWorkIndex() }
        .onChange(of: appState.qsoRecords.count) { _, _ in rebuildWorkIndex() }
        .onChange(of: appState.totalConfirmedCount) { _, _ in rebuildWorkIndex() }
        .onChange(of: client.spots.first?.id) { _, _ in processNewestSpotForAlert() }
        .popover(isPresented: $showConnectionSettings, arrowEdge: .top) {
            connectionSettings
                .padding(16)
                .frame(width: 360)
        }
    }

    private var clusterToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                connectionButton
                settingsButton
                bandPicker
                needPicker.frame(width: 360)
                searchControl
                Spacer()
                clearButton
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    connectionButton
                    settingsButton
                    bandPicker
                    Spacer()
                    clearButton
                }
                HStack(spacing: 10) {
                    needPicker.frame(maxWidth: 360)
                    searchControl.frame(minWidth: 180)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var connectionButton: some View {
        Button {
            if client.state.isConnected {
                client.disconnect()
            } else {
                client.connect(host: host, port: port, callsign: appState.currentStationCallsign)
            }
        } label: {
            Label(client.state.isConnected ? "Disconnect" : "Connect", systemImage: client.state.isConnected ? "stop.fill" : "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(client.state.isConnected ? .red : .accentColor)
    }

    private var settingsButton: some View {
        Button { showConnectionSettings.toggle() } label: { Image(systemName: "gearshape") }
            .help("Cluster connection settings")
    }

    private var bandPicker: some View {
        Picker("Band", selection: $bandFilter) {
            Text("All Bands").tag("All")
            ForEach(AmateurBandPlan.commonBands, id: \.self) { Text($0).tag($0) }
        }
        .frame(width: 135)
    }

    private var needPicker: some View {
        Picker("", selection: $needFilter) {
            Text("All Spots").tag("All")
            Text("Needed").tag("Needed")
            Text("Unconfirmed").tag("Unconfirmed")
            Text("Watchlist").tag("Watchlist")
        }
        .pickerStyle(.segmented)
    }

    private var searchControl: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Call, spotter, or comment", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
    }

    private var clearButton: some View {
        Button { client.clearSpots() } label: { Image(systemName: "trash") }
            .help("Clear received spots")
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("UTC").frame(width: 54, alignment: .leading)
            Text("FREQUENCY").frame(width: 92, alignment: .trailing)
            Text("CALL").frame(width: 105, alignment: .leading)
            Text("BAND").frame(width: 52, alignment: .center)
            Text("MODE").frame(width: 58, alignment: .center)
            Text("STATUS").frame(width: 92, alignment: .leading)
            Text("COMMENT").frame(maxWidth: .infinity, alignment: .leading)
            Text("SPOTTER").frame(width: 86, alignment: .leading)
            Color.clear.frame(width: 76)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func spotRow(_ spot: DXSpot) -> some View {
        let status = workIndex.status(for: spot.callsign, band: spot.band)
        return HStack(spacing: 12) {
            Text(clusterUTCTimeFormatter.string(from: spot.spottedAt))
                .frame(width: 54, alignment: .leading)
            Text(String(format: "%.1f", spot.frequencyKHz))
                .font(.system(.body, design: .monospaced))
                .frame(width: 92, alignment: .trailing)
            HStack(spacing: 4) {
                Button {
                    toggleWatch(spot.callsign)
                } label: {
                    Image(systemName: watchlist.contains(spot.callsign) ? "star.fill" : "star")
                        .foregroundStyle(watchlist.contains(spot.callsign) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                Text(spot.callsign)
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .lineLimit(1)
            }
            .frame(width: 105, alignment: .leading)
            Text(spot.band.isEmpty ? "-" : spot.band).frame(width: 52)
            Text(spot.submode.isEmpty ? spot.mode : spot.submode).frame(width: 58)
            Text(status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor(status))
                .frame(width: 92, alignment: .leading)
            Text(spot.comment.isEmpty ? "-" : spot.comment)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(spot.spotter)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 86, alignment: .leading)
            HStack(spacing: 6) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AmateurBandPlan.formattedMHz(spot.frequencyMHz), forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy frequency")
                Button {
                    appState.prepareQuickLog(from: spot)
                } label: { Image(systemName: "plus.circle.fill") }
                    .help("Prepare this QSO in Quick Log")
            }
            .buttonStyle(.borderless)
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(rowBackground(status))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { appState.prepareQuickLog(from: spot) }
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("DX Cluster Connection", systemImage: "network")
                .font(.headline)
            TextField("Host", text: $host).textFieldStyle(.roundedBorder)
            HStack {
                Text("TCP Port")
                Spacer()
                TextField("7373", value: $port, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
            }
            Toggle("Sound for needed or watched spots", isOn: $neededAlerts)
            VStack(alignment: .leading, spacing: 4) {
                Text("Watchlist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("K1ABC, EP2XYZ", text: $watchlistText)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Done") { showConnectionSettings = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func rebuildWorkIndex() {
        workIndex = appState.workIndex()
    }

    private func statusColor(_ status: DXSpotNeedStatus) -> Color {
        switch status {
        case .newCallsign: return .orange
        case .newBand: return .blue
        case .worked: return .secondary
        case .confirmed: return .green
        }
    }

    private func rowBackground(_ status: DXSpotNeedStatus) -> Color {
        switch status {
        case .newCallsign: return Color.orange.opacity(0.055)
        case .newBand: return Color.blue.opacity(0.045)
        default: return .clear
        }
    }

    private func toggleWatch(_ callsign: String) {
        var items = watchlist
        if items.contains(callsign) { items.remove(callsign) } else { items.insert(callsign) }
        watchlistText = items.sorted().joined(separator: ", ")
    }

    private func processNewestSpotForAlert() {
        guard neededAlerts, let spot = client.spots.first, !alertedSpotIDs.contains(spot.id) else { return }
        alertedSpotIDs.insert(spot.id)
        if alertedSpotIDs.count > 500 { alertedSpotIDs = Set(client.spots.prefix(300).map(\.id)) }
        let status = workIndex.status(for: spot.callsign, band: spot.band)
        if watchlist.contains(spot.callsign) || status == .newCallsign || status == .newBand {
            appState.playActivitySound(.notice)
        }
    }
}

private struct SyncCenterPanel: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("unifiedSyncEnabled") private var automaticSync = false
    @AppStorage("unifiedSyncIntervalMinutes") private var intervalMinutes = 30.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Synchronization Health")
                            .font(.title2.weight(.bold))
                        Text("One place for incoming logs and online confirmation status")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if appState.isUnifiedSyncRunning { ProgressView().controlSize(.small) }
                    Button {
                        appState.runUnifiedSync()
                    } label: {
                        Label("Sync All", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isUnifiedSyncRunning)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(appState.syncServiceStatuses) { status in
                        syncCard(status)
                    }
                }

                Divider()

                HStack(spacing: 16) {
                    Toggle("Automatic sync", isOn: $automaticSync)
                        .onChange(of: automaticSync) { _, _ in appState.configureUnifiedSyncSchedule() }
                    if automaticSync {
                        Stepper(
                            "Every \(Int(intervalMinutes)) minutes",
                            value: $intervalMinutes,
                            in: 5...240,
                            step: 5
                        )
                        .onChange(of: intervalMinutes) { _, _ in appState.configureUnifiedSyncSchedule() }
                        .frame(width: 220)
                    }
                    Spacer()
                    Button {
                        appState.refreshSyncServiceConfiguration()
                    } label: {
                        Label("Refresh Status", systemImage: "arrow.clockwise")
                    }
                }

                if !appState.syncHistory.isEmpty {
                    Divider()
                    Text("Recent Activity")
                        .font(.headline)
                    VStack(spacing: 0) {
                        ForEach(appState.syncHistory.prefix(20)) { entry in
                            HStack(spacing: 10) {
                                Image(systemName: entry.source.systemImage)
                                    .foregroundStyle(stateColor(entry.state))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.source.title).fontWeight(.semibold)
                                    Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if entry.changedRecords > 0 {
                                    Text("\(entry.changedRecords) changed")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.completedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 130, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
            .padding(22)
        }
        .onAppear { appState.refreshSyncServiceConfiguration() }
    }

    private func syncCard(_ status: SyncServiceStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: status.source.systemImage)
                    .font(.title3)
                    .foregroundStyle(status.configured ? stateColor(status.state) : .secondary)
                Text(status.source.title).font(.headline)
                Spacer()
                Circle()
                    .fill(status.configured ? stateColor(status.state) : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
            Text(status.configured ? status.detail : "Not configured")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            HStack {
                if let date = status.lastSuccess {
                    Text("Last success \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("No successful run")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if status.state == .running {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        appState.runSync(status.source)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!status.configured || appState.isUnifiedSyncRunning)
                    .help("Sync \(status.source.title)")
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(stateColor(status.state).opacity(status.configured ? 0.28 : 0.12)))
    }

    private func stateColor(_ state: SyncRunState) -> Color {
        switch state {
        case .running: return .blue
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        case .idle: return .secondary
        }
    }
}
