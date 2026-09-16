//
//  OperatorDeskView.swift
//  YAAM
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

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

            deskPanel(for: appState.operatorDeskSection)
        }
    }

    private func deskPanel(for section: Int) -> AnyView {
        switch section {
        case 1:
            return AnyView(DXClusterPanel(client: appState.dxClusterClient))
        case 2:
            return AnyView(SyncCenterPanel())
        case 3:
            return AnyView(RadioBridgePanel(rig: appState.rigControlClient, wsjtx: appState.wsjtxListener))
        case 4:
            return AnyView(ContestPanel())
        case 5:
            return AnyView(QSLHubPanel())
        case 6:
            return AnyView(AwardCenterPanel())
        case 7:
            return AnyView(PortableActivitiesPanel())
        case 8:
            return AnyView(ConnectivityPanel())
        case 9:
            return AnyView(ContestCalendarPanel())
        case 10:
            return AnyView(ClubLogSpotsView())
        case 11:
            return AnyView(SixMeterWatchView())
        case 12:
            return AnyView(GlobeAndGridTrackerWorkspaceView())
        case 13:
            return AnyView(BandmapView())
        case 14:
            return AnyView(CWKeyerView().padding(20))
        case 15:
            return AnyView(ClubMembershipView())
        case 16:
            return AnyView(TCIControlView())
        case 17:
            return AnyView(ON4KSTView())
        case 18:
            return AnyView(WinKeyerView())
        case 19:
            return AnyView(QSLLabelDesignerView())
        case 20:
            return AnyView(DigitalCallRosterView())
        case 21:
            return AnyView(DXNewsAndIntelligenceView())
        case 22:
            return AnyView(HamClockShackView(isEmbedded: true))
        case 23:
            return AnyView(DigitalMasterStationView())
        case 24:
            return AnyView(NetworkTransceiverEmulatorView(emulator: appState.transceiverEmulator))
        case 25:
            return AnyView(MultiRigFT8View(hub: appState.multiRigFT8Hub))
        default:
            return AnyView(QuickLogPanel())
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
            DeskTabItem(tag: 22, title: "Shack Clock", icon: "deskclock.fill"),
            DeskTabItem(tag: 20, title: "Call Roster", icon: "waveform.and.person.filled"),
            DeskTabItem(tag: 21, title: "DX News", icon: "newspaper.fill"),
            DeskTabItem(tag: 12, title: "Globe & Grids", icon: "globe.americas.fill"),
            DeskTabItem(tag: 13, title: "Bandmap", icon: "waveform.path.ecg.rectangle"),
            DeskTabItem(tag: 23, title: "Digital Suite", icon: "teletype"),
            DeskTabItem(tag: 24, title: "Transceiver Emulator", icon: "server.rack"),
            DeskTabItem(tag: 25, title: "Multi-Rig FT8", icon: "square.split.3x1.fill"),
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
                Button { selectTab(22, proxy: proxy) } label: { Label("Shack Clock", systemImage: "deskclock.fill") }
                Button { selectTab(20, proxy: proxy) } label: { Label("Call Roster", systemImage: "waveform.and.person.filled") }
                Button { selectTab(21, proxy: proxy) } label: { Label("DX News", systemImage: "newspaper.fill") }
                Button { selectTab(12, proxy: proxy) } label: { Label("Globe & Grids", systemImage: "globe.americas.fill") }
                Button { selectTab(13, proxy: proxy) } label: { Label("Bandmap", systemImage: "waveform.path.ecg.rectangle") }
                Button { selectTab(23, proxy: proxy) } label: { Label("Digital Suite", systemImage: "teletype") }
                Button { selectTab(24, proxy: proxy) } label: { Label("Transceiver Emulator", systemImage: "server.rack") }
                Button { selectTab(25, proxy: proxy) } label: { Label("Multi-Rig FT8", systemImage: "square.split.3x1.fill") }
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
        case 23:
            (appState.digitalModemEngine.isListening, appState.digitalModemEngine.isListening ? "Digital Suite Active" : "Digital Suite Standby")
        case 24:
            (appState.transceiverEmulator.isServerRunning, appState.transceiverEmulator.isServerRunning ? "Transceiver Emulator Online" : "Transceiver Emulator Standby")
        case 25:
            (appState.multiRigFT8Hub.slots.contains { $0.isMonitoring }, "Multi-Rig FT8 Cluster (\(appState.multiRigFT8Hub.slots.count) Rigs)")
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

// MARK: - Modern High-Density Recent QSO Row
private struct RecentQSORowView: View {
    let record: QSORecordModel
    let isEven: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        let call = record["CALL"]
        let dxcc = DXCCDatabase.resolve(callsign: call)
        let flag = dxcc.flagEmoji
        let entityName = dxcc.entityName
        let time = record["TIME_ON"].prefix(4)
        let formattedTime = time.count == 4 ? "\(time.prefix(2)):\(time.suffix(2))" : record["TIME_ON"]
        let freqInfo = QSOMetadataFormatter.formatFrequency(freqRaw: record["FREQ"], bandRaw: record["BAND"])
        let mode = record["SUBMODE"].isEmpty ? record["MODE"] : record["SUBMODE"]
        let rst = "\(record["RST_SENT"])/\(record["RST_RCVD"])"
        let parsedMeta = QSOMetadataFormatter.parse(record: record)

        let lotw = record["LOTW_QSL_RCVD"].uppercased() == "Y"
        let qrz = record["QRZLOG_QSL_RCVD"].uppercased() == "Y" || record["QRZCOM_QSL_RCVD"].uppercased() == "Y" || record["APP_QRZLOG_STATUS"].uppercased() == "CONFIRMED"
        let paper = record["QSL_RCVD"].uppercased() == "Y"
        let eqsl = record["EQSL_QSL_RCVD"].uppercased() == "Y"

        HStack(spacing: 8) {
            // TIME (UTC)
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                Text(formattedTime)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .frame(width: 68, alignment: .leading)

            // CALLSIGN & DXCC
            HStack(spacing: 4) {
                Text(flag)
                    .font(.system(size: 12))
                Text(call)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .lineLimit(1)
            }
            .frame(width: 105, alignment: .leading)
            .help("\(call) — \(entityName)")

            // BAND & FREQUENCY
            HStack(spacing: 4) {
                Text(freqInfo.band)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(QSOMetadataFormatter.bandColor(freqInfo.band).opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(QSOMetadataFormatter.bandColor(freqInfo.band))

                if !freqInfo.freq.isEmpty {
                    Text(freqInfo.freq)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 105, alignment: .leading)

            // MODE
            Text(mode)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(modeColor(mode).opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(modeColor(mode))
                .frame(width: 48, alignment: .leading)

            // RST (S/R)
            Text(rst)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)

            // INFO & EXCHANGE (Smart Parsed Badges)
            HStack(spacing: 4) {
                if let iota = parsedMeta.iota {
                    badge(text: "🏝️ \(iota)", color: .cyan)
                }
                if let state = parsedMeta.state {
                    badge(text: "📍 \(state)", color: .blue)
                }
                if let grid = parsedMeta.grid {
                    badge(text: "🌐 \(grid)", color: .teal)
                }
                if let pota = parsedMeta.pota {
                    badge(text: "🌲 \(pota)", color: .green)
                }
                if let sota = parsedMeta.sota {
                    badge(text: "⛰️ \(sota)", color: .orange)
                }
                if let exch = parsedMeta.contestExchange {
                    badge(text: "🔢 \(exch)", color: .indigo)
                }
                if !parsedMeta.cleanComment.isEmpty {
                    Text(parsedMeta.cleanComment)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if !parsedMeta.hasBadges {
                    if !record["QTH"].isEmpty {
                        Text(record["QTH"])
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if !record["NAME"].isEmpty {
                        Text(record["NAME"])
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            .clipped()

            // QSL STATUS PILLS
            HStack(spacing: 3) {
                if lotw {
                    qslPill(text: "LoTW", color: .green)
                }
                if qrz {
                    qslPill(text: "QRZ", color: .blue)
                }
                if paper {
                    qslPill(text: "Card", color: .orange)
                }
                if eqsl {
                    qslPill(text: "eQSL", color: .purple)
                }
                if !lotw && !qrz && !paper && !eqsl {
                    Text("Pending")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                }
            }
            .frame(width: 85, alignment: .trailing)

            // ACTION BUTTON
            HStack(spacing: 2) {
                Button {
                    onLoad()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9.5))
                        .foregroundStyle(isHovered ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Load into Quick Log form")
            }
            .frame(width: 24, alignment: .center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHovered
                ? Color.accentColor.opacity(0.12)
                : (isEven ? Color(nsColor: .controlBackgroundColor).opacity(0.65) : Color.clear),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            onLoad()
        }
        .contextMenu {
            Button {
                onLoad()
            } label: {
                Label("Load into Quick Log", systemImage: "square.and.pencil")
            }

            Button {
                if let url = URL(string: "https://www.qrz.com/db/\(call)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Lookup on QRZ.com", systemImage: "safari")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(call, forType: .string)
            } label: {
                Label("Copy Callsign", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete QSO...", systemImage: "trash")
            }
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(color)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func qslPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(color)
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
}

private struct QuickLogPanel: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var focusedField: Field?
    @State private var lookupTask: Task<Void, Never>?
    @State private var showDuplicateConfirmation = false
    @State private var duplicateWasAcknowledged = false
    @State private var showPortableFields = false
    @State private var showContestFields = false
    @State private var showContestBandmapHUD = false
    @State private var showContestRateMatrixHUD = false
    @State private var recentLimit: Int = 10
    @State private var recentSearchText: String = ""
    @State private var recordToDelete: QSORecordModel? = nil
    @State private var showDeleteConfirm = false
    @State private var currentTime = Date()
    private let liveClockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @ObservedObject private var esm = CWESMEngine.shared
    @State private var lastESMExecutionTime: Date = Date.distantPast

    private var currentUTCTimeString: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: currentTime)
    }

    private var currentUTCDateString: String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: currentTime)
    }

    private enum Field: Hashable {
        case callsign, frequency, rstSent, rstReceived, exchange, sentSerial, receivedSerial, state, arrlSection, comment
    }
    private let modes = ["FT8", "SSB", "CW", "FT4", "RTTY", "JS8", "DATA", "FM", "AM", "MFSK", "SSTV", "SAT"]

    private var esmCurrentAction: CWESMAction {
        esm.determineAction(
            callsign: appState.quickLogDraft.callsign,
            receivedExchange: appState.quickLogDraft.receivedExchange,
            receivedSerial: appState.quickLogDraft.receivedSerial
        )
    }

    private var esmButtonTitle: String {
        guard esm.isEnabled else { return "Log (↵)" }
        return esmCurrentAction.buttonTitle
    }

    private var esmButtonColor: Color {
        guard esm.isEnabled else { return .accentColor }
        return esmCurrentAction.badgeColor
    }

    private var isDupe: Bool {
        appState.quickLogAssessment.sameBandMode > 0 || appState.quickLogAssessment.contestDuplicate
    }

    private var dxccInfo: DXCCEntityInfo {
        DXCCDatabase.resolve(callsign: appState.quickLogDraft.normalizedCallsign)
    }

    private var homeCoordinate: GeoCoordinate? {
        appState.effectiveStationCoordinate
    }

    private func updateCallIntelligence() {
        CallIntelligenceEngine.shared.update(
            callsign: appState.quickLogDraft.callsign,
            band: appState.quickLogDraft.band,
            mode: appState.quickLogDraft.mode,
            records: appState.qsoRecords,
            homeCoordinate: appState.effectiveStationCoordinate,
            lookupResult: appState.quickLogLookup,
            clusterSpots: appState.dxClusterClient.spots
        )
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
            updateCallIntelligence()
            showContestFields = (appState.currentContestSession?.isActive == true)
            // Wire CWKeyerService to the shared RigControlClient instance
            CWKeyerService.shared.rigControlClientRef = appState.rigControlClient
        }
        .onReceive(liveClockTimer) { currentTime = $0 }
        .onChange(of: appState.quickLogDraft.callsign) { _, newValue in
            duplicateWasAcknowledged = false
            lookupTask?.cancel()
            esm.onCallsignChanged(newValue)

            // Spacebar in callsign triggers instant lookup and advances to RST or Exchange (N1MM standard)
            if newValue.hasSuffix(" ") {
                let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                appState.quickLogDraft.callsign = clean
                if let hist = CallHistoryLookupEngine.shared.lookup(callsign: clean) {
                    prefillCallHistory(hist)
                }
                if appState.isValidOperatorCallsign(clean) {
                    updateCallIntelligence()
                    Task { @MainActor in
                        await appState.lookupQuickLogCallsign(clean)
                        updateCallIntelligence()
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
            updateCallIntelligence()
            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard appState.isValidOperatorCallsign(normalized) else {
                appState.quickLogStatus = normalized.isEmpty ? "Ready" : "Waiting for a complete callsign"
                return
            }
            lookupTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await appState.lookupQuickLogCallsign(normalized)
                updateCallIntelligence()
            }
        }
        .onChange(of: appState.quickLogDraft.band) { _, _ in
            duplicateWasAcknowledged = false
            appState.refreshQuickLogAssessment()
            updateCallIntelligence()
        }
        .onChange(of: appState.quickLogDraft.mode) { _, _ in
            duplicateWasAcknowledged = false
            appState.refreshQuickLogAssessment()
            updateCallIntelligence()
        }
        .onChange(of: appState.quickLogLookup) { _, _ in
            updateCallIntelligence()
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

            if showContestRateMatrixHUD {
                ContestRateMatrixHUDView(activeBand: appState.quickLogDraft.band)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            }

            if showContestBandmapHUD {
                ContestBandmapHUDView(
                    activeBand: appState.quickLogDraft.band,
                    activeMode: appState.quickLogDraft.mode,
                    currentVFOFrequencyMHz: Double(appState.quickLogDraft.frequencyMHz) ?? 14.025
                ) { spot in
                    if let hist = CallHistoryLookupEngine.shared.lookup(callsign: spot.callsign) {
                        prefillCallHistory(hist)
                    }
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            }

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

            esmContestToolbar

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
                            Text("(\(dxccInfo.continent))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
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

                    // Super Check Partial (SCP) Live Contest Autocomplete HUD
                    SuperCheckPartialHUDView(
                        targetCallsign: $appState.quickLogDraft.callsign,
                        activeBand: appState.quickLogDraft.band,
                        activeMode: appState.quickLogDraft.mode,
                        qsoRecords: appState.qsoRecords
                    ) { selectedCall in
                        appState.quickLogDraft.callsign = selectedCall
                        if let hist = CallHistoryLookupEngine.shared.lookup(callsign: selectedCall) {
                            prefillCallHistory(hist)
                        }
                        moveAfterCallsign()
                    }

                    // Call History Predictive Exchange Pre-fill Banner
                    let cleanCall = appState.quickLogDraft.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if cleanCall.count >= 2, let hist = CallHistoryLookupEngine.shared.lookup(callsign: cleanCall) {
                        HStack(spacing: 6) {
                            Image(systemName: "book.pages.fill")
                                .font(.system(size: 8.5))
                                .foregroundColor(.indigo)
                            Text("HIST:")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(hist.previewSummary)
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)

                            Spacer()

                            Button {
                                prefillCallHistory(hist)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.down.doc.fill")
                                        .font(.system(size: 7))
                                    Text("Pre-Fill (␣)")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                                .foregroundColor(.indigo)
                            }
                            .buttonStyle(.plain)
                            .help("Click or press Spacebar to pre-fill Name, State, Zone, and Exchange from contest history")
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.indigo.opacity(0.3), lineWidth: 0.8))
                    }
                }

                // LIVE UTC CLOCK
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIVE UTC")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(currentUTCTimeString)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.green)
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
                        if esm.isEnabled {
                            handleESMAction()
                        } else {
                            attemptSave()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: esm.isEnabled ? "bolt.fill" : "checkmark.circle.fill")
                            Text(esmButtonTitle)
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(esmButtonColor)
                    .keyboardShortcut(.return, modifiers: [])

                    Button {
                        handleEscapeKey()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: (CWKeyerService.shared.isTransmitting || CWKeyerService.shared.isAutoCQActive) ? "stop.fill" : "eraser.line.dashed")
                            Text((CWKeyerService.shared.isTransmitting || CWKeyerService.shared.isAutoCQActive) ? "Stop (Esc)" : "Wipe")
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
    }

    private var operatingFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Transceiver & Signal Parameters", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()

                if let sniper = CallIntelligenceEngine.shared.activeReport?.pileupSniper, sniper.isSplit {
                    Button {
                        BandmapEngine.shared.applySniperSolution(sniper)
                        let hz = UInt64(sniper.recommendedTxKHz * 1000.0)
                        appState.rigControlClient.setFrequencyHz(hz)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "scope")
                                .font(.system(size: 9, weight: .bold))
                            Text("SPLIT \(sniper.offsetSignFormatted)")
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.yellow.opacity(0.18), in: Capsule())
                        .overlay(Capsule().stroke(Color.yellow.opacity(0.5), lineWidth: 1))
                        .foregroundStyle(Color.yellow)
                    }
                    .buttonStyle(.plain)
                    .help("DX is operating SPLIT. Click to arm VFO-B to Sniper target \(sniper.frequencyFormattedMHz)")
                }
            }

            HStack(alignment: .top, spacing: 10) {
                // FREQUENCY
                compactField("Frequency (MHz)", width: 125) {
                    TextField("14.074", text: $appState.quickLogDraft.frequencyMHz)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: .frequency)
                        .onChange(of: appState.quickLogDraft.frequencyMHz) { _, value in
                            appState.quickLogDraft.applyFrequency(value)
                        }
                }

                // BAND
                compactField("Band", width: 85) {
                    Picker("", selection: $appState.quickLogDraft.band) {
                        ForEach(AmateurBandPlan.commonBands, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }

                // MODE
                compactField("Mode", width: 95) {
                    Picker("", selection: $appState.quickLogDraft.mode) {
                        ForEach(modes, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: appState.quickLogDraft.mode) { _, newValue in
                        appState.quickLogDraft.applyMode(newValue)
                    }
                }

                // SUBMODE
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

                // RST SENT
                compactField("RST Sent", width: 85) {
                    TextField("59", text: $appState.quickLogDraft.rstSent)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: .rstSent)
                }

                // RST RECV
                compactField("RST Recv", width: 85) {
                    TextField("59", text: $appState.quickLogDraft.rstReceived)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: .rstReceived)
                        .onSubmit {
                            if esm.isEnabled {
                                handleESMAction()
                            } else {
                                attemptSave()
                            }
                        }
                }
            }

            // QUICK RST PRESET CHIPS
            HStack(spacing: 6) {
                Text("Quick RST:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                let rstPresets: [String] = {
                    let m = appState.quickLogDraft.mode.uppercased()
                    if m == "CW" { return ["599", "579", "559"] }
                    if m == "DATA" || m == "FT8" || m == "FT4" { return ["-10", "-15", "+00", "+05"] }
                    return ["59", "57", "55"]
                }()

                ForEach(rstPresets, id: \.self) { rst in
                    Button {
                        appState.quickLogDraft.rstSent = rst
                        appState.quickLogDraft.rstReceived = rst
                    } label: {
                        Text(rst)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    @ViewBuilder
    private var contestFields: some View {
        let session = appState.currentContestSession
        let isContestActive = session?.isActive == true

        DisclosureGroup(isExpanded: $showContestFields) {
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
                        .onSubmit {
                            if esm.isEnabled {
                                handleESMAction()
                            } else {
                                attemptSave()
                            }
                        }
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
                } else {
                    Text("(Optional)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.18)))
    }

    private var contactFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Callbook & Station Details", systemImage: "person.text.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let lookup = appState.quickLogLookup, !lookup.sources.isEmpty {
                    Text("Source: " + lookup.sources.joined(separator: " + "))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    labeledField("Name", text: $appState.quickLogDraft.name)
                    labeledField("QTH", text: $appState.quickLogDraft.qth)
                    labeledField("Grid", text: $appState.quickLogDraft.grid)
                        .onChange(of: appState.quickLogDraft.grid) { _, val in
                            if val != val.uppercased() {
                                appState.quickLogDraft.grid = val.uppercased()
                            }
                        }
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
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                labeledField("QSO Notes & Comments", text: $appState.quickLogDraft.comment)
                    .focused($focusedField, equals: .comment)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Status")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.quickLogStatus == "Cleared" || appState.quickLogStatus.contains("Loaded") || appState.quickLogStatus == "Saved" ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(appState.quickLogStatus)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 140, alignment: .trailing)
            }

            // Quick Comment Chips
            HStack(spacing: 5) {
                Text("Quick Notes:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                ForEach(["73!", "TNX QSO", "Ragchew", "First QSO", "QRP 5W"], id: \.self) { tag in
                    Button {
                        if appState.quickLogDraft.comment.isEmpty {
                            appState.quickLogDraft.comment = tag
                        } else if !appState.quickLogDraft.comment.contains(tag) {
                            appState.quickLogDraft.comment += " · \(tag)"
                        }
                    } label: {
                        Text(tag)
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadRecordIntoForm(_ record: QSORecordModel) {
        appState.quickLogDraft.callsign = record["CALL"]
        appState.quickLogDraft.frequencyMHz = record["FREQ"]
        appState.quickLogDraft.band = record["BAND"]
        appState.quickLogDraft.mode = record["MODE"]
        appState.quickLogDraft.submode = record["SUBMODE"]
        appState.quickLogDraft.rstSent = record["RST_SENT"]
        appState.quickLogDraft.rstReceived = record["RST_RCVD"]
        appState.quickLogDraft.name = record["NAME"]
        appState.quickLogDraft.qth = record["QTH"]
        appState.quickLogDraft.grid = record["GRID"]
        appState.quickLogDraft.country = record["COUNTRY"]
        appState.quickLogDraft.comment = record["COMMENT"]
        appState.refreshQuickLogAssessment()
        focusedField = .callsign
        appState.quickLogStatus = "Loaded \(record["CALL"])"
    }

    private var recentQSOsTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Bar
            HStack(spacing: 8) {
                Label("Recent Station QSOs", systemImage: "clock.badge.checkmark")
                    .font(.subheadline.weight(.bold))

                // Selector for count: 8 / 15 / 25
                HStack(spacing: 2) {
                    ForEach([8, 15, 25], id: \.self) { count in
                        Button {
                            recentLimit = count
                        } label: {
                            Text("\(count)")
                                .font(.system(size: 10, weight: recentLimit == count ? .bold : .regular))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(recentLimit == count ? Color.accentColor.opacity(0.2) : Color.clear, in: Capsule())
                                .foregroundStyle(recentLimit == count ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.secondary.opacity(0.08), in: Capsule())

                // Quick Search Bar
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    TextField("Filter recent...", text: $recentSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 110)
                    if !recentSearchText.isEmpty {
                        Button {
                            recentSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2)))

                Spacer()

                Text("Total in Log: \(appState.qsoRecords.count.formatted())")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    appState.selectedTab = 0
                } label: {
                    HStack(spacing: 3) {
                        Text("View Full Log")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Switch to Log Table tab (⌘1)")
            }

            if appState.qsoRecords.isEmpty {
                Text("No QSOs logged yet. Enter details above and press ↵ to log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                let filtered = appState.qsoRecords.filter { rec in
                    guard !recentSearchText.isEmpty else { return true }
                    let q = recentSearchText.uppercased()
                    return rec["CALL"].uppercased().contains(q) ||
                           rec["BAND"].uppercased().contains(q) ||
                           rec["MODE"].uppercased().contains(q) ||
                           rec["GRID"].uppercased().contains(q) ||
                           rec["COMMENT"].uppercased().contains(q)
                }
                let recents = Array(filtered.suffix(recentLimit).reversed())

                VStack(alignment: .leading, spacing: 0) {
                    // Table Column Headers
                    HStack(spacing: 8) {
                        Text("TIME (UTC)").frame(width: 68, alignment: .leading)
                        Text("CALLSIGN").frame(width: 105, alignment: .leading)
                        Text("BAND / FREQ").frame(width: 105, alignment: .leading)
                        Text("MODE").frame(width: 48, alignment: .leading)
                        Text("RST (S/R)").frame(width: 65, alignment: .leading)
                        Text("INFO & EXCHANGE").frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                        Text("QSL").frame(width: 85, alignment: .trailing)
                        Text("").frame(width: 24, alignment: .center)
                    }
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                    Divider()
                        .padding(.vertical, 2)

                    ForEach(Array(recents.enumerated()), id: \.element.id) { index, record in
                        RecentQSORowView(
                            record: record,
                            isEven: index % 2 == 0,
                            onLoad: { loadRecordIntoForm(record) },
                            onDelete: {
                                recordToDelete = record
                                showDeleteConfirm = true
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        .confirmationDialog(
            "Delete QSO Record",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete QSO", role: .destructive) {
                if let r = recordToDelete {
                    appState.deleteRecord(id: r.id)
                    recordToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { recordToDelete = nil }
        } message: {
            if let r = recordToDelete {
                Text("Are you sure you want to delete QSO with \(r["CALL"]) on \(r["BAND"]) \(r["MODE"])?")
            }
        }
    }

    private var historyPanel: some View {
        CallIntelligencePanelView()
    }

    private var stationDashboardCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Operator Profile Card
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.activeStationProfile?.callsign.isEmpty == false ? (appState.activeStationProfile?.callsign ?? "EP2AES") : "EP2AES")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                        Text(appState.activeStationProfile?.name.isEmpty == false ? (appState.activeStationProfile?.name ?? "Station Operator") : "Station Operator")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let grid = appState.activeStationProfile?.grid, !grid.isEmpty {
                        Text(grid)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))

            // Logbook Quick Stats
            VStack(alignment: .leading, spacing: 8) {
                Text("STATION LOGBOOK")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    statBox(title: "TOTAL QSOs", value: appState.qsoRecords.count.formatted(), color: .primary)
                    let confirmed = appState.qsoRecords.filter(\.isConfirmed).count
                    let rate = appState.qsoRecords.isEmpty ? 0 : Int((Double(confirmed) / Double(appState.qsoRecords.count)) * 100)
                    statBox(title: "CONFIRMED", value: "\(confirmed.formatted()) (\(rate)%)", color: .green)
                }

                HStack(spacing: 8) {
                    let uniqueCalls = Set(appState.qsoRecords.map { $0["CALL"] }).count
                    statBox(title: "UNIQUE CALLS", value: uniqueCalls.formatted(), color: .blue)
                    let activeBands = Set(appState.qsoRecords.map { $0["BAND"] }.filter { !$0.isEmpty }).count
                    statBox(title: "ACTIVE BANDS", value: "\(activeBands) Bands", color: .purple)
                }
            }

            // Keyboard Shortcuts Card
            VStack(alignment: .leading, spacing: 6) {
                Text("OPERATOR SHORTCUTS")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)

                shortcutRow(key: "Space", desc: "Advance to RST / Exchange")
                shortcutRow(key: "↵ Enter", desc: "Log QSO immediately")
                shortcutRow(key: "Esc", desc: "Wipe form & reset for next")
                shortcutRow(key: "⌘1", desc: "Switch to full Log Table")
            }
            .padding(10)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12)))
        }
    }

    private func statBox(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.15)))
    }

    private func shortcutRow(key: String, desc: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            Text(desc)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
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

    private var esmContestToolbar: some View {
        HStack(spacing: 8) {
            // ESM On/Off Toggle Button
            Button {
                esm.isEnabled.toggle()
                if esm.isEnabled && appState.quickLogDraft.mode.uppercased() != "CW" {
                    appState.quickLogDraft.applyMode("CW")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: esm.isEnabled ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 11, weight: .bold))
                    Text("ESM")
                        .font(.system(size: 11, weight: .bold))
                    Text(esm.isEnabled ? "ACTIVE" : "OFF")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(esm.isEnabled ? Color.orange : Color.secondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundColor(esm.isEnabled ? .black : .white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(esm.isEnabled ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(esm.isEnabled ? Color.orange.opacity(0.4) : Color.secondary.opacity(0.18), lineWidth: 1)
                )
                .foregroundColor(esm.isEnabled ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle ESM Contest Automation: Pressing Enter sends Morse and advances QSO stages automatically (Ctrl+M)")

            if esm.isEnabled {
                // RUN vs S&P Segmented Picker
                Picker("", selection: $esm.operatingMode) {
                    Label("RUN (Pileup)", systemImage: "flame.fill").tag(CWESMOperatingMode.run)
                    Label("S&P (Hunt)", systemImage: "binoculars.fill").tag(CWESMOperatingMode.searchAndPounce)
                }
                .pickerStyle(.segmented)
                .frame(width: 195)

                // Live Prediction Pill
                let action = esmCurrentAction
                let preview = esm.previewExpandedAction(action: action, appState: appState)
                HStack(spacing: 5) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 10))
                        .foregroundColor(action.badgeColor)
                    Text("NEXT:")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(preview.previewText)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(action.badgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(action.badgeColor.opacity(0.28), lineWidth: 1))
                .foregroundColor(action.badgeColor)

                Spacer()

                // Fast CW WPM quick stepper
                HStack(spacing: 4) {
                    Text("CW:")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("\(CWKeyerService.shared.wpm) WPM")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    Button {
                        CWKeyerService.shared.decreaseWPM(2)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    Button {
                        CWKeyerService.shared.increaseWPM(2)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            } else {
                Spacer()
            }

            // Paddle Break-in indicator
            if CWKeyerService.shared.isPaddleBreakInActive {
                HStack(spacing: 4) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 8))
                    Text("⚡ PADDLE BREAK-IN")
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
                .foregroundColor(.white)
            }

            // Bandmap HUD Toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    showContestBandmapHUD.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.system(size: 9))
                    Text("Bandmap")
                        .font(.system(size: 9.5, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(showContestBandmapHUD ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                .foregroundColor(showContestBandmapHUD ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Contest Bandmap vertical frequency ruler")

            // Rate Matrix HUD Toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    showContestRateMatrixHUD.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 9))
                    Text("Rate Matrix")
                        .font(.system(size: 9.5, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(showContestRateMatrixHUD ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                .foregroundColor(showContestRateMatrixHUD ? .purple : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Contest Rate Speedometer & Multiplier 2D Matrix")

            // Hidden Ctrl+M shortcut
            Button("") {
                esm.isEnabled.toggle()
                if esm.isEnabled && appState.quickLogDraft.mode.uppercased() != "CW" {
                    appState.quickLogDraft.applyMode("CW")
                }
            }
            .keyboardShortcut("m", modifiers: [.control])
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .padding(.vertical, 2)
    }

    private func handleESMAction() {
        let now = Date()
        guard now.timeIntervalSince(lastESMExecutionTime) > 0.25 else { return }
        lastESMExecutionTime = now

        let action = esmCurrentAction
        esm.executeAction(
            action: action,
            appState: appState,
            focusExchange: {
                if appState.currentContestSession?.isActive == true {
                    focusedField = .exchange
                } else {
                    focusedField = .rstReceived
                }
            },
            focusCallsign: {
                focusedField = .callsign
            },
            saveQSO: {
                attemptSave()
            }
        )
    }

    private func handleEscapeKey() {
        if CWKeyerService.shared.isTransmitting || CWKeyerService.shared.isAutoCQActive {
            CWKeyerService.shared.stop()
            appState.quickLogStatus = "CW Keying Aborted"
        } else {
            wipeForm()
        }
    }

    private func moveAfterCallsign() {
        if esm.isEnabled {
            handleESMAction()
            return
        }
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
        esm.resetForNewQSO()
        updateCallIntelligence()
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

    private func prefillCallHistory(_ hist: CallHistoryRecord) {
        if !hist.name.isEmpty && appState.quickLogDraft.name.isEmpty {
            appState.quickLogDraft.name = hist.name
        }
        if !hist.state.isEmpty && appState.quickLogDraft.state.isEmpty {
            appState.quickLogDraft.state = hist.state
        }
        if !hist.arrlSection.isEmpty && appState.quickLogDraft.arrlSection.isEmpty {
            appState.quickLogDraft.arrlSection = hist.arrlSection
        }
        if appState.quickLogDraft.receivedExchange.isEmpty {
            if !hist.userExchange.isEmpty {
                appState.quickLogDraft.receivedExchange = hist.userExchange
            } else if let z = hist.cqZone, z > 0 {
                appState.quickLogDraft.receivedExchange = z < 10 ? "0\(z)" : "\(z)"
            } else if !hist.state.isEmpty {
                appState.quickLogDraft.receivedExchange = hist.state
            }
        }
        if !hist.gridSquare.isEmpty && appState.quickLogDraft.grid.isEmpty {
            appState.quickLogDraft.grid = hist.gridSquare
        }
    }

    private func save() {
        do {
            _ = try appState.saveQuickLog()
            duplicateWasAcknowledged = false
            updateCallIntelligence()
            CallHistoryLookupEngine.shared.learnFromLogbook(records: appState.qsoRecords)
            ContestRateMatrixEngine.shared.recalculate(qsoRecords: appState.qsoRecords)
            esm.resetForNewQSO()
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
    @ObservedObject private var lotwDB = LoTWActivityDatabase.shared

    // Cluster Connection settings
    @AppStorage("dxClusterPrimaryHost") private var primaryHost = "dxcluster.co.uk"
    @AppStorage("dxClusterPrimaryPort") private var primaryPort = 7373
    @AppStorage("dxClusterBackupHost") private var backupHost = "dxc.nc7j.com"
    @AppStorage("dxClusterBackupPort") private var backupPort = 7373
    @AppStorage("dxClusterSSID") private var clusterSSID = "22"
    @AppStorage("dxClusterWatchlist") private var watchlistText = ""
    @AppStorage("dxClusterNeededAlerts") private var neededAlerts = true
    @AppStorage("dxClusterAlertRulesData") private var alertRulesData = ""

    // UI & Filter states
    @State private var showConnectionSettings = false
    @State private var showAlertSettings = false
    @State private var showSendSpotSheet = false
    @State private var showConsoleSheet = false
    @State private var showArchiveSheet = false

    @State private var bandFilter = "All"
    @State private var modeFilter = "All" // "All", "Hide FT8", "CW", "SSB", "Digital"
    @State private var needFilter = "All" // "All", "Needed", "Unconfirmed", "Watchlist", "LoTW Active"
    @State private var maxSpotterDistanceKm: Double = 0.0 // 0 = Any
    @State private var searchText = ""

    @State private var workIndex = LogWorkIndex(records: [])
    @State private var alertedSpotIDs: Set<String> = []
    @State private var alertCooldowns: [String: Date] = [:]
    @State private var alertRules: [SpotAlertRule] = SpotAlertRule.defaultRules()

    // Send Spot state
    @State private var spotCallInput = ""
    @State private var spotFreqInput = ""
    @State private var spotCommentInput = ""

    // Console command state
    @State private var consoleInput = ""

    // Banner & enhanced feature states
    @ObservedObject private var localServer = LocalClusterServer.shared
    @ObservedObject private var ctyDB = CTYDatabaseManager.shared
    @State private var showRBNMatrix = false
    @State private var showLocalServerSettings = false
    @AppStorage("localClusterServerPort") private var localServerPort: Int = 7300
    @AppStorage("dxClusterSpotTTLMinutes") private var spotTTLMinutes: Double = 60.0
    @AppStorage("dxClusterDeliverNotifications") private var deliverSystemNotifications: Bool = true

    private var watchlist: Set<String> {
        Set(watchlistText
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
            .map { $0.uppercased() })
    }

    private var effectiveGrid: String {
        appState.effectiveStationGrid
    }

    private var filteredSpots: [DXSpot] {
        let cutoff = Date().addingTimeInterval(-spotTTLMinutes * 60)
        return client.spots.filter { spot in
            guard spot.lastSeenAt >= cutoff else { return false }

            // Band filter
            if bandFilter != "All", spot.band != bandFilter { return false }

            // Mode filter
            let m = spot.mode.uppercased()
            let sub = spot.submode.uppercased()
            switch modeFilter {
            case "Hide FT8":
                if m == "FT8" || sub == "FT8" || m == "FT4" || sub == "FT4" || m == "DATA" { return false }
            case "CW":
                if m != "CW" && sub != "CW" { return false }
            case "SSB":
                if m != "SSB" && sub != "SSB" && m != "PHONE" { return false }
            case "Digital":
                if m != "FT8" && sub != "FT8" && m != "FT4" && sub != "FT4" && m != "RTTY" && m != "DATA" { return false }
            default:
                break
            }

            // Need / LoTW filter
            let status = workIndex.status(for: spot.callsign, band: spot.band)
            switch needFilter {
            case "Needed":
                if status != .newCallsign, status != .newBand { return false }
            case "Unconfirmed":
                if status == .confirmed { return false }
            case "Watchlist":
                if !watchlist.contains(spot.callsign) { return false }
            case "LoTW Active":
                if !spot.isLoTWActive { return false }
            default:
                break
            }

            // Spotter distance filter
            if maxSpotterDistanceKm > 0 {
                if let dist = spot.spotterDistanceKm {
                    if dist > maxSpotterDistanceKm { return false }
                } else {
                    // Unknown spotter grid: hide when strictly filtering by distance
                    return false
                }
            }

            // Text search
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return spot.callsign.lowercased().contains(query) ||
                    spot.comment.lowercased().contains(query) ||
                    spot.spotter.lowercased().contains(query) ||
                    spot.grid.lowercased().contains(query)
            }

            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            clusterToolbar
            Divider()
            smartBanners
            columnHeader
            Divider()

            if client.spots.isEmpty && client.pausedBufferCount == 0 {
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
            statusBar
        }
        .onAppear {
            rebuildWorkIndex()
            loadAlertRules()
        }
        .onChange(of: appState.qsoRecords.count) { _, _ in rebuildWorkIndex() }
        .onChange(of: appState.totalConfirmedCount) { _, _ in rebuildWorkIndex() }
        .onChange(of: client.spots.first?.id) { _, _ in processNewestSpotForAlert() }
        .popover(isPresented: $showConnectionSettings, arrowEdge: .top) {
            connectionSettingsView
                .padding(16)
                .frame(width: 440)
        }
        .sheet(isPresented: $showAlertSettings) {
            alertSettingsSheet
                .frame(width: 580, height: 480)
        }
        .sheet(isPresented: $showSendSpotSheet) {
            sendSpotSheet
                .frame(width: 400, height: 260)
        }
        .sheet(isPresented: $showConsoleSheet) {
            clusterConsoleSheet
                .frame(width: 640, height: 480)
        }
        .sheet(isPresented: $showArchiveSheet) {
            SpotArchiveView()
                .environmentObject(appState)
                .frame(width: 1020, height: 640)
        }
    }

    // MARK: - Toolbar

    private var clusterToolbar: some View {
        HStack(spacing: 8) {
            connectionButton

            // Pause / Resume Display button
            Button {
                client.toggleDisplayPause()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: client.isDisplayPaused ? "play.circle.fill" : "pause.circle")
                    Text(client.isDisplayPaused ? (client.pausedBufferCount > 0 ? "Resume (\(client.pausedBufferCount))" : "Resume") : "Pause")
                }
            }
            .buttonStyle(.bordered)
            .tint(client.isDisplayPaused ? .orange : .secondary)
            .help(client.isDisplayPaused ? "Resume real-time display and show buffered spots" : "Pause table scroll while keeping background spot reception")

            bandPicker
            modePicker
            needPicker
            distancePicker
            ttlPicker

            searchControl

            Spacer()

            // Quick Actions
            Button {
                showSendSpotSheet = true
            } label: {
                Label("Spot", systemImage: "plus.bubble")
            }
            .help("Submit a new DX spot to cluster")

            Button {
                showConsoleSheet = true
            } label: {
                Image(systemName: "terminal")
            }
            .help("Interactive DX cluster terminal console")

            Button {
                showArchiveSheet = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("Historical spot archive — search multi-day history & export to CSV")

            Button {
                exportLiveSpotsToCSV()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export current live spots to CSV")

            Button {
                showAlertSettings = true
            } label: {
                Image(systemName: "bell.badge")
            }
            .help("Configure 5-tier intelligent alerts & rate limits")

            // RBN Mode Matrix
            Button {
                showRBNMatrix = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(client.rbnSettings.cw || client.rbnSettings.ft8 ? .blue : .secondary)
            }
            .help("RBN Mode Filter Matrix — control which skimmer modes pass through")
            .popover(isPresented: $showRBNMatrix, arrowEdge: .top) {
                rbnMatrixPopover
                    .padding(16)
                    .frame(width: 300)
            }

            // Local Server Status Pill
            Button {
                showLocalServerSettings = true
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(localServer.isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(localServer.isRunning
                         ? "Local:\(localServer.port) (\(localServer.clientCount))"
                         : "Local Off")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(localServer.isRunning ? .primary : .secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    localServer.isRunning
                        ? Color.green.opacity(0.12)
                        : Color.secondary.opacity(0.08),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(
                    localServer.isRunning ? Color.green.opacity(0.3) : Color.clear,
                    lineWidth: 1
                ))
            }
            .buttonStyle(.plain)
            .help(localServer.isRunning
                  ? "Local redistribution server running on port \(localServer.port) — \(localServer.clientCount) client(s) connected"
                  : "Local redistribution server is stopped — tap to configure")
            .popover(isPresented: $showLocalServerSettings, arrowEdge: .top) {
                localServerSettingsPopover
                    .padding(16)
                    .frame(width: 320)
            }

            Button {
                showConnectionSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Primary & Backup cluster connection settings")

            Button {
                client.clearSpots()
            } label: {
                Image(systemName: "trash")
            }
            .help("Clear received spots")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Smart Banner Stack

    @ViewBuilder
    private var smartBanners: some View {
        VStack(spacing: 0) {
            // 0. Rover Mode Active Tactical Banner
            if appState.isRoverActive, let session = RoverModeEngine.shared.activeSession {
                HStack(spacing: 8) {
                    Image(systemName: "shoeprints.fill")
                        .foregroundStyle(.orange)
                    Text("ROVER ACTIVE: \(session.targetGrid)")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.orange)
                    Text("· \(session.label)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("(\(session.formattedRemainingTime))")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Distances & headings from \(session.targetGrid)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button {
                        RoverModeEngine.shared.deactivate()
                    } label: {
                        Text("Return Home")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                Divider()
            }

            // 1. Upstream Filter Warning
            if client.upstreamFiltersDetected && !client.isUpstreamFilterBannerDismissed {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Upstream filters detected on \(client.primaryHost)")
                            .font(.system(size: 11, weight: .semibold))
                        if !client.upstreamFilterDetails.isEmpty {
                            Text(client.upstreamFilterDetails)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button("Clear Filters") {
                        client.clearUpstreamFilters()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    Button {
                        client.dismissUpstreamFilterBanner()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss this warning")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.10))
                .overlay(Rectangle().frame(height: 1), alignment: .bottom)
            }

            // 2. Flap Protection Banner
            if client.isFlapProtectionActive {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Flap Protection Active")
                            .font(.system(size: 11, weight: .semibold))
                        let secs = max(0, Int(client.flapCooldownRemaining))
                        Text("Reconnect blocked for \(secs)s — cluster was disconnecting too frequently")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Override") {
                        client.overrideFlapProtection()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                    .help("Force reconnect now, bypassing flap protection")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.purple.opacity(0.10))
                .overlay(Rectangle().frame(height: 1), alignment: .bottom)
            }

            // 3. CTY Database Staleness Warning
            if ctyDB.isLoaded && ctyDB.isStale {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CTY.DAT is over 30 days old")
                            .font(.system(size: 11, weight: .semibold))
                        if let date = ctyDB.releaseDate {
                            Text("Last updated: \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Update Now") {
                        Task { try? await ctyDB.updateFromWeb() }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.yellow.opacity(0.08))
                .overlay(Rectangle().frame(height: 1), alignment: .bottom)
            }
        }
    }

    // MARK: - RBN Matrix Popover

    private var rbnMatrixPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("RBN Mode Filter Matrix")
                        .font(.headline)
                    Text("Control which Reverse Beacon Network skimmer modes are allowed through")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            let cw    = client.rbnSettings.cw
            let rtty  = client.rbnSettings.rtty
            let ft8   = client.rbnSettings.ft8
            let psk   = client.rbnSettings.psk
            let bkn   = client.rbnSettings.beacons

            rbnToggleRow(label: "CW (Morse)",          icon: "waveform",               color: .blue,   isOn: cw)   { v in var s = client.rbnSettings; s.cw      = v; client.updateRBNSettings(s) }
            rbnToggleRow(label: "RTTY (Teletype)",     icon: "teletype",               color: .orange, isOn: rtty) { v in var s = client.rbnSettings; s.rtty    = v; client.updateRBNSettings(s) }
            rbnToggleRow(label: "FT8 / FT4 (Digital)", icon: "dot.radiowaves.forward", color: .green,  isOn: ft8)  { v in var s = client.rbnSettings; s.ft8     = v; client.updateRBNSettings(s) }
            rbnToggleRow(label: "PSK31 / BPSK",        icon: "waveform.path",          color: .indigo, isOn: psk)  { v in var s = client.rbnSettings; s.psk     = v; client.updateRBNSettings(s) }
            rbnToggleRow(label: "Beacons",              icon: "radio.fill",             color: .gray,   isOn: bkn)  { v in var s = client.rbnSettings; s.beacons = v; client.updateRBNSettings(s) }

            Divider()

            HStack(spacing: 8) {
                Button("All On") {
                    client.updateRBNSettings(RBNMatrixSettings(cw: true, rtty: true, ft8: true, ft4: true, psk: true, beacons: true))
                }
                .controlSize(.small)
                Button("CW Only") {
                    client.updateRBNSettings(RBNMatrixSettings(cw: true, rtty: false, ft8: false, ft4: false, psk: false, beacons: false))
                }
                .controlSize(.small)
                Spacer()
                Button("Close") { showRBNMatrix = false }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func rbnToggleRow(label: String, icon: String, color: Color, isOn: Bool, onToggle: @escaping (Bool) -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { onToggle($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    // MARK: - Local Server Settings Popover

    private var localServerSettingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(.green)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Local Redistribution Server")
                        .font(.headline)
                    Text("Broadcast spots to N1MM, DX4WIN, and other local clients via Telnet/UDP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(localServer.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(localServer.isRunning ? "Running" : "Stopped")
                    .font(.system(size: 12, weight: .semibold))
                if localServer.isRunning {
                    Text("· \(localServer.clientCount) client(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(localServer.isRunning ? "Stop" : "Start") {
                    if localServer.isRunning {
                        localServer.stop()
                    } else {
                        localServer.port = localServerPort
                        localServer.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(localServer.isRunning ? .red : .green)
                .controlSize(.small)
            }

            HStack {
                Text("Telnet Port")
                    .font(.system(size: 12))
                Spacer()
                TextField("7300", value: $localServerPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
            }

            Text("Clients connect to 127.0.0.1:\(localServerPort). UDP spot broadcasts on port \(localServer.port + 1) (N1MM compatible).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Spacer()
                Button("Close") { showLocalServerSettings = false }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var connectionButton: some View {
        Button {
            if client.state.isConnected {
                client.disconnect()
            } else {
                client.connect(
                    primaryHost: primaryHost,
                    primaryPort: primaryPort,
                    backupHost: backupHost,
                    backupPort: backupPort,
                    callsign: appState.currentStationCallsign,
                    ssid: clusterSSID,
                    homeGrid: effectiveGrid
                )
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: client.state.isConnected ? "stop.fill" : "play.fill")
                Text(client.state.isConnected ? (client.activeNodeRole == .backup ? "Backup: Disconnect" : "Disconnect") : "Connect")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(client.state.isConnected ? (client.activeNodeRole == .backup ? .orange : .red) : .accentColor)
    }

    private var bandPicker: some View {
        Picker("Band", selection: $bandFilter) {
            Text("All Bands").tag("All")
            ForEach(AmateurBandPlan.commonBands, id: \.self) { Text($0).tag($0) }
        }
        .frame(width: 110)
    }

    private var modePicker: some View {
        Picker("Mode", selection: $modeFilter) {
            Text("All Modes").tag("All")
            Text("Hide FT8/Data").tag("Hide FT8")
            Text("CW Only").tag("CW")
            Text("SSB Only").tag("SSB")
            Text("Digital Only").tag("Digital")
        }
        .frame(width: 130)
    }

    private var needPicker: some View {
        Picker("Need", selection: $needFilter) {
            Text("All").tag("All")
            Text("Needed").tag("Needed")
            Text("Unconfirmed").tag("Unconfirmed")
            Text("Watchlist").tag("Watchlist")
            Text("LoTW Active").tag("LoTW Active")
        }
        .frame(width: 125)
    }

    private var distancePicker: some View {
        Picker("Proximity", selection: $maxSpotterDistanceKm) {
            Text("Any Dist").tag(0.0)
            Text("< 1,000 km").tag(1000.0)
            Text("< 2,500 km").tag(2500.0)
            Text("< 5,000 km").tag(5000.0)
        }
        .frame(width: 110)
        .help("Filter spots by maximum distance from your station grid to the spotter")
    }

    private var ttlPicker: some View {
        Picker("Age", selection: $spotTTLMinutes) {
            Text("15m").tag(15.0)
            Text("30m").tag(30.0)
            Text("1h").tag(60.0)
            Text("2h").tag(120.0)
            Text("4h").tag(240.0)
            Text("12h").tag(720.0)
        }
        .frame(width: 80)
        .help("Spot Retention / Age Cutoff — only display spots heard within this time window")
    }

    private var searchControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Call, spotter, comment, grid", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
        .frame(minWidth: 160)
    }

    // MARK: - Table Header & Rows

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("UTC").frame(width: 50, alignment: .leading)
            Text("FREQUENCY").frame(width: 85, alignment: .trailing)
            Text("CALL").frame(width: 125, alignment: .leading)
            Text("BAND").frame(width: 46, alignment: .center)
            Text("MODE").frame(width: 52, alignment: .center)
            Text("SNR").frame(width: 44, alignment: .center)
            Text("BEAM").frame(width: 46, alignment: .center)
            Text("LOTW").frame(width: 44, alignment: .center)
            Text("STATUS").frame(width: 82, alignment: .leading)
            Text("PROXIMITY").frame(width: 110, alignment: .leading)
            Text("COMMENT").frame(maxWidth: .infinity, alignment: .leading)
            Text("SPOTTER").frame(width: 80, alignment: .leading)
            Color.clear.frame(width: 65)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func spotRow(_ spot: DXSpot) -> some View {
        let status = workIndex.status(for: spot.callsign, band: spot.band)
        let alertColor = alertHighlightColor(for: spot, status: status)

        return HStack(spacing: 10) {
            Text(clusterUTCTimeFormatter.string(from: spot.spottedAt))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 50, alignment: .leading)

            Text(String(format: "%.1f", spot.frequencyKHz))
                .font(.system(.body, design: .monospaced))
                .frame(width: 85, alignment: .trailing)

            HStack(spacing: 3) {
                Button {
                    toggleWatch(spot.callsign)
                } label: {
                    Image(systemName: watchlist.contains(spot.callsign) ? "star.fill" : "star")
                        .foregroundStyle(watchlist.contains(spot.callsign) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                if !spot.flagEmoji.isEmpty {
                    Text(spot.flagEmoji)
                        .font(.system(size: 12))
                }

                Text(spot.callsign)
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .lineLimit(1)

                if spot.reportCount > 1 {
                    Text("×\(spot.reportCount)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }
            .frame(width: 125, alignment: .leading)

            Text(spot.band.isEmpty ? "-" : spot.band)
                .font(.caption)
                .frame(width: 46, alignment: .center)

            Text(spot.submode.isEmpty ? spot.mode : spot.submode)
                .font(.caption)
                .frame(width: 52, alignment: .center)

            // P0-B: SNR Column (RBN / Signal strength)
            Group {
                if let snr = spot.snrDB {
                    Text("\(snr > 0 ? "+\(snr)" : "\(snr)")dB")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(spot.snrColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(spot.snrColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                } else {
                    Text("-").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 44, alignment: .center)

            // P0-C / P1-B: Beam Antenna Heading towards spotted station
            Group {
                if let beam = spot.beamHeadingDeg {
                    Text(String(format: "%03.0f°", beam))
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(.primary)
                } else {
                    Text("-").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 46, alignment: .center)
            .help(spot.beamHeadingDeg.map { "Beam antenna heading: \(Int($0.rounded()))° towards \(spot.dxccEntityName)" } ?? "Beam heading unavailable")

            // LoTW User Indicator
            lotwBadge(for: spot)
                .frame(width: 44, alignment: .center)

            Text(status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor(status))
                .frame(width: 82, alignment: .leading)

            // Proximity & Bearing
            Group {
                if let dist = spot.spotterDistanceKm, let az = spot.spotterBearingDeg {
                    Text("\(Int(dist.rounded()))km · \(Int(az.rounded()))°\(spot.spotterCardinalDirection ?? "")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("-").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 110, alignment: .leading)

            Text(spot.comment.isEmpty ? "-" : spot.comment)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(spot.spotter)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 80, alignment: .leading)

            HStack(spacing: 4) {
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
            .frame(width: 65, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(alertColor ?? rowBackground(status))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { appState.prepareQuickLog(from: spot) }
    }

    private func lotwBadge(for spot: DXSpot) -> some View {
        let desc = lotwDB.lastUploadDescription(for: spot.callsign)
        return Group {
            if spot.isLoTWActive {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if spot.lotwLastUpload != nil {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(.orange)
            } else {
                Text("-").foregroundStyle(.tertiary)
            }
        }
        .help(desc)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Label(
                client.lastMessage,
                systemImage: client.state.isConnected ? (client.activeNodeRole == .backup ? "exclamationmark.triangle.fill" : "checkmark.circle.fill") : "info.circle"
            )
            .foregroundStyle(client.state.isConnected ? (client.activeNodeRole == .backup ? .orange : .green) : .secondary)

            if client.isDisplayPaused {
                Text("· DISPLAY PAUSED (\(client.pausedBufferCount) buffered)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }

            Spacer()

            if lotwDB.isLoaded {
                Text("LoTW: \(lotwDB.userCount) users")
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
            }

            Text("Showing \(filteredSpots.count) of \(client.spots.count) · \(client.receivedSpotCount) received")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: - Connection Settings Popover

    private var connectionSettingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("DX Cluster Architecture", systemImage: "network")
                    .font(.headline)
                Spacer()
                if client.state.isConnected {
                    Text("Active: \(client.activeNodeRole.rawValue)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(client.activeNodeRole == .backup ? Color.orange.opacity(0.2) : Color.green.opacity(0.2), in: Capsule())
                        .foregroundStyle(client.activeNodeRole == .backup ? .orange : .green)
                }
            }

            GroupBox("Primary Cluster Node (Default)") {
                VStack(spacing: 8) {
                    HStack {
                        TextField("Host", text: $primaryHost).textFieldStyle(.roundedBorder)
                        TextField("Port", value: $primaryPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 75)
                    }
                }
                .padding(4)
            }

            GroupBox("Backup Cluster Node (Failover)") {
                VStack(spacing: 8) {
                    HStack {
                        TextField("Host", text: $backupHost).textFieldStyle(.roundedBorder)
                        TextField("Port", value: $backupPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 75)
                    }
                    Text("Switches automatically after 3 connection drops and probes primary in background.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $client.isAggregationEnabled) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.merge")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Dual-Node Aggregation")
                                    .font(.subheadline.weight(.semibold))
                                Text("Connect to BOTH nodes simultaneously and merge all spots from both feeds")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onChange(of: client.isAggregationEnabled) { _, enabled in
                        if enabled && client.state.isConnected {
                            client.startSecondaryConnection()
                        } else {
                            client.stopSecondaryConnection()
                        }
                    }

                    if client.isAggregationEnabled {
                        Divider()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(client.secondaryState.isConnected ? Color.green : Color.secondary.opacity(0.35))
                                .frame(width: 7, height: 7)
                            Text("Secondary node: \(client.secondaryState.isConnected ? "Connected (\(client.backupHost):\(client.backupPort))" : "Connecting…")")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(client.secondaryState.isConnected ? .primary : .secondary)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(4)
            } label: {
                Label("Multi-Cluster Aggregation", systemImage: "arrow.triangle.merge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            HStack {
                Text("Callsign SSID:")
                TextField("e.g. 22", text: $clusterSSID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("(Avoids session conflict if other apps connect with same call)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GroupBox("ARRL LoTW User Intelligence") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Active Users Database:")
                        Spacer()
                        Text(lotwDB.isLoaded ? "\(lotwDB.userCount) active stations" : "Not loaded")
                            .foregroundStyle(lotwDB.isLoaded ? .green : .secondary)
                    }
                    HStack {
                        if lotwDB.isUpdating {
                            ProgressView().controlSize(.small)
                            Text("Updating from ARRL...").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Update LoTW Database Now") {
                                Task { try? await lotwDB.updateFromWeb() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Watchlist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("K1ABC, EP2XYZ, 3B7M", text: $watchlistText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Done") { showConnectionSettings = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - 5-Tier Alert Settings Sheet

    private var alertSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("5-Tier Intelligent Spot Alerts", systemImage: "bell.badge.fill")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("Done") {
                    saveAlertRules()
                    showAlertSettings = false
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Configure up to 5 flexible, rate-limited alert slots with custom highlight colors and audio cues.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Deliver native macOS notification banners when alerts fire", isOn: $deliverSystemNotifications)
                .font(.subheadline.weight(.medium))

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach($alertRules) { $rule in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Toggle(rule.title, isOn: $rule.isEnabled)
                                        .font(.headline)

                                    Spacer()

                                    ColorPicker("", selection: Binding(
                                        get: { Color(hex: rule.colorHex) ?? .orange },
                                        set: { rule.colorHex = $0.toHex() ?? rule.colorHex }
                                    ))
                                    .labelsHidden()

                                    Picker("Sound", selection: $rule.soundName) {
                                        Text("Notice").tag("Notice")
                                        Text("Ping").tag("Ping")
                                        Text("Hero").tag("Hero")
                                        Text("Submarine").tag("Submarine")
                                        Text("Glass").tag("Glass")
                                        Text("None").tag("None")
                                    }
                                    .frame(width: 110)
                                }

                                HStack(spacing: 12) {
                                    TextField("DXCC Entity (e.g. Iran)", text: $rule.dxccEntity)
                                        .textFieldStyle(.roundedBorder)

                                    Picker("Band", selection: $rule.band) {
                                        Text("All Bands").tag("")
                                        ForEach(AmateurBandPlan.commonBands, id: \.self) { Text($0).tag($0) }
                                    }
                                    .frame(width: 110)

                                    Picker("Mode", selection: $rule.mode) {
                                        Text("All Modes").tag("")
                                        Text("CW").tag("CW")
                                        Text("SSB").tag("SSB")
                                        Text("FT8").tag("FT8")
                                        Text("RTTY").tag("RTTY")
                                    }
                                    .frame(width: 110)
                                }

                                HStack(spacing: 12) {
                                    HStack {
                                        Text("Wildcard Call:")
                                            .font(.caption)
                                        TextField("*P*, 3B7*, FT*", text: $rule.callsignPattern)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 140)
                                    }

                                    Toggle("Needed only", isOn: $rule.onlyUnworkedOrUnconfirmed)
                                        .font(.caption)

                                    Toggle("macOS Banner", isOn: $rule.sendNotification)
                                        .font(.caption)

                                    Spacer()

                                    Picker("Cooldown", selection: $rule.cooldownMinutes) {
                                        Text("Every spot").tag(0)
                                        Text("Max 1 / 5m").tag(5)
                                        Text("Max 1 / 10m").tag(10)
                                        Text("Max 1 / 15m").tag(15)
                                    }
                                    .frame(width: 120)
                                }
                            }
                            .padding(6)
                        }
                    }
                }
            }
        }
        .padding(18)
    }

    // MARK: - Send Spot Sheet

    private var sendSpotSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Submit DX Spot to Cluster", systemImage: "plus.bubble.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("DX Station Callsign:")
                    .font(.caption)
                TextField("e.g. EP2AES", text: $spotCallInput)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Frequency (kHz):")
                    .font(.caption)
                TextField("e.g. 14025.0", text: $spotFreqInput)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Comment:")
                    .font(.caption)
                TextField("599 in Tehran TNX", text: $spotCommentInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { showSendSpotSheet = false }
                Spacer()
                Button("Send Spot") {
                    if let freq = Double(spotFreqInput), !spotCallInput.isEmpty {
                        client.sendSpot(callsign: spotCallInput, frequencyKHz: freq, comment: spotCommentInput)
                        showSendSpotSheet = false
                        spotCallInput = ""
                        spotFreqInput = ""
                        spotCommentInput = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(spotCallInput.isEmpty || Double(spotFreqInput) == nil)
            }
        }
        .padding(18)
    }

    // MARK: - Cluster Terminal Console Sheet

    private var clusterConsoleSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("DX Cluster Terminal Console", systemImage: "terminal.fill")
                    .font(.headline)
                Spacer()
                Button("Clear") { client.clearConsole() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Done") { showConsoleSheet = false }
                    .buttonStyle(.borderedProminent)
            }

            // Common shortcut command buttons
            HStack(spacing: 8) {
                Button("sh/dx") { client.sendCommand("sh/dx") }
                Button("sh/wwv") { client.sendCommand("sh/wwv") }
                Button("sh/sun") { client.sendCommand("sh/sun") }
                Button("sh/filter") { client.sendCommand("sh/filter") }
                Button("set/skimmer") { client.setRBNEnabled(true) }
                Button("unset/skimmer") { client.setRBNEnabled(false) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Terminal display
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(client.rawConsoleLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.hasPrefix(">") ? .yellow : .primary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(Color.black.opacity(0.85))
                .cornerRadius(6)
                .onChange(of: client.rawConsoleLines.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }

            // Command input field
            HStack {
                TextField("Enter cluster command (e.g. sh/dx 20, set/skimmer)...", text: $consoleInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !consoleInput.isEmpty {
                            client.sendCommand(consoleInput)
                            consoleInput = ""
                        }
                    }

                Button("Send") {
                    if !consoleInput.isEmpty {
                        client.sendCommand(consoleInput)
                        consoleInput = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    // MARK: - Helpers & Alert Logic

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

    private func alertHighlightColor(for spot: DXSpot, status: DXSpotNeedStatus) -> Color? {
        let entityName = DXCCDatabase.resolve(callsign: spot.callsign).entityName
        for rule in alertRules where rule.isEnabled {
            if rule.matches(spot: spot, entityName: entityName, status: status) {
                return Color(hex: rule.colorHex)?.opacity(0.12)
            }
        }
        return nil
    }

    private func toggleWatch(_ callsign: String) {
        var items = watchlist
        if items.contains(callsign) { items.remove(callsign) } else { items.insert(callsign) }
        watchlistText = items.sorted().joined(separator: ", ")
    }

    private func processNewestSpotForAlert() {
        guard let spot = client.spots.first, !alertedSpotIDs.contains(spot.id) else { return }
        alertedSpotIDs.insert(spot.id)
        if alertedSpotIDs.count > 600 { alertedSpotIDs = Set(client.spots.prefix(300).map(\.id)) }

        let status = workIndex.status(for: spot.callsign, band: spot.band)
        let entityName = DXCCDatabase.resolve(callsign: spot.callsign).entityName

        // Check 5-tier alert rules
        for rule in alertRules where rule.isEnabled {
            if rule.matches(spot: spot, entityName: entityName, status: status) {
                let cooldownKey = "\(rule.id.uuidString)-\(spot.callsign)"
                if let lastTime = alertCooldowns[cooldownKey] {
                    let elapsedMin = Date().timeIntervalSince(lastTime) / 60.0
                    if elapsedMin < Double(rule.cooldownMinutes) {
                        return // Under cooldown
                    }
                }

                alertCooldowns[cooldownKey] = Date()
                if rule.soundName != "None" {
                    NSSound(named: rule.soundName)?.play()
                }
                if rule.sendNotification && deliverSystemNotifications {
                    sendSystemNotification(for: spot, ruleTitle: rule.title, entityName: entityName)
                }
                return
            }
        }

        // Fallback: standard needed alerts
        if neededAlerts {
            if watchlist.contains(spot.callsign) || status == .newCallsign || status == .newBand {
                appState.playActivitySound(.notice)
                if deliverSystemNotifications {
                    let title = watchlist.contains(spot.callsign) ? "⭐ Watchlist Station Spotted" : "🎯 Needed \(status.title)"
                    sendSystemNotification(for: spot, ruleTitle: title, entityName: entityName)
                }
            }
        }
    }

    private func sendSystemNotification(for spot: DXSpot, ruleTitle: String, entityName: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(ruleTitle): \(spot.callsign) (\(spot.band))"
            var parts = ["\(String(format: "%.1f", spot.frequencyKHz)) kHz", spot.submode.isEmpty ? spot.mode : spot.submode]
            if !entityName.isEmpty { parts.append(entityName) }
            if let snr = spot.snrDB { parts.append("SNR: \(snr > 0 ? "+\(snr)" : "\(snr)")dB") }
            if let beam = spot.beamHeadingDeg { parts.append("Beam: \(Int(beam.rounded()))°") }
            content.body = parts.joined(separator: " · ") + (spot.comment.isEmpty ? "" : "\n\"\(spot.comment)\"")
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "dxspot-\(spot.id)-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            center.add(request, withCompletionHandler: nil)
        }
    }

    private func loadAlertRules() {
        if !alertRulesData.isEmpty,
           let data = alertRulesData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([SpotAlertRule].self, from: data) {
            alertRules = decoded
        }
    }

    private func saveAlertRules() {
        if let data = try? JSONEncoder().encode(alertRules),
           let str = String(data: data, encoding: .utf8) {
            alertRulesData = str
        }
    }

    private func exportLiveSpotsToCSV() {
        guard !filteredSpots.isEmpty else { return }
        let csv = SpotArchiveDatabase.generateCSV(from: filteredSpots)

        let panel = NSSavePanel()
        panel.title = "Export Live Spots to CSV"
        panel.nameFieldStringValue = "YAAM_Live_Spots_\(Date().formatted(.iso8601.year().month().day())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]

        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
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
