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
            headerBar

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
                ContestCalendarPanel()
            case 10:
                ClubLogSpotsView()
            case 11:
                SixMeterWatchView()
            case 12:
                GlobeAndGridTrackerWorkspaceView()
            case 13:
                BandmapView()
            case 14:
                CWKeyerView()
                    .padding(20)
            case 15:
                ClubMembershipView()
            case 16:
                TCIControlView()
            case 17:
                ON4KSTView()
            case 18:
                WinKeyerView()
            case 19:
                QSLLabelDesignerView()
            case 20:
                DigitalCallRosterView()
            default:
                QuickLogPanel()
            }
        }
    }

    private struct DeskTabItem {
        let tag: Int
        let title: String
        let icon: String
    }

    private var deskTabs: [DeskTabItem] {
        [
            DeskTabItem(tag: 0, title: "Quick Log", icon: "plus.circle.fill"),
            DeskTabItem(tag: 20, title: "Call Roster", icon: "waveform.and.person.filled"),
            DeskTabItem(tag: 12, title: "Globe & Grids", icon: "globe.americas.fill"),
            DeskTabItem(tag: 13, title: "Bandmap", icon: "waveform.path.ecg.rectangle"),
            DeskTabItem(tag: 14, title: "CW Keyer", icon: "tuningfork"),
            DeskTabItem(tag: 18, title: "WinKeyer", icon: "cable.connector.horizontal"),
            DeskTabItem(tag: 17, title: "ON4KST Chat", icon: "bubble.left.and.bubble.right.fill"),
            DeskTabItem(tag: 19, title: "QSL Labels", icon: "printer.fill"),
            DeskTabItem(tag: 15, title: "Clubs", icon: "person.3.sequence.fill"),
            DeskTabItem(tag: 16, title: "TCI SDR", icon: "antenna.radiowaves.left.and.right"),
            DeskTabItem(tag: 1, title: "DX Cluster", icon: "dot.radiowaves.left.and.right"),
            DeskTabItem(tag: 10, title: "Club Log", icon: "person.3.fill"),
            DeskTabItem(tag: 2, title: "Sync Center", icon: "arrow.triangle.2.circlepath"),
            DeskTabItem(tag: 3, title: "Radio Bridge", icon: "wave.3.right.circle"),
            DeskTabItem(tag: 4, title: "Contest", icon: "flag.checkered"),
            DeskTabItem(tag: 5, title: "QSL", icon: "arrow.left.arrow.right.circle"),
            DeskTabItem(tag: 6, title: "Awards", icon: "medal"),
            DeskTabItem(tag: 7, title: "Portable", icon: "figure.hiking"),
            DeskTabItem(tag: 8, title: "Connect", icon: "network"),
            DeskTabItem(tag: 9, title: "Calendar", icon: "calendar"),
            DeskTabItem(tag: 11, title: "6m Band", icon: "bolt.badge.clock.fill")
        ]
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Station Callsign & Grid Badge (Fixed layout - Zero Overlap)
            stationBadge
                .fixedSize(horizontal: true, vertical: false)

            Divider()
                .frame(height: 20)

            // Scrollable / Responsive Tab Bar with Left/Right Overflow Indicators & Fast Menu
            ScrollViewReader { scrollProxy in
                HStack(spacing: 4) {
                    // Left Overflow Indicator / Scroll Left Button (•••)
                    Button {
                        scrollLeft(proxy: scrollProxy)
                    } label: {
                        HStack(spacing: 1.5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9.5, weight: .bold))
                            Image(systemName: "ellipsis")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Scroll left to previous Operator Desk panels")

                    // Scrollable Horizontal Tabs
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(deskTabs, id: \.tag) { tab in
                                Button {
                                    selectTab(tab.tag, proxy: scrollProxy)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: tab.icon)
                                        Text(tab.title)
                                    }
                                    .font(.system(size: 11.5, weight: appState.operatorDeskSection == tab.tag ? .bold : .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        appState.operatorDeskSection == tab.tag ?
                                            Color.accentColor.opacity(0.18) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(appState.operatorDeskSection == tab.tag ? Color.accentColor : Color.clear, lineWidth: 1.0)
                                    )
                                    .foregroundStyle(appState.operatorDeskSection == tab.tag ? Color.accentColor : Color.primary)
                                }
                                .buttonStyle(.plain)
                                .id(tab.tag)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onAppear {
                        scrollProxy.scrollTo(appState.operatorDeskSection, anchor: .center)
                    }
                    .onChange(of: appState.operatorDeskSection) { _, newSection in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scrollProxy.scrollTo(newSection, anchor: .center)
                        }
                    }

                    // Right Overflow Indicator / Scroll Right Button (•••)
                    Button {
                        scrollRight(proxy: scrollProxy)
                    } label: {
                        HStack(spacing: 1.5) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 8, weight: .bold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Scroll right to more Operator Desk panels")

                    // All Panels Fast Jump Menu (•••)
                    allPanelsMenu(proxy: scrollProxy)
                }
            }

            Spacer(minLength: 4)

            deskStatus
                .frame(maxWidth: 180, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func allPanelsMenu(proxy: ScrollViewProxy) -> some View {
        Menu {
            Section("📻 Live Operating") {
                Button { selectTab(0, proxy: proxy) } label: { Label("Quick Log", systemImage: "plus.circle.fill") }
                Button { selectTab(12, proxy: proxy) } label: { Label("Globe & Grids", systemImage: "globe.americas.fill") }
                Button { selectTab(13, proxy: proxy) } label: { Label("Bandmap", systemImage: "waveform.path.ecg.rectangle") }
                Button { selectTab(14, proxy: proxy) } label: { Label("CW Keyer", systemImage: "tuningfork") }
                Button { selectTab(18, proxy: proxy) } label: { Label("WinKeyer", systemImage: "cable.connector.horizontal") }
                Button { selectTab(17, proxy: proxy) } label: { Label("ON4KST Chat", systemImage: "bubble.left.and.bubble.right.fill") }
                Button { selectTab(16, proxy: proxy) } label: { Label("TCI SDR", systemImage: "antenna.radiowaves.left.and.right") }
                Button { selectTab(3, proxy: proxy) } label: { Label("Radio Bridge", systemImage: "wave.3.right.circle") }
            }
            Section("🌍 DX & Propagation") {
                Button { selectTab(11, proxy: proxy) } label: { Label("6m Magic Band", systemImage: "bolt.badge.clock.fill") }
                Button { selectTab(1, proxy: proxy) } label: { Label("DX Cluster", systemImage: "dot.radiowaves.left.and.right") }
                Button { selectTab(10, proxy: proxy) } label: { Label("Club Log Spots", systemImage: "person.3.fill") }
            }
            Section("🏆 Contests & Awards") {
                Button { selectTab(4, proxy: proxy) } label: { Label("Contest Mode", systemImage: "flag.checkered") }
                Button { selectTab(9, proxy: proxy) } label: { Label("Contest Calendar", systemImage: "calendar") }
                Button { selectTab(6, proxy: proxy) } label: { Label("Awards Center", systemImage: "medal") }
                Button { selectTab(15, proxy: proxy) } label: { Label("Club Memberships", systemImage: "person.3.sequence.fill") }
            }
            Section("🔄 QSL & Station Hub") {
                Button { selectTab(5, proxy: proxy) } label: { Label("QSL Hub", systemImage: "arrow.left.arrow.right.circle") }
                Button { selectTab(19, proxy: proxy) } label: { Label("QSL Label Designer", systemImage: "printer.fill") }
                Button { selectTab(2, proxy: proxy) } label: { Label("Sync Center", systemImage: "arrow.triangle.2.circlepath") }
                Button { selectTab(7, proxy: proxy) } label: { Label("Portable (POTA/SOTA)", systemImage: "figure.hiking") }
                Button { selectTab(8, proxy: proxy) } label: { Label("Connect & Companion", systemImage: "network") }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .bold))
                Text("Panels")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.25), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .help("Jump directly to any of the 20 Operator Desk panels")
    }

    private func selectTab(_ tag: Int, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.15)) {
            appState.operatorDeskSection = tag
            UserDefaults.standard.set(tag, forKey: "operatorDeskSection")
            proxy.scrollTo(tag, anchor: .center)
        }
    }

    private func scrollLeft(proxy: ScrollViewProxy) {
        guard let currentIdx = deskTabs.firstIndex(where: { $0.tag == appState.operatorDeskSection }) else { return }
        let targetIdx = max(0, currentIdx - 1)
        let targetTag = deskTabs[targetIdx].tag
        selectTab(targetTag, proxy: proxy)
    }

    private func scrollRight(proxy: ScrollViewProxy) {
        guard let currentIdx = deskTabs.firstIndex(where: { $0.tag == appState.operatorDeskSection }) else { return }
        let targetIdx = min(deskTabs.count - 1, currentIdx + 1)
        let targetTag = deskTabs[targetIdx].tag
        selectTab(targetTag, proxy: proxy)
    }

    private var stationBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.green)
            Text(appState.currentStationCallsign.isEmpty ? "NO CALL" : appState.currentStationCallsign)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.3), lineWidth: 1.0))
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
            (!appState.contestCalendarEntries.isEmpty, "\(appState.contestCalendarEntries.count) upcoming contests")
        case 11:
            (SixMeterPropagationEngine.shared.assessment.level != .quiet, SixMeterPropagationEngine.shared.assessment.summaryHeadline)
        case 13:
            (true, "\(BandmapEngine.shared.spots.count) live spots on \(BandmapEngine.shared.selectedBand)")
        case 14:
            (CWKeyerService.shared.isTransmitting, CWKeyerService.shared.isTransmitting ? "TX Morse Active" : "CW Keyer \(CWKeyerService.shared.wpm) WPM")
        case 15:
            (true, "\(ClubMembershipEngine.shared.totalMembersIndexed) club members indexed")
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
                .truncationMode(.tail)
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

    private enum Field: Hashable {
        case callsign, frequency, rstSent, rstReceived, exchange, sentSerial, receivedSerial, state, arrlSection, comment
    }
    private let modes = ["SSB", "CW", "DATA", "RTTY", "FM", "AM", "MFSK", "SSTV", "SAT"]

    private var isDupe: Bool {
        appState.quickLogAssessment.sameBandMode > 0 || appState.quickLogAssessment.contestDuplicate
    }

    private var dxccInfo: DXCCEntityInfo {
        DXCCDatabase.resolve(callsign: appState.quickLogDraft.normalizedCallsign)
    }

    private var homeCoordinate: GeoCoordinate? {
        if let profile = appState.activeStationProfile {
            if let lat = Double(profile.latitude), let lon = Double(profile.longitude), (lat != 0 || lon != 0) {
                return GeoCoordinate(latitude: lat, longitude: lon)
            }
            if !profile.grid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: profile.grid) {
                return box.center
            }
        }
        return nil
    }

    private var targetCoordinate: GeoCoordinate? {
        let grid = appState.quickLogDraft.grid.isEmpty ? (appState.quickLogLookup?.grid ?? "") : appState.quickLogDraft.grid
        if !grid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: grid) {
            return box.center
        }
        if let lookup = appState.quickLogLookup, let lat = Double(lookup.latitude), let lon = Double(lookup.longitude), (lat != 0 || lon != 0) {
            return GeoCoordinate(latitude: lat, longitude: lon)
        }
        return nil
    }

    private var beamInfo: (sp: Double, lp: Double, distKm: Double, distMi: Double)? {
        guard let home = homeCoordinate, let target = targetCoordinate else { return nil }
        let sp = GeodesicMath.initialBearing(from: home, to: target)
        let lp = GeodesicMath.longPathBearing(from: home, to: target)
        let km = GeodesicMath.distanceKm(from: home, to: target)
        let mi = km * GeodesicMath.kmToMiles
        return (sp, lp, km, mi)
    }

    private var dxSolarState: SolarEphemeris.IlluminationState? {
        guard let target = targetCoordinate else { return nil }
        return SolarEphemeris.illuminationState(for: target)
    }

    private var qsoDurationString: String {
        let end = appState.quickLogDraft.endedAt >= appState.quickLogDraft.startedAt ? appState.quickLogDraft.endedAt : Date()
        let diff = max(0, Int(end.timeIntervalSince(appState.quickLogDraft.startedAt)))
        let mins = diff / 60
        let secs = diff % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 960 {
                HSplitView {
                    ScrollView {
                        entryFields
                            .padding(16)
                    }
                    .frame(minWidth: 580)

                    historyPanel
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 440)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        entryFields
                            .padding(16)
                        Divider()
                        historyPanel
                            .frame(minHeight: 320)
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

            // Spacebar in callsign triggers instant lookup and advances to RST or Exchange (N1MM standard)
            if newValue.hasSuffix(" ") {
                let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                appState.quickLogDraft.callsign = clean
                if appState.isValidOperatorCallsign(clean) {
                    Task { @MainActor in
                        await appState.lookupQuickLogCallsign(clean)
                    }
                    if appState.currentContestSession?.isActive == true {
                        focusedField = .exchange
                    } else {
                        focusedField = .rstSent
                    }
                    return
                }
            }

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
        VStack(alignment: .leading, spacing: 14) {
            quickEntryHeader
            Divider()
            operatingFields
            contestFields
            contactFields
            portableFields
            notesAndStatus
            Divider()
            recentQSOsTable
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dupeAlertBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("⚠️ DUPE ALERT: Already worked on \(appState.quickLogDraft.band) \(appState.quickLogDraft.mode)")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white)
                if let last = appState.quickLogAssessment.lastWorkedAt {
                    Text("Previous contact: \(last.formatted(date: .abbreviated, time: .shortened)) UTC")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            Spacer()
            Text("Esc to Wipe")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red, lineWidth: 1.5))
    }

    private var quickEntryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDupe {
                dupeAlertBanner
            }

            HStack(alignment: .bottom, spacing: 12) {
                // CALLSIGN
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("CALLSIGN")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        if !appState.quickLogDraft.normalizedCallsign.isEmpty {
                            Text(dxccInfo.flagEmoji)
                                .font(.system(size: 12))
                            Text(dxccInfo.entityName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(spacing: 6) {
                        TextField("DX Callsign (Space to advance)", text: $appState.quickLogDraft.callsign)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .focused($focusedField, equals: .callsign)
                            .onSubmit { moveAfterCallsign() }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isDupe ? Color.red : Color.clear, lineWidth: 2)
                            )
                            .frame(minWidth: 230)

                        if appState.isLookingUpQuickLogCallsign {
                            ProgressView().controlSize(.small)
                        }
                    }

                    let matches = ClubMembershipEngine.shared.lookupMemberships(for: appState.quickLogDraft.callsign)
                    if !matches.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(matches) { match in
                                Button {
                                    appState.quickLogDraft.receivedExchange = match.memberNumber
                                    appState.quickLogDraft.comment = "\(match.club.rawValue) #\(match.memberNumber)"
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: match.club.icon).font(.system(size: 9))
                                        Text("\(match.club.rawValue) #\(match.memberNumber)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(match.club.badgeColor.opacity(0.18), in: Capsule())
                                    .foregroundColor(match.club.badgeColor)
                                }
                                .buttonStyle(.plain)
                                .help("Click to insert \(match.club.rawValue) #\(match.memberNumber) into exchange")
                            }
                        }
                    }

                    // Super Check Partial (Master.scp) Matches
                    let scpMatches = SuperCheckPartialEngine.shared.findMatches(for: appState.quickLogDraft.callsign, maxResults: 5)
                    if !scpMatches.isEmpty && !appState.quickLogDraft.callsign.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                            Text("SCP:")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)

                            ForEach(scpMatches) { match in
                                Button {
                                    appState.quickLogDraft.callsign = match.callsign
                                } label: {
                                    Text(match.callsign)
                                        .font(.system(size: 10, weight: match.isExact ? .bold : .medium, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(match.isExact ? Color.green.opacity(0.18) : Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                        .foregroundColor(match.isExact ? .green : .blue)
                                }
                                .buttonStyle(.plain)
                                .help("Click to select \(match.callsign)")
                            }
                        }
                    }
                }

                // START UTC
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        Text("START UTC")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Button {
                            appState.quickLogDraft.startedAt = Date()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .help("Set start time to now")
                    }
                    DatePicker("", selection: $appState.quickLogDraft.startedAt, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                // END UTC
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        Text("END UTC")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Button {
                            appState.quickLogDraft.endedAt = Date()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 9))
                        }
                        .buttonStyle(.plain)
                        .help("Set end time to now")
                    }
                    DatePicker("", selection: $appState.quickLogDraft.endedAt, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                // LIVE DURATION BADGE
                VStack(alignment: .leading, spacing: 4) {
                    Text("DURATION")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 10))
                        Text(qsoDurationString)
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Color.accentColor)
                }

                Spacer()

                // LOG & CLEAR ACTION BUTTONS
                HStack(spacing: 6) {
                    Button {
                        attemptSave()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Log (↵)")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])

                    Button {
                        wipeForm()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "eraser.line.dashed")
                            Text("Wipe")
                        }
                        .font(.system(size: 12))
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
    }

    private var operatingFields: some View {
        HStack(alignment: .top, spacing: 10) {
            compactField("Frequency (MHz)", width: 125) {
                TextField("14.074", text: $appState.quickLogDraft.frequencyMHz)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($focusedField, equals: .frequency)
                    .onChange(of: appState.quickLogDraft.frequencyMHz) { _, value in
                        appState.quickLogDraft.applyFrequency(value)
                    }
            }

            compactField("Band", width: 85) {
                Picker("", selection: $appState.quickLogDraft.band) {
                    ForEach(AmateurBandPlan.commonBands, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }

            compactField("Mode", width: 95) {
                Picker("", selection: $appState.quickLogDraft.mode) {
                    ForEach(modes, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .onChange(of: appState.quickLogDraft.mode) { _, newValue in
                    appState.quickLogDraft.applyMode(newValue)
                }
            }

            let availableSubmodes = AmateurBandPlan.submodes(forMode: appState.quickLogDraft.mode)
            compactField("Submode", width: 100) {
                Menu {
                    Button("(None)") {
                        appState.quickLogDraft.applySubmode("")
                    }
                    ForEach(availableSubmodes.filter { !$0.isEmpty }, id: \.self) { sub in
                        Button(sub) {
                            appState.quickLogDraft.applySubmode(sub)
                        }
                    }
                } label: {
                    HStack {
                        Text(appState.quickLogDraft.submode.isEmpty ? "(None)" : appState.quickLogDraft.submode)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3)))
                }
                .buttonStyle(.plain)
            }

            compactField("RST Sent", width: 85) {
                TextField("59", text: $appState.quickLogDraft.rstSent)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($focusedField, equals: .rstSent)
            }

            compactField("RST Recv", width: 85) {
                TextField("59", text: $appState.quickLogDraft.rstReceived)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($focusedField, equals: .rstReceived)
            }
        }
    }

    @ViewBuilder
    private var contestFields: some View {
        let session = appState.currentContestSession
        let isContestActive = session?.isActive == true

        DisclosureGroup(isExpanded: .constant(true)) {
            HStack(spacing: 10) {
                if let activeSession = session, activeSession.isActive {
                    compactValue("Serial", value: String(ContestWorkspaceLogic.nextSerial(in: activeSession, records: appState.qsoRecords)))
                    compactValue("Sent Exch", value: activeSession.sentExchange.isEmpty ? "--" : activeSession.sentExchange)
                } else {
                    compactField("STX (Sent #)", width: 85) {
                        TextField("001", text: $appState.quickLogDraft.sentSerial)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .focused($focusedField, equals: .sentSerial)
                    }
                    compactField("SRX (Recv #)", width: 85) {
                        TextField("001", text: $appState.quickLogDraft.receivedSerial)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .focused($focusedField, equals: .receivedSerial)
                    }
                }

                compactField("Recv Exch", width: 120) {
                    TextField("599 001", text: $appState.quickLogDraft.receivedExchange)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: .exchange)
                }

                compactField("State / Prov", width: 85) {
                    TextField("CA", text: $appState.quickLogDraft.state)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: .state)
                }

                compactField("ARRL Sect", width: 85) {
                    TextField("SV", text: $appState.quickLogDraft.arrlSection)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: .arrlSection)
                }

                if isContestActive && appState.quickLogAssessment.contestDuplicate {
                    Label("DUPE", systemImage: "flag.checkered")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Label("Contest & Exchange", systemImage: "flag.checkered")
                    .font(.subheadline.weight(.semibold))
                if let activeSession = session, activeSession.isActive {
                    Text("• \(activeSession.displayName)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.2)))
    }

    private var contactFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Callbook & Location", systemImage: "person.text.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let lookup = appState.quickLogLookup, !lookup.sources.isEmpty {
                    Text("Source: " + lookup.sources.joined(separator: " + "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    labeledField("Name", text: $appState.quickLogDraft.name)
                    labeledField("QTH", text: $appState.quickLogDraft.qth)
                    labeledField("Grid", text: $appState.quickLogDraft.grid)
                }
                GridRow {
                    labeledField("Country", text: $appState.quickLogDraft.country)
                    labeledField("DXCC", text: $appState.quickLogDraft.dxcc)
                    HStack(spacing: 6) {
                        labeledField("CQ", text: $appState.quickLogDraft.cqZone)
                        labeledField("ITU", text: $appState.quickLogDraft.ituZone)
                    }
                }
            }
        }
    }

    private var portableFields: some View {
        DisclosureGroup(isExpanded: $showPortableFields) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Operating role", selection: $appState.quickLogDraft.portableRole) {
                    ForEach(PortableOperatingRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)

                Grid(horizontalSpacing: 10, verticalSpacing: 8) {
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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } label: {
            Label("Portable Activity (POTA / SOTA / IOTA)", systemImage: "figure.hiking")
                .font(.subheadline.weight(.semibold))
        }
        .padding(8)
        .background(Color.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.18)))
    }

    private var notesAndStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                labeledField("QSO Notes & Comments", text: $appState.quickLogDraft.comment)
                    .focused($focusedField, equals: .comment)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Status")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(appState.quickLogStatus)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 140, alignment: .trailing)
            }
        }
    }

    private var recentQSOsTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Recent Logged QSOs (\(min(8, appState.qsoRecords.count)))", systemImage: "list.bullet.rectangle.portrait")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("Total in Log: \(appState.qsoRecords.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if appState.qsoRecords.isEmpty {
                Text("No QSOs logged yet. Enter details above and press ↵ to log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                let recents = Array(appState.qsoRecords.suffix(8).reversed())
                VStack(spacing: 2) {
                    // Table header
                    HStack(spacing: 8) {
                        Text("UTC").frame(width: 55, alignment: .leading)
                        Text("CALLSIGN").frame(width: 100, alignment: .leading)
                        Text("FREQ / BAND").frame(width: 85, alignment: .leading)
                        Text("MODE").frame(width: 55, alignment: .leading)
                        Text("RST (S/R)").frame(width: 75, alignment: .leading)
                        Text("EXCHANGE / INFO").frame(minWidth: 80, alignment: .leading)
                        Text("QSL").frame(width: 70, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                    ForEach(recents) { record in
                        recentQSOItem(record)
                    }
                }
            }
        }
    }

    private func recentQSOItem(_ record: QSORecordModel) -> some View {
        let call = record["CALL"]
        let flag = DXCCDatabase.resolve(callsign: call).flagEmoji
        let time = record["TIME_ON"].prefix(4)
        let formattedTime = time.count == 4 ? "\(time.prefix(2)):\(time.suffix(2))" : record["TIME_ON"]
        let freq = record["FREQ"].isEmpty ? record["BAND"] : "\(record["FREQ"]) MHz"
        let mode = record["SUBMODE"].isEmpty ? record["MODE"] : record["SUBMODE"]
        let rst = "\(record["RST_SENT"])/\(record["RST_RCVD"])"
        let exch = record["SRX_STRING"].isEmpty ? record["COMMENT"] : record["SRX_STRING"]

        let lotw = record["LOTW_QSL_RCVD"].uppercased() == "Y"
        let qrz = record["QRZLOG_QSL_RCVD"].uppercased() == "Y" || record["QRZCOM_QSL_RCVD"].uppercased() == "Y" || record["APP_QRZLOG_STATUS"].uppercased() == "CONFIRMED"
        let paper = record["QSL_RCVD"].uppercased() == "Y"

        return HStack(spacing: 8) {
            Text(formattedTime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 55, alignment: .leading)

            HStack(spacing: 4) {
                Text(flag)
                    .font(.system(size: 11))
                Text(call)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
            }
            .frame(width: 100, alignment: .leading)

            Text(freq)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 85, alignment: .leading)

            Text(mode)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(modeColor(mode))
                .frame(width: 55, alignment: .leading)

            Text(rst)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 75, alignment: .leading)

            Text(exch)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 80, alignment: .leading)

            HStack(spacing: 3) {
                if lotw {
                    Text("L")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 3)
                        .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.green)
                        .help("LoTW Confirmed")
                }
                if qrz {
                    Text("Q")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 3)
                        .background(Color.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.blue)
                        .help("QRZ Confirmed")
                }
                if paper {
                    Text("P")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 3)
                        .background(Color.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.orange)
                        .help("Paper Card Confirmed")
                }
                if !lotw && !qrz && !paper {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("DX & Station Intelligence", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)

            let assessment = appState.quickLogAssessment
            let call = appState.quickLogDraft.normalizedCallsign

            if call.isEmpty {
                ContentUnavailableView(
                    "Enter Callsign",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("DXCC entity, antenna headings, worked before history, and duplicate checks will appear here.")
                )
            } else {
                dxccSummaryCard

                if assessment.isNewCallsign {
                    statusBanner("All-Time New One (ATNO)", detail: "No previous QSO with this callsign in station log", icon: "sparkles", color: .blue)
                } else {
                    bandMatrixSection
                    previousQSOsSection

                    Divider()

                    metricRow("Total QSOs", value: assessment.totalWorked, color: .primary)
                    metricRow("Confirmed", value: assessment.confirmed, color: .green)
                    metricRow("This band (\(appState.quickLogDraft.band))", value: assessment.sameBand, color: .blue)
                    metricRow("Band + mode (\(appState.quickLogDraft.band) \(appState.quickLogDraft.mode))", value: assessment.sameBandMode, color: .purple)

                    if let lastWorked = assessment.lastWorkedAt {
                        HStack {
                            Text("Last Worked")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(lastWorked.formatted(date: .abbreviated, time: .shortened) + " UTC")
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                        }
                    }
                }
            }

            Spacer()

            if let saved = appState.quickLogLastSaved {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST LOGGED QSO")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(DXCCDatabase.resolve(callsign: saved["CALL"]).flagEmoji)
                        Text(saved["CALL"])
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        Spacer()
                        Text("\(saved["BAND"]) · \(saved["MODE"])")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var dxccSummaryCard: some View {
        let entity = dxccInfo
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entity.flagEmoji)
                    .font(.system(size: 26))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entity.entityName)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Text("\(entity.continent) · CQ \(entity.cqZone) · ITU \(entity.ituZone)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let solar = dxSolarState {
                    HStack(spacing: 3) {
                        Image(systemName: solar == .daylight ? "sun.max.fill" : (solar == .night ? "moon.stars.fill" : "sunset.fill"))
                            .font(.system(size: 10))
                        Text(solar.rawValue)
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(
                        (solar == .daylight ? Color.yellow : (solar == .night ? Color.indigo : Color.orange)).opacity(0.18),
                        in: Capsule()
                    )
                    .foregroundStyle(solar == .daylight ? Color.orange : (solar == .night ? Color.indigo : Color.orange))
                }
            }

            if let beam = beamInfo {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("BEAM HEADING")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%03.0f° SP / %03.0f° LP", beam.sp, beam.lp))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("DISTANCE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0f km (%.0f mi)", beam.distKm, beam.distMi))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
    }

    private var bandMatrixSection: some View {
        let callsign = appState.quickLogDraft.normalizedCallsign
        let commonBands = AmateurBandSettings.shared.orderedActiveBands()
        let matchingRecords = appState.qsoRecords.filter {
            $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == callsign
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text("BAND MATRIX")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(commonBands, id: \.self) { band in
                    let bandRecords = matchingRecords.filter { $0["BAND"].lowercased() == band.lowercased() }
                    let isConfirmed = bandRecords.contains(where: \.isConfirmed)
                    let isWorked = !bandRecords.isEmpty
                    bandBadge(band: band, isConfirmed: isConfirmed, isWorked: isWorked)
                }
            }
        }
    }

    private func bandBadge(band: String, isConfirmed: Bool, isWorked: Bool) -> some View {
        let tint: Color = isConfirmed ? .green : (isWorked ? .orange : .secondary)
        let bgOpacity = isConfirmed ? 0.18 : (isWorked ? 0.18 : 0.06)
        let borderOpacity = isConfirmed ? 0.4 : (isWorked ? 0.4 : 0.15)

        return HStack(spacing: 2) {
            Text(band)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            if isConfirmed {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
            } else if isWorked {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(tint.opacity(bgOpacity), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(tint.opacity(borderOpacity), lineWidth: 1))
        .foregroundStyle(tint)
    }

    private var previousQSOsSection: some View {
        let callsign = appState.quickLogDraft.normalizedCallsign
        let matches = appState.qsoRecords.filter {
            $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == callsign
        }

        return Group {
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PREVIOUS QSOs (\(matches.count))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 3) {
                        ForEach(Array(matches.suffix(5).reversed())) { rec in
                            HStack(spacing: 4) {
                                Text(rec["QSO_DATE"].prefix(8))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(rec["BAND"])
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                Text(rec["MODE"])
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(modeColor(rec["MODE"]))
                                Spacer()
                                Text("\(rec["RST_SENT"])/\(rec["RST_RCVD"])")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if rec.isConfirmed {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.green)
                                        .help("Confirmed")
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
    }

    private func modeColor(_ mode: String) -> Color {
        switch mode.uppercased() {
        case "CW": return .green
        case "SSB", "USB", "LSB": return .blue
        case "DATA", "DIGI", "FT8", "FT4", "JS8", "MFSK", "RTTY": return .purple
        case "FM", "AM": return .orange
        default: return .secondary
        }
    }

    @ViewBuilder
    private func compactField<Content: View>(_ title: String, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .leading)
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            TextField(title, text: text).textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.bold))
                .frame(minWidth: 70, minHeight: 22, alignment: .leading)
        }
    }

    private func metricRow(_ title: String, value: Int, color: Color) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary).font(.caption)
            Spacer()
            Text(value.formatted())
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
        }
    }

    private func statusBanner(_ title: String, detail: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.25)))
    }

    private func moveAfterCallsign() {
        let clean = appState.quickLogDraft.normalizedCallsign
        if appState.isValidOperatorCallsign(clean) {
            if appState.currentContestSession?.isActive == true {
                focusedField = .exchange
            } else {
                focusedField = .rstSent
            }
        }
    }

    private func wipeForm() {
        appState.quickLogDraft.resetForNextQSO(keepingOperatingContext: true)
        appState.quickLogDraft.startedAt = Date()
        appState.quickLogDraft.endedAt = Date()
        appState.quickLogLookup = nil
        appState.refreshQuickLogAssessment()
        focusedField = .callsign
        appState.quickLogStatus = "Cleared"
    }

    private func attemptSave() {
        if isDupe, !duplicateWasAcknowledged {
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

                // MARK: - Wavelog & Cloudlog Server Card
                HStack(spacing: 16) {
                    Image(systemName: "cloud.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Wavelog / Cloudlog Server")
                                .font(.headline)
                            Text(WavelogSyncEngine.shared.isConfigured ? "Connected" : "Not configured")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(WavelogSyncEngine.shared.isConfigured ? Color.green.opacity(0.18) : Color.secondary.opacity(0.18), in: Capsule())
                                .foregroundColor(WavelogSyncEngine.shared.isConfigured ? .green : .secondary)
                        }

                        Text(WavelogSyncEngine.shared.lastStatusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            await WavelogSyncEngine.shared.performFullSync(appState: appState)
                        }
                    } label: {
                        Label("Sync Wavelog", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(WavelogSyncEngine.shared.isSyncing || !WavelogSyncEngine.shared.isConfigured)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

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
