//
//  HamTrackerWorkspaceView.swift
//  YAAM
//
//  Real-Time Callsign Activity Tracker & Digital Monitor UI
//  (Native macOS Visual Workstation for ham_tracker.py)
//
//  Features:
//  - Live PSKReporter MQTT 3.1.1 stream with sub-second transmission alerts
//  - FT8 15-second cycle synchronized radar & cadence analysis
//  - 360-degree polar antenna radiation pattern & reception footprint
//  - DX Cluster Telnet spot history
//  - 1-click CAT transceiver tuning, antenna rotator beam alignment, and Quick Log entry
//

import AppKit
import Combine
import Foundation
import FT8808Engine
import SwiftUI

public struct HamTrackerWorkspaceView: View {
    private struct WebSDRCycleGroup: Identifiable {
        let slot: Date
        let messages: [WebSDRAggregatedMessage]
        var id: Date { slot }
        var isEven: Bool { WebSDRSlotTime.isEven(slot) }
    }

    private struct ReceptionRegion: Identifiable {
        let region: String
        let count: Int
        var id: String { region }
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject private var engine = HamTrackerEngine.shared
    @ObservedObject private var webSDR = WebSDRFT8Monitor.shared
    @ObservedObject private var rotatorService = RotatorService.shared

    // Local UI State
    @State private var selectedTab: Int = 0 // 0: Polar Radar, 1: Band/Continent Matrix, 2: SNR Histogram
    @State private var streamFilterText: String = ""
    @State private var selectedStreamTab: Int = 0 // 0: Live Stream, 1: DX Cluster, 2: Top Spotters
    @State private var isWebSDRWorkspace = false
    @State private var decodedMessageFilter = 1
    @State private var showWebSDRSetup = false
    @State private var webSDRLogbook = WebSDRLogbookIndex()
    @State private var alertedDXKeys = Set<String>()
    @State private var activeDXAlert = ""
    @State private var lastDXAlertSoundAt = Date.distantPast
    @AppStorage("webSDRDXAudioAlertsEnabled") private var webSDRDXAudioAlertsEnabled = true
    @State private var showIcomConnection = false
    @State private var showCustomWebSDR = false
    @State private var showWebSDRReceivers = false
    @State private var showPrimaryWebSDRPicker = false
    @State private var customWebSDRName = ""
    @State private var customWebSDRURL = ""
    @State private var customWebSDRFlag = ""
    @State private var customWebSDRContinent = "AS"
    @State private var customWebSDRError = ""
    @State private var webSDRFrequencyDraft = ""
    @State private var webSDRFrequencyError = ""
    @AppStorage("icomNetworkHost") private var icomHost = ""
    @AppStorage("icomNetworkControlPort") private var icomPort = 50_001
    @AppStorage("icomNetworkUsername") private var icomUsername = ""
    @AppStorage("icomNetworkClientName") private var icomClientName = "YAAM"
    @AppStorage("icomNetworkModel") private var icomModelName = IcomNetworkModel.ic7300MK2.rawValue
    @State private var icomPassword = ""
    @State private var selectedWebSDRReply: WebSDRReplyPlan?
    @State private var webSDRReplyDraft = ""
    @State private var webSDRReplyStatus = ""
    @State private var selectedWebSDRTxParity: SlotParity = .even
    @State private var replyFollowsLatest = true
    @AppStorage("ft8OutputDeviceUID") private var webSDRFT8OutputDeviceUID = ""
    @State private var hoveredSpot: HamTrackSpot? = nil
    @State private var isShowingCLISheet: Bool = false
    @State private var showExportNotification: Bool = false
    @State private var rotatorActionNotification: String? = nil

    private var visibleWebSDRCycleGroups: [WebSDRCycleGroup] {
        let visible: [WebSDRAggregatedMessage]
        switch decodedMessageFilter {
        case 1: visible = webSDR.consensusTargetMatches
        case 2: visible = webSDR.consensusMessages.filter { message in
            guard let call = message.transmittingCallsign else { return false }
            let status = webSDRLogbook.status(for: call, band: webSDR.selectedBand)
            return status.isNewDXCC || status.isNewBand
        }
        default: visible = webSDR.consensusMessages
        }
        let grouped = Dictionary(grouping: visible, by: \.slotStart)
        return grouped.keys.sorted(by: >).map { slot in
            WebSDRCycleGroup(slot: slot, messages: (grouped[slot] ?? []).sorted {
                if $0.mentionsTarget != $1.mentionsTarget { return $0.mentionsTarget }
                if $0.receiverCount != $1.receiverCount { return $0.receiverCount > $1.receiverCount }
                return $0.text < $1.text
            })
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Top Control Bar (Search, Presets, Live Status & CTA)
            headerControlStrip
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            HStack(spacing: 8) {
                Picker("Digital monitor view", selection: $isWebSDRWorkspace) {
                    Text("Activity & spots").tag(false)
                    Text("WebSDR RX · FT8").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Digital monitor view")
                .frame(width: 280)
                Spacer()
                if isWebSDRWorkspace {
                    Text("\(webSDR.selectedAutomaticEndpoints.count) receivers · \(webSDR.consensusTargetMatches.count) target messages")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider()

            if isWebSDRWorkspace {
                webSDRReceivePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {

            // 2. High-Tech Telemetry HUD Cards (4 Dynamic Cards)
            telemetryHUDGrid
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))

            Divider()

            // 2.5 Active QSO Partner Hero Banner / Detection Status
            activePartnerHeroBanner
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 3. Central Main Split View (Radar / Visuals on Left, Live Stream on Right)
            HSplitView {
                // Left Pane: Visual Radar & Analytics
                leftVisualWorkspace
                    .frame(minWidth: 360, minHeight: 340)

                // Right Pane: Live Activity Stream & Spotters
                rightStreamWorkspace
                    .frame(minWidth: 380, idealWidth: 460, maxWidth: 620)
            }
            }

            Divider()

            // 4. Bottom Quick Action Command Strip
            bottomActionToolbar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $isShowingCLISheet) {
            cliDiagnosticSheet
        }
        .onAppear {
            webSDR.refreshInputs()
            let coord = appState.effectiveStationCoordinate
            engine.homeCoordinate = GeoCoordinate(latitude: coord.latitude, longitude: coord.longitude)
            if engine.targetCallsign.isEmpty {
                // The operator's active station is the default WebSDR target.
                if let profile = appState.activeStationProfile, !profile.normalizedCallsign.isEmpty {
                    engine.setTarget(profile.normalizedCallsign)
                } else if !appState.quickLogDraft.normalizedCallsign.isEmpty {
                    engine.setTarget(appState.quickLogDraft.normalizedCallsign)
                } else {
                    engine.setTarget("")
                }
            }
        }
        .onChange(of: engine.targetCallsign) { _, _ in
            webSDR.stop()
            selectedWebSDRReply = nil
            webSDRReplyDraft = ""
        }
    }

    // MARK: - 1. Top Control Bar

    private var headerControlStrip: some View {
        HStack(spacing: 12) {
            // Target Callsign Input
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13, weight: .bold))

                TextField("Callsign (e.g. EP2AES, W1AW)", text: $engine.targetCallsign)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .frame(width: 170)
                    .onSubmit {
                        if !engine.targetCallsign.isEmpty {
                            engine.startMonitoring()
                        }
                    }

                if !engine.targetCallsign.isEmpty {
                    Button {
                        engine.targetCallsign = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }

                // Recent History Menu
                Menu {
                    Text("Recent Target Callsigns").font(.caption.bold())
                    Divider()
                    ForEach(engine.recentSearches, id: \.self) { call in
                        Button(call) {
                            engine.setTarget(call)
                            engine.startMonitoring()
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(engine.status.isLive ? Color.green.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: 1.2)
            )

            // Quick Station Chips
            HStack(spacing: 6) {
                if let activeCall = appState.activeStationProfile?.normalizedCallsign, !activeCall.isEmpty {
                    Button {
                        engine.setTarget(activeCall)
                        engine.startMonitoring()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 9))
                            Text(activeCall)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Monitor my own transmitter footprint")
                }

                if !appState.quickLogDraft.normalizedCallsign.isEmpty,
                   appState.quickLogDraft.normalizedCallsign != engine.targetCallsign {
                    Button {
                        engine.setTarget(appState.quickLogDraft.normalizedCallsign)
                        engine.startMonitoring()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "target")
                                .font(.system(size: 9))
                            Text(appState.quickLogDraft.normalizedCallsign)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                        .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    .help("Monitor station in Quick Log draft")
                }
            }

            Spacer()

            // Stable Real-Time Activity Status Capsule
            stationActivityCapsule

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(engine.status.indicatorColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: engine.status.indicatorColor.opacity(0.8), radius: engine.status.isLive ? 4 : 0)

                Text(engine.status.displayText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(engine.status.isLive ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: Capsule())

            // Window Duration Picker
            Picker("", selection: $engine.selectedTimeWindow) {
                ForEach(HamTrackerTimeWindow.allCases) { window in
                    Text(window.shortLabel).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 184)
            .help("Catch-up time window")

            // Audio Alert Toggle
            Button {
                engine.audioAlertsEnabled.toggle()
            } label: {
                Image(systemName: engine.audioAlertsEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(engine.audioAlertsEnabled ? .yellow : .secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help(engine.audioAlertsEnabled ? "Audio alerts enabled (Click to mute)" : "Audio alerts muted (Click to enable)")

            // CLI Diagnostic Sheet
            Button {
                isShowingCLISheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                    Text("CLI")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("View & run python ham_tracker.py CLI diagnostics")

            // Primary Start / Stop Button
            Button {
                if engine.status.isLive {
                    engine.stopMonitoring()
                } else {
                    engine.startMonitoring()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: engine.status.isLive ? "stop.fill" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .bold))
                    Text(engine.status.isLive ? "Stop" : "Start Live Track")
                        .font(.system(size: 11.5, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    engine.status.isLive
                        ? LinearGradient(colors: [.red.opacity(0.85), .orange.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .foregroundStyle(.white)
                .shadow(color: engine.status.isLive ? .red.opacity(0.4) : .blue.opacity(0.3), radius: 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var stationActivityCapsule: some View {
        HStack(spacing: 7) {
            if engine.cycleStatus.isTargetTransmittingNow {
                // TRANSMITTING: Solid Red for full 15 seconds with remaining countdown
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: .red, radius: 4)

                HStack(spacing: 4) {
                    Text("TRANSMITTING (TX)")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.red)

                    Text(":\(String(format: "%02d", engine.cycleStatus.slotSecondsRemaining))s")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.red)
                }
            } else if engine.cycleStatus.isTargetListeningNow {
                // LISTENING / RX: Cyan for full 15 seconds with remaining countdown
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 7, height: 7)
                    .shadow(color: .cyan, radius: 3)

                HStack(spacing: 4) {
                    Text("LISTENING (RX)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.cyan)

                    Text(":\(String(format: "%02d", engine.cycleStatus.slotSecondsRemaining))s")
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                // STANDBY / IDLE
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)

                Text(engine.cycleStatus.lastSeenSecondsAgo.map { "Standby (Heard \($0)s ago)" } ?? "Awaiting Signal...")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 200)
        .background(
            engine.cycleStatus.isTargetTransmittingNow
                ? Color.red.opacity(0.12)
                : (engine.cycleStatus.isTargetListeningNow ? Color.cyan.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.7)),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(
                    engine.cycleStatus.isTargetTransmittingNow
                        ? Color.red.opacity(0.7)
                        : (engine.cycleStatus.isTargetListeningNow ? Color.cyan.opacity(0.5) : Color.secondary.opacity(0.18)),
                    lineWidth: 1.2
                )
        )
    }

    // MARK: - 2. Telemetry HUD Cards

    private var telemetryHUDGrid: some View {
        HStack(spacing: 10) {
            // Card 1: Active Frequency & Band
            hudCard(title: "PRIMARY FREQUENCY & BAND", icon: "waveform.path") {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if engine.statistics.primaryFrequencyMHz > 0 {
                            Text(String(format: "%.4f", engine.statistics.primaryFrequencyMHz))
                                .font(.system(size: 17, weight: .black, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("MHz")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Awaiting Signal...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !engine.statistics.primaryBand.isEmpty {
                            Text(engine.statistics.primaryBand)
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.blue)
                        }

                        if !engine.statistics.primaryMode.isEmpty {
                            Text(engine.statistics.primaryMode)
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.purple)
                        }
                    }

                    HStack(spacing: 4) {
                        if let ago = engine.cycleStatus.lastSeenSecondsAgo {
                            Circle()
                                .fill(ago <= 30 ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text("Heard \(ago)s ago")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No transmissions in window")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        if engine.statistics.primaryFrequencyMHz > 0 {
                            Button {
                                tuneTransceiver(freqMHz: engine.statistics.primaryFrequencyMHz)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "radio")
                                        .font(.system(size: 8))
                                    Text("QSY Rig")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            .help("Tune connected transceiver to this frequency")
                        }
                    }
                }
            }

            // Card 2: FT8 15s Cycle Timing Radar
            hudCard(title: "FT8 TRANSMISSION CYCLE", icon: "clock.arrow.circlepath") {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        // Circular Ring Progress
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 3.5)
                            Circle()
                                .trim(from: 0, to: engine.cycleStatus.progress)
                                .stroke(
                                    engine.cycleStatus.isTargetTransmittingNow
                                        ? LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)
                                        : (engine.cycleStatus.isTargetListeningNow
                                            ? LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
                                            : LinearGradient(colors: [.secondary.opacity(0.5), .secondary.opacity(0.2)], startPoint: .top, endPoint: .bottom)),
                                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                            Text(String(format: "%02d", engine.cycleStatus.slotSecondsRemaining))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(engine.cycleStatus.isTargetTransmittingNow ? .red : (engine.cycleStatus.isTargetListeningNow ? .cyan : .primary))
                        }
                        .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 1) {
                            if engine.cycleStatus.isTargetTransmittingNow {
                                Text("🔴 TX: Transmitting Now (\(engine.cycleStatus.currentSlotLabel))")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(.red)
                            } else if engine.cycleStatus.isTargetListeningNow {
                                Text("🔵 RX: Listening / Receiving (\(engine.cycleStatus.currentSlotLabel))")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(.cyan)
                            } else {
                                Text("Current Slot: \(engine.cycleStatus.currentSlotLabel)")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(.primary)
                            }

                            Text(engine.cycleStatus.activityState.statusDescription)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.cyan)
                        Text(engine.cycleStatus.recommendedCallCycle)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                }
            }

            // Card 3: Signal Quality (SNR Telemetry)
            hudCard(title: "SIGNAL REPORT (SNR)", icon: "chart.bar.fill") {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%+.1f dB", engine.statistics.averageSNR))
                            .font(.system(size: 17, weight: .black, design: .monospaced))
                            .foregroundStyle(snrColor(Int(engine.statistics.averageSNR)))

                        Text("avg")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            HStack(spacing: 3) {
                                Text("Peak:")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text(engine.statistics.peakSNR > -90 ? "\(engine.statistics.peakSNR > 0 ? "+" : "")\(engine.statistics.peakSNR) dB" : "—")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                            HStack(spacing: 3) {
                                Text("Low:")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                Text(engine.statistics.weakestSNR < 90 ? "\(engine.statistics.weakestSNR) dB" : "—")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.purple)
                            }
                        }
                    }

                    // SNR Gauge Bar (-24 dB to +15 dB)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 4)

                            let normalized = max(0.0, min(1.0, (engine.statistics.averageSNR + 24.0) / 39.0))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(colors: [.purple, .orange, .cyan, .green], startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: geo.size.width * normalized, height: 4)
                        }
                    }
                    .frame(height: 5)
                }
            }

            // Card 4: Global Reach & Furthest Spotter
            hudCard(title: "GLOBAL SPOTTING FOOTPRINT", icon: "globe.europe.africa.fill") {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(engine.statistics.uniqueSpottersCount)")
                            .font(.system(size: 17, weight: .black, design: .monospaced))
                            .foregroundStyle(.primary)

                        Text("Spotters")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Continents badges (filtering out "??" and invalid strings)
                        HStack(spacing: 3) {
                            ForEach(engine.statistics.continents.filter { $0 != "??" && $0 != "--" && $0.count == 2 }, id: \.self) { c in
                                Text(c)
                                    .font(.system(size: 8.5, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        if engine.statistics.furthestDistanceKm > 0 {
                            Text("Max DX: \(engine.statistics.furthestFlag) \(engine.statistics.furthestSpotter)")
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f km", engine.statistics.furthestDistanceKm))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Transmitter Grid: \(engine.statistics.targetTransmitterGrid.isEmpty ? "Unknown" : engine.statistics.targetTransmitterGrid)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func hudCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            content()
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 0.8))
    }

    // MARK: - 2.5 Active QSO Partner Hero Banner

    private var activePartnerHeroBanner: some View {
        Group {
            if let partner = engine.activePartner {
                HStack(spacing: 12) {
                    // Left: Glowing badge and Partner identity
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 34, height: 34)
                            Image(systemName: "person.2.wave.2.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.green)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("POSSIBLE PARTNER · SPOT CORRELATION")
                                    .font(.system(size: 8.5, weight: .black))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(.green)

                                Text(partner.confidencePercentage >= 90 ? "HIGH SPOT CORRELATION" : "POSSIBLE EXCHANGE")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(partner.confidenceBadgeColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(partner.confidenceBadgeColor)
                            }

                            HStack(spacing: 6) {
                                Text(partner.flag)
                                    .font(.system(size: 15))
                                Text(partner.callsign)
                                    .font(.system(size: 16, weight: .black, design: .monospaced))
                                    .foregroundStyle(.primary)

                                if !partner.grid.isEmpty {
                                    Text("[\(partner.grid)]")
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }

                                Text("• \(partner.country)")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer()

                    // Middle: Correlation Telemetry
                    HStack(spacing: 12) {
                        // Cycles count
                        VStack(alignment: .leading, spacing: 1) {
                            Text("MATCHED SLOTS")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.swap")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.cyan)
                                Text("\(partner.matchedCyclesCount) Cycles")
                                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            }
                        }

                        // Frequency offset
                        VStack(alignment: .leading, spacing: 1) {
                            Text("OFFSET (ΔHz)")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("\(partner.frequencyOffsetHz >= 0 ? "+" : "")\(partner.frequencyOffsetHz) Hz")
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(abs(partner.frequencyOffsetHz) <= 15 ? Color.green : Color.cyan)
                        }

                        // Path Distance & Bearing
                        if let dist = partner.distanceKmFromTarget {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("TARGET ➔ PARTNER")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 3) {
                                    Text(String(format: "%.0f km", dist))
                                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                    if let brg = partner.bearingDegFromTarget {
                                        Text("• \(Int(brg))°")
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.12), lineWidth: 0.8))

                    // Right: Actions Strip
                    HStack(spacing: 6) {
                        Button {
                            isWebSDRWorkspace = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 9))
                                Text("Verify on WebSDR")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.6), lineWidth: 1))
                            .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Check actual decoded FT8 messages before logging a contact")

                        Button {
                            engine.switchTrackerToPartner()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 9))
                                Text("Track Partner")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.6), lineWidth: 1))
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Switch active tracking target to this partner station")

                        Menu {
                            Button("Tune Transceiver to \(String(format: "%.4f", partner.frequencyMHz)) MHz") {
                                tuneTransceiver(freqMHz: partner.frequencyMHz)
                            }
                            if let brg = partner.bearingDegFromTarget {
                                Button("Turn Rotator to \(Int(brg))°") {
                                    rotatorService.turnTo(azimuth: brg)
                                    rotatorActionNotification = "Rotator turning to \(Int(brg))°"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        rotatorActionNotification = nil
                                    }
                                }
                            }
                            Divider()
                            Button("View in Call Intelligence") {
                                appState.quickLogDraft.callsign = partner.callsign
                                appState.openOperatorDesk(.quickLog)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 18)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [Color.green.opacity(0.12), Color.blue.opacity(0.08)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.green.opacity(0.4), lineWidth: 1.2))
            } else {
                // Scanning / Ready State
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: engine.cycleStatus.isTargetTransmittingNow ? "waveform.badge.magnifyingglass" : "waveform.and.person.filled")
                            .font(.system(size: 11))
                            .foregroundStyle(engine.cycleStatus.isTargetTransmittingNow ? .red : (engine.partnerDetectionEnabled ? .cyan : .secondary))

                        Text(engine.cycleStatus.isTargetTransmittingNow ? "STATION CALLING CQ" : "QSO PARTNER DETECTOR")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    if engine.partnerDetectionEnabled {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(engine.cycleStatus.isTargetTransmittingNow ? Color.red : Color.cyan)
                                .frame(width: 5, height: 5)
                            if engine.cycleStatus.isTargetTransmittingNow {
                                Text("\(engine.targetCallsign.isEmpty ? "Target" : engine.targetCallsign) is calling CQ • Listening for answering station on alternate cycle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            } else if !engine.partnerScanningBand.isEmpty {
                                Text("Monitoring ±45 Hz opposite cycle exchanges on \(engine.partnerScanningBand)...")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Active • Awaiting \(engine.targetCallsign.isEmpty ? "target" : engine.targetCallsign) transmission to lock band & cycle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Partner detection paused.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !engine.recentCompletedQSOs.isEmpty {
                        Text("\(engine.recentCompletedQSOs.count) spot-inferred exchange(s)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Toggle("", isOn: $engine.partnerDetectionEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help("Enable cross-cycle frequency correlation for active QSO partner detection")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - 3. Left Visual Workspace (Polar Radar / Matrix / Histogram)

    private var leftVisualWorkspace: some View {
        VStack(spacing: 0) {
            // Viewport Switcher Tab Bar
            HStack(spacing: 8) {
                Picker("", selection: $selectedTab) {
                    Text("Polar Radar").tag(0)
                    Text("Band & Continents").tag(1)
                    Text("SNR Spectrum").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Spacer()

                if let spot = hoveredSpot {
                    HStack(spacing: 4) {
                        Text("\(spot.receiverFlag) \(spot.receiverCall)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        Text("(\(spot.snr > 0 ? "+" : "")\(spot.snr) dB • \(spot.distanceKm.map { String(format: "%.0f km", $0) } ?? "—"))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))

            Divider()

            // Viewport Content
            ZStack {
                switch selectedTab {
                case 0:
                    polarRadiationRadarCanvas
                case 1:
                    bandAndContinentMatrixView
                case 2:
                    snrDistributionHistogramView
                default:
                    polarRadiationRadarCanvas
                }

                // Rotator feedback banner
                if let notification = rotatorActionNotification {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "location.north.line.fill")
                                .foregroundStyle(.cyan)
                            Text(notification)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.5), lineWidth: 1))
                        .padding(.bottom, 12)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // Sub-View A: 360° Polar Radiation Radar Canvas
    private var polarRadiationRadarCanvas: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let maxRadius = min(geo.size.width, geo.size.height) * 0.44

            ZStack {
                // Background dark radar glass
                RadialGradient(
                    colors: [Color.blue.opacity(0.08), Color.black.opacity(0.4)],
                    center: .center,
                    startRadius: 0,
                    endRadius: maxRadius
                )

                // Concentric distance rings
                ForEach([0.25, 0.50, 0.75, 1.0], id: \.self) { fraction in
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                        .frame(width: maxRadius * 2 * fraction, height: maxRadius * 2 * fraction)

                    // Distance label
                    Text("\(Int(fraction * 16000)) km")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .position(x: center.x, y: center.y - maxRadius * fraction + 8)
                }

                // Compass Spokes & Cardinal Labels
                ForEach([0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { angle in
                    Path { path in
                        let rad = Double(angle - 90) * .pi / 180.0
                        path.move(to: center)
                        path.addLine(to: CGPoint(
                            x: center.x + CGFloat(cos(rad)) * maxRadius,
                            y: center.y + CGFloat(sin(rad)) * maxRadius
                        ))
                    }
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 0.8)

                    let cardinal = cardinalString(for: angle)
                    let rad = Double(angle - 90) * .pi / 180.0
                    Text(cardinal)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(angle == 0 ? .red : .secondary)
                        .position(
                            x: center.x + CGFloat(cos(rad)) * (maxRadius + 14),
                            y: center.y + CGFloat(sin(rad)) * (maxRadius + 14)
                        )
                }

                // Center Origin Point (Target Transmitter)
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .shadow(color: .cyan, radius: 6)
                    .position(center)

                Text(engine.targetCallsign.isEmpty ? "TX" : engine.targetCallsign)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .position(x: center.x, y: center.y + 14)

                // Plotted Spotter Nodes
                ForEach(engine.spots) { spot in
                    if let dist = spot.distanceKm, let bearing = spot.bearingDeg {
                        let clampedDist = min(dist, 16000.0)
                        let fraction = clampedDist / 16000.0
                        let r = maxRadius * fraction
                        let rad = Double(bearing - 90.0) * .pi / 180.0
                        let x = center.x + CGFloat(cos(rad)) * r
                        let y = center.y + CGFloat(sin(rad)) * r

                        ZStack {
                            Circle()
                                .fill(spot.snrBadgeColor)
                                .frame(width: spot.isRealtimeMQTT ? 9 : 6, height: spot.isRealtimeMQTT ? 9 : 6)
                                .shadow(color: spot.snrBadgeColor.opacity(0.8), radius: spot.isRealtimeMQTT ? 5 : 2)

                            if spot.isRealtimeMQTT {
                                Circle()
                                    .stroke(spot.snrBadgeColor.opacity(0.5), lineWidth: 1)
                                    .frame(width: 15, height: 15)
                            }
                        }
                        .position(x: x, y: y)
                        .onHover { isHovered in
                            hoveredSpot = isHovered ? spot : nil
                        }
                    }
                }

                // Active QSO Partner Vector & Highlight Node on Radar
                if let partner = engine.activePartner,
                   let dist = partner.distanceKmFromTarget,
                   let bearing = partner.bearingDegFromTarget {
                    let clampedDist = min(dist, 16000.0)
                    let fraction = clampedDist / 16000.0
                    let r = maxRadius * fraction
                    let rad = Double(bearing - 90.0) * .pi / 180.0
                    let px = center.x + CGFloat(cos(rad)) * r
                    let py = center.y + CGFloat(sin(rad)) * r

                    // Dashed QSO Vector Line
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: CGPoint(x: px, y: py))
                    }
                    .stroke(
                        LinearGradient(colors: [.cyan, .green], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                    )

                    // Partner Node with Diamond and Glow
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.8), lineWidth: 1.5)
                            .frame(width: 20, height: 20)

                        Image(systemName: "diamond.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.yellow)
                            .shadow(color: .yellow, radius: 4)

                        VStack(spacing: 1) {
                            Text("🤝 \(partner.flag) \(partner.callsign)")
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                                .shadow(color: .black.opacity(0.4), radius: 2)
                        }
                        .offset(y: -17)
                    }
                    .position(x: px, y: py)
                }
            }
        }
    }

    private func cardinalString(for angle: Int) -> String {
        switch angle {
        case 0: return "N"
        case 45: return "NE"
        case 90: return "E"
        case 135: return "SE"
        case 180: return "S"
        case 225: return "SW"
        case 270: return "W"
        case 315: return "NW"
        default: return ""
        }
    }

    // Sub-View B: Band & Continent Matrix View
    private var bandAndContinentMatrixView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Active Bands Breakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE TRANSMISSION BANDS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    if engine.statistics.activeBands.isEmpty {
                        Text("No band telemetry recorded yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(engine.statistics.activeBands.sorted(by: { $0.value > $1.value }), id: \.key) { band, count in
                            HStack {
                                Text(band.isEmpty ? "Unknown" : band)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(width: 70, alignment: .leading)

                                GeometryReader { geo in
                                    let maxVal = engine.statistics.activeBands.values.max() ?? 1
                                    let ratio = CGFloat(count) / CGFloat(maxVal)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.blue.gradient)
                                        .frame(width: max(12, geo.size.width * ratio), height: 16)
                                }
                                .frame(height: 16)

                                Text("\(count) spots")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                // Continents Reach Matrix
                VStack(alignment: .leading, spacing: 8) {
                    Text("GLOBAL CONTINENT RECEPTION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    let allContinents = ["EU", "AS", "NA", "SA", "AF", "OC", "AN"]
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                        ForEach(allContinents, id: \.self) { c in
                            let active = engine.statistics.continents.contains(c)
                            HStack(spacing: 5) {
                                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(active ? .green : .secondary.opacity(0.4))
                                    .font(.system(size: 11))
                                Text(continentName(for: c))
                                    .font(.system(size: 10.5, weight: active ? .bold : .regular))
                                    .foregroundStyle(active ? .primary : .secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(active ? Color.green.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(14)
        }
    }

    private func continentName(for code: String) -> String {
        switch code {
        case "EU": return "Europe"
        case "AS": return "Asia"
        case "NA": return "N. America"
        case "SA": return "S. America"
        case "AF": return "Africa"
        case "OC": return "Oceania"
        case "AN": return "Antarctica"
        default: return code
        }
    }

    // Sub-View C: SNR Distribution Histogram
    private var snrDistributionHistogramView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SIGNAL-TO-NOISE RATIO (SNR) HISTOGRAM")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            let buckets = computeSNRBuckets()
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(buckets, id: \.label) { b in
                    VStack(spacing: 4) {
                        Text("\(b.count)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.secondary)

                        GeometryReader { geo in
                            let maxCount = buckets.map(\.count).max() ?? 1
                            let heightRatio = maxCount > 0 ? CGFloat(b.count) / CGFloat(maxCount) : 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(b.color.gradient)
                                .frame(height: max(4, geo.size.height * heightRatio))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }

                        Text(b.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .padding(14)

            Spacer()
        }
    }

    private struct SNRSegment {
        let label: String
        let count: Int
        let color: Color
    }

    private func computeSNRBuckets() -> [SNRSegment] {
        var strong = 0   // >= 0 dB
        var good = 0     // -1 .. -10 dB
        var fair = 0     // -11 .. -18 dB
        var weak = 0     // < -18 dB

        for s in engine.spots {
            if s.snr >= 0 { strong += 1 }
            else if s.snr >= -10 { good += 1 }
            else if s.snr >= -18 { fair += 1 }
            else { weak += 1 }
        }

        return [
            SNRSegment(label: "Strong (≥0)", count: strong, color: .green),
            SNRSegment(label: "Good (-1..-10)", count: good, color: .cyan),
            SNRSegment(label: "Fair (-11..-18)", count: fair, color: .orange),
            SNRSegment(label: "Weak (<-18)", count: weak, color: .purple)
        ]
    }

    // MARK: - 4. Right Stream Workspace (Live Stream / DX Cluster / Spotters)

    private var rightStreamWorkspace: some View {
        VStack(spacing: 0) {
            // Segmented Header
            HStack(spacing: 8) {
                Picker("", selection: $selectedStreamTab) {
                    Text("Spots (\(engine.spots.count))").tag(0)
                    Text("Spot Inference").tag(1)
                    Text("Spotters (\(engine.statistics.uniqueSpottersCount))").tag(2)
                    Text("Cluster (\(engine.clusterSpots.count))").tag(3)
                }
                .pickerStyle(.segmented)

                if selectedStreamTab == 3 {
                    Button {
                        engine.refreshClusterSpots()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh DX Cluster spots")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))

            Divider()

            // Filter Text Bar
            if selectedStreamTab == 0 {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))
                    TextField("Filter spotters by callsign, grid, band...", text: $streamFilterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !streamFilterText.isEmpty {
                        Button { streamFilterText = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                Divider()
            }

            // Stream Content
            switch selectedStreamTab {
            case 0:
                liveSpotsTableView
            case 1:
                partnerContactsTableView
            case 2:
                topSpottersTableView
            case 3:
                clusterSpotsTableView
            default:
                liveSpotsTableView
            }
        }
    }

    // MARK: - Actual FT8 audio from WebSDR playback

    private var webSDRReceivePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            webSDRReceiveControls

            Divider()
            webSDRDecodedMessages

        }
        .onAppear {
            webSDRLogbook = WebSDRLogbookIndex(records: appState.qsoRecords)
            webSDR.checkReceiver(webSDR.receiver.id, url: webSDR.receiver.url)
            webSDRFrequencyDraft = WebSDRFrequency.formattedMHz(webSDR.dialHz)
            followLatestWebSDRReply()
            scanDXOpportunities()
        }
        .onChange(of: appState.qsoRecordsRevision) { _, _ in
            webSDRLogbook = WebSDRLogbookIndex(records: appState.qsoRecords)
            scanDXOpportunities()
        }
        .onChange(of: webSDR.consensusMessages.first?.id) { _, _ in
            scanDXOpportunities()
        }
        .onChange(of: webSDR.messages.count) { _, _ in
            scanDXOpportunities()
        }
        .sheet(isPresented: $showIcomConnection) {
            icomConnectionSheet
        }
        .sheet(isPresented: $showCustomWebSDR) {
            customWebSDRSheet
        }
        .onChange(of: webSDR.consensusTargetMatches.count) { _, _ in
            if replyFollowsLatest { followLatestWebSDRReply() }
        }
    }

    private func webSDRMessageRow(_ message: WebSDRAggregatedMessage, in group: WebSDRCycleGroup) -> some View {
        let logStatus: WebSDRLogbookStatus? = message.transmittingCallsign.map {
            webSDRLogbook.status(for: $0, band: webSDR.selectedBand)
        }
        let entityLabel: String = "\(logStatus?.entity.flagEmoji ?? message.transmittingFlag) \(logStatus?.entity.entityName ?? "Unknown")"
        let relativeLevel: String = WebSDRRelativeLevel.value(message.signalLevelDbFS, among: group.messages)
            .map { "\($0) rel dB" } ?? "— rel dB"
        let rawLevel: String = message.signalLevelDbFS.map { String(format: "%.0f dBFS", $0) } ?? "unknown"
        let receiverNames: String = message.receivers.map { "\($0.receiverFlag) \($0.receiverName)" }.joined(separator: ", ")
        let receiverDetails: String = message.receivers
            .map { "\($0.receiverFlag) \($0.receiverName) · \(Int($0.audioFrequencyHz)) Hz" }
            .joined(separator: "\n")
        return HStack(spacing: 6) {
            Text(entityLabel)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)
                .help(message.transmittingCallsign ?? "Transmitter not identified")
            Text(message.text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .help(message.text)
            if let grid = WebSDRMessageParser.grid(in: message.text) {
                Text(grid).font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if let grid = logStatus?.loggedGrid {
                Text("\(grid) · log").font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let state = logStatus?.loggedState {
                Text("\(state) · log").font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            if let plan = WebSDRReplyPlanner.plan(for: message.text,
                                                  targetCallsign: engine.targetCallsign) {
                Button {
                    selectedWebSDRReply = plan
                    webSDRReplyDraft = plan.draft
                    selectedWebSDRTxParity = appState.ft8Engine.txParity
                    webSDRReplyStatus = ""
                    replyFollowsLatest = false
                } label: {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                }
                .buttonStyle(.plain)
                .help("Prepare expected reply: \(plan.draft)")
            }
            Spacer(minLength: 2)
            if message.mentionsTarget {
                Text(message.addressedToTarget ? (message.isAcknowledgement ? "ACK" : "REPLY") : "MENTION")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(message.isAcknowledgement ? .green : .orange)
            }
            if let status = logStatus, status.isNewDXCC || status.isNewBand {
                Label(status.isNewDXCC ? "NEW DXCC" : "NEW BAND", systemImage: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(status.isNewDXCC ? .orange : .yellow)
                    .help(status.isNewDXCC
                          ? "No logged QSO with \(status.entity.entityName)"
                          : "No logged QSO with \(status.entity.entityName) on \(webSDR.selectedBand)")
            } else if logStatus?.workedCall == true {
                Text("WORKED").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(relativeLevel)
                .font(.system(size: 9, design: .monospaced))
                .help("Relative to this cycle; raw audio level: \(rawLevel). Not RF SNR.")
            if message.receiverCount > 1 {
                Text("\(message.receiverCount)/\(message.totalSelectedReceivers)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(message.hasMajority ? .purple : .secondary)
            }
            Text(receiverNames)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 230, alignment: .trailing)
                .help(receiverDetails)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(logStatus?.isNewDXCC == true ? Color.orange.opacity(0.27) :
                    logStatus?.isNewBand == true ? Color.yellow.opacity(0.22) :
                    message.hasMajority ? Color.purple.opacity(0.23) :
                    (group.isEven ? Color.green.opacity(0.13) : Color.blue.opacity(0.13)))
        .overlay(alignment: .leading) {
            if logStatus?.isNewDXCC == true || logStatus?.isNewBand == true {
                Rectangle().fill(.orange).frame(width: 4)
            } else if message.mentionsTarget {
                Rectangle().fill(.orange).frame(width: 3)
            } else if message.hasMajority {
                Rectangle().fill(.purple).frame(width: 3)
            }
        }
    }

    private func webSDRCycleHeader(_ group: WebSDRCycleGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.slot, format: .dateTime.hour().minute().second())
                .monospacedDigit()
            Text(group.isEven ? "RX EVEN · :00 / :30" : "RX ODD · :15 / :45")
            Text(Date().timeIntervalSince(group.slot) < 45 ? "· collecting" : "· late decodes possible")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(group.messages.count) signals")
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(group.isEven ? Color.green.opacity(0.25) : Color.blue.opacity(0.25))
    }

    private var webSDRAutomaticReceiversMenu: some View {
        Button("Receivers \(webSDR.selectedAutomaticEndpoints.count)") {
            showWebSDRReceivers.toggle()
            if showWebSDRReceivers { webSDR.checkAvailableReceivers() }
        }
        .popover(isPresented: $showWebSDRReceivers, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WebSDR receivers · \(webSDR.selectedBand)").font(.headline)
                Text("Green: site reachable · Red: site unavailable · Gray: checking")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button("One per region") { selectRegionalWebSDRs() }
                    Button("Select all") { webSDR.selectAllParallelEndpoints() }
                    Button("Primary only") { webSDR.clearParallelEndpoints() }
                }
                .font(.caption)
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(["AS", "EU", "AF", "NA", "SA", "OC"], id: \.self) { continent in
                            let endpoints = webSDR.availableAutomaticEndpoints.filter { $0.continent == continent }
                            if !endpoints.isEmpty {
                                Text(continentName(continent))
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                ForEach(endpoints) { endpoint in
                                    Button {
                                        webSDR.toggleParallelEndpoint(endpoint.id)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(webSDR.receiverHealth[endpoint.id].map { $0 ? Color.green : Color.red } ?? .gray)
                                                .frame(width: 8, height: 8)
                                            Text("\(endpoint.flag) \(endpoint.name)")
                                            Spacer()
                                            if endpoint.id == webSDR.primaryAutomaticEndpoint?.id {
                                                Text("Primary").foregroundStyle(.secondary)
                                            } else if webSDR.selectedParallelEndpointIDs.contains(endpoint.id) {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(endpoint.id == webSDR.primaryAutomaticEndpoint?.id)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                Button("Add a WebSDR for this band…") {
                    showWebSDRReceivers = false
                    customWebSDRError = ""
                    showCustomWebSDR = true
                }
                if !webSDR.customEndpoints.isEmpty {
                    Menu("Remove custom receiver") {
                        ForEach(webSDR.customEndpoints) { endpoint in
                            Button("\(endpoint.flag) \(endpoint.name)") {
                                webSDR.removeCustomEndpoint(endpoint.id)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 330, height: 430)
        }
        .help("Choose parallel receivers by region")
    }

    private var webSDRAudioControls: some View {
        HStack(spacing: 9) {
            Picker("Audio input", selection: $webSDR.selectedInputUID) {
                if webSDR.receiver.supportsAutomaticRecording {
                    Text("WebSDR audio · automatic").tag(WebSDRFT8Monitor.automaticRecordingUID)
                }
                Text("System Audio").tag(WebSDRFT8Monitor.systemAudioUID)
                ForEach(webSDR.audioInputs) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .frame(width: 330)
            .onChange(of: webSDR.selectedInputUID) { _, _ in
                webSDR.stop()
            }
            Button { webSDR.refreshInputs() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh audio inputs")
            if webSDR.selectedInputUID == WebSDRFT8Monitor.automaticRecordingUID {
                Toggle("Listen", isOn: $webSDR.listenToReceiver)
                    .toggleStyle(.checkbox)
            }
            Button("Show receiver") { webSDR.openReceiver() }
            Text("\(WebSDRFrequency.formattedMHz(webSDR.dialHz)) MHz USB · ~3 kHz")
                .foregroundStyle(.secondary)
            Toggle("DX sound", isOn: $webSDRDXAudioAlertsEnabled)
                .toggleStyle(.checkbox)
            Spacer(minLength: 0)
            Text(webSDR.status)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 460, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .controlSize(.small)
    }

    private func webSDRReplyControls(_ reply: WebSDRReplyPlan) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Expected reply to \(reply.partner)", systemImage: "arrowshape.turn.up.left.fill")
                    .font(.subheadline.bold())
                Spacer()
                if !replyFollowsLatest {
                    Button("Follow latest") {
                        replyFollowsLatest = true
                        followLatestWebSDRReply()
                    }
                    .font(.caption)
                }
                Text("IC-7300MK2")
                    .font(.caption.monospaced())
            }
            Text(reply.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("FT8 reply", text: $webSDRReplyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Picker("My TX slot", selection: $selectedWebSDRTxParity) {
                    Text("Even :00/:30").tag(SlotParity.even)
                    Text("Odd :15/:45").tag(SlotParity.odd)
                }
                .pickerStyle(.segmented)
                .frame(width: 290)
                Toggle("Arm TX", isOn: Binding(
                    get: { appState.ft8Engine.transmitArmed },
                    set: { appState.ft8Engine.transmitArmed = $0 }
                ))
                    .toggleStyle(.checkbox)
                Button("Queue next TX slot") { queueWebSDRReply(reply) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!WebSDRReplyPlanner.isReady(webSDRReplyDraft,
                                                           for: reply,
                                                           targetCallsign: engine.targetCallsign)
                              || !appState.ft8Engine.transmitArmed)
            }
            Text("Uses the selected TX parity and audio output in FT8 Station. Verify the partner's actual slot before arming; WebSDR delay may span whole cycles.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !webSDRReplyStatus.isEmpty {
                Text(webSDRReplyStatus)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var webSDRReceiverControls: some View {
        HStack(spacing: 8) {
            Text("WEBSDR FT8 · \(appState.activeStationProfile?.grid.isEmpty == false ? appState.activeStationProfile?.grid ?? "LM55rr" : "LM55rr")")
                .font(.caption.bold())
                .fixedSize()
            Button {
                showPrimaryWebSDRPicker.toggle()
                if showPrimaryWebSDRPicker { webSDR.checkAvailableReceivers() }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(webSDR.receiverHealth[webSDR.receiver.id].map { $0 ? Color.green : Color.red } ?? .gray)
                        .frame(width: 8, height: 8)
                    Text("\(webSDR.receiver.flag) \(webSDR.receiver.name) · \(webSDR.receiver.location)")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .frame(width: 275)
            }
            .popover(isPresented: $showPrimaryWebSDRPicker, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Choose a receiver").font(.headline)
                    Text("Only listed FT8 bands can be selected afterward.")
                        .font(.caption2).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(["AS", "EU", "AF", "NA", "SA", "OC"], id: \.self) { continent in
                                let receivers = WebSDRReceiver.presets.filter { $0.continent == continent }
                                if !receivers.isEmpty {
                                    Text(continentName(continent))
                                        .font(.caption.bold()).foregroundStyle(.secondary)
                                    ForEach(receivers) { receiver in
                                        Button {
                                            webSDR.selectedReceiverID = receiver.id
                                            showPrimaryWebSDRPicker = false
                                        } label: {
                                            HStack(spacing: 8) {
                                                Circle()
                                                    .fill(webSDR.receiverHealth[receiver.id].map { $0 ? Color.green : Color.red } ?? .gray)
                                                    .frame(width: 8, height: 8)
                                                Text("\(receiver.flag) \(receiver.name) · \(receiver.location)")
                                                Spacer()
                                                if !receiver.supportsAutomaticRecording {
                                                    Text("Manual").foregroundStyle(.secondary)
                                                }
                                                if receiver.id == webSDR.receiver.id {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .frame(width: 370, height: 480)
            }
            .onChange(of: webSDR.selectedReceiverID) { _, _ in
                webSDR.stop()
                webSDR.normalizeSelection()
                webSDR.checkReceiver(webSDR.receiver.id, url: webSDR.receiver.url)
                webSDRFrequencyDraft = WebSDRFrequency.formattedMHz(webSDR.dialHz)
                webSDRFrequencyError = ""
            }
            Picker("FT8 band", selection: $webSDR.selectedBand) {
                ForEach(WebSDRFT8Monitor.bands.filter { webSDR.receiver.bands.contains($0.name) }) { band in
                    Text(band.label).tag(band.name)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .onChange(of: webSDR.selectedBand) { _, _ in
                webSDR.stop()
                webSDR.normalizeSelection()
                webSDR.checkReceiver(webSDR.receiver.id, url: webSDR.receiver.url)
                webSDRFrequencyDraft = WebSDRFrequency.formattedMHz(webSDR.dialHz)
                webSDRFrequencyError = ""
            }
            if webSDR.selectedReceiverID == "utah" {
                Picker("Utah antenna", selection: $webSDR.selectedUtahReceiver) {
                    ForEach(webSDR.availableUtahReceivers) { receiver in
                        Text(receiver.label).tag(receiver.number)
                    }
                }
                .labelsHidden()
                .frame(width: 185)
                .onChange(of: webSDR.selectedUtahReceiver) { _, _ in
                    webSDR.stop()
                    if let receiver = webSDR.activeUtahReceiver {
                        webSDR.checkReceiver("utah-\(receiver.number)", url: receiver.url)
                    }
                }
            }
            if webSDR.selectedInputUID == WebSDRFT8Monitor.automaticRecordingUID {
                webSDRAutomaticReceiversMenu
            }
            Spacer(minLength: 0)
            Button {
                if icomPassword.isEmpty {
                    icomPassword = CredentialVault.valueIfAvailableWithoutPrompt(for: .icomNetworkPassword)
                }
                if icomModelName == IcomNetworkModel.ic705.rawValue {
                    icomModelName = IcomNetworkModel.ic7300MK2.rawValue
                }
                showIcomConnection = true
            } label: {
                Label("IC-7300MK2", systemImage: "radio")
            }
            .help("Configure IC-7300MK2 network connection")
            Button {
                if webSDR.isMonitoring {
                    webSDR.stop()
                } else {
                    if webSDRFrequencyDraft != WebSDRFrequency.formattedMHz(webSDR.dialHz) {
                        applyWebSDRFrequency()
                        guard webSDRFrequencyError.isEmpty else { return }
                    }
                    webSDR.start(targetCallsign: engine.targetCallsign)
                }
            } label: {
                Label(webSDR.isMonitoring ? "Stop receive" : "Start receive",
                      systemImage: webSDR.isMonitoring ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(webSDR.isMonitoring ? .red : .green)
        }
        .controlSize(.small)
    }

    private var webSDRManualFrequencyControls: some View {
        HStack(spacing: 8) {
            Label("Dial frequency", systemImage: "dial.low")
                .font(.caption.bold())
            TextField("14.074", text: $webSDRFrequencyDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 105)
                .onSubmit(applyWebSDRFrequency)
            Text("MHz · USB")
                .foregroundStyle(.secondary)
            Button("Tune") { applyWebSDRFrequency() }
                .disabled(webSDRFrequencyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if webSDR.manualDialHz != nil {
                Button("Use band preset") {
                    webSDR.usePresetFrequency()
                    webSDRFrequencyDraft = WebSDRFrequency.formattedMHz(webSDR.dialHz)
                    webSDRFrequencyError = ""
                }
            }
            if !webSDRFrequencyError.isEmpty {
                Label(webSDRFrequencyError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(webSDRFrequencyError)
            } else {
                Text("Enter a frequency in a band listed for this receiver. Tuning stops the current session.")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .controlSize(.small)
    }

    private func applyWebSDRFrequency() {
        webSDRFrequencyError = webSDR.applyManualFrequency(webSDRFrequencyDraft) ?? ""
        if webSDRFrequencyError.isEmpty {
            webSDRFrequencyDraft = WebSDRFrequency.formattedMHz(webSDR.dialHz)
        }
    }

    private var webSDRDecodedMessages: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if !activeDXAlert.isEmpty {
                    Label(activeDXAlert, systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.17), in: RoundedRectangle(cornerRadius: 6))
                }
                HStack(spacing: 6) {
                Image(systemName: "scope")
                    .foregroundStyle(.orange)
                Text("Target: \(engine.targetCallsign.isEmpty ? "set callsign above" : engine.targetCallsign)")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(webSDR.consensusTargetMatches.count) matching messages")
            }
            .font(.caption)
            .padding(6)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 10) {
                Text("Decoded messages").fixedSize(horizontal: true, vertical: false)
                Picker("Decoded messages", selection: $decodedMessageFilter) {
                    Text("All (\(webSDR.consensusMessages.count))").tag(0)
                    Text("\(engine.targetCallsign) (\(webSDR.consensusTargetMatches.count))").tag(1)
                    Text("New DX / band").tag(2)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 400)
            }
            if let warning = webSDR.noDecodeWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if visibleWebSDRCycleGroups.isEmpty {
                Text("No FT8 message in this view yet. Check the receiver frequency and audio playback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleWebSDRCycleGroups) { group in
                        webSDRCycleHeader(group)
                        ForEach(group.messages) { message in
                            webSDRMessageRow(message, in: group)
                            Divider().opacity(0.65)
                        }
                        Divider().background(Color.primary.opacity(0.35))
                    }
                }
            }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var webSDRReceiveControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            webSDRReceiverControls

            webSDRManualFrequencyControls

            webSDRAudioControls

            if webSDR.selectedInputUID == WebSDRFT8Monitor.systemAudioUID,
               !webSDR.systemAudioPermissionGranted {
                HStack(spacing: 6) {
                    Button("Request System Audio access") { webSDR.requestSystemAudioAccess() }
                    Text("Reopen YAAM after granting access. Automatic WebSDR audio needs no macOS capture permission.")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
            if webSDR.selectedAutomaticEndpoints.count > 1 {
                Text(webSDR.selectedAutomaticEndpoints.map {
                    "\($0.flag) \($0.name): \(webSDR.receiverStatuses[$0.id] ?? "Connecting…")"
                }.joined(separator: "   ·   "))
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            }
            if let phase = webSDR.phaseSeconds {
                Text("Audio phase: \(phase, specifier: "%.1f") s · stream lag modulo 15 s")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("Setup and timing", isExpanded: $showWebSDRSetup) {
                Text("Automatic mode tunes USB with an approximately 3 kHz passband. System Audio requires macOS capture access. FT8 text cannot identify absolute WebSDR delay across whole cycles.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
            if let reply = selectedWebSDRReply {
                webSDRReplyControls(reply)

            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func continentName(_ code: String) -> String {
        switch code {
        case "AS": "Asia"
        case "EU": "Europe"
        case "AF": "Africa"
        case "NA": "North America"
        case "SA": "South America"
        case "OC": "Oceania"
        default: code
        }
    }

    private var recommendedReceiverRegions: [ReceptionRegion] {
        let target = engine.targetCallsign.uppercased()
        let recent = engine.spots.filter {
            $0.senderCall.uppercased() == target && $0.band.lowercased() == webSDR.selectedBand.lowercased()
                && Date().timeIntervalSince($0.timestamp) < 1_800
        }
        let byContinent = Dictionary(grouping: recent) {
            DXCCDatabase.resolve(callsign: $0.receiverCall, country: $0.receiverCountry).continent
        }
        return byContinent.map { ReceptionRegion(region: $0.key, count: $0.value.count) }
            .filter { $0.region != "??" }
            .sorted { $0.count > $1.count }
    }

    private func selectRegionalWebSDRs() {
        for region in ["AS", "EU", "AF", "NA", "SA", "OC"] {
            let candidates = webSDR.availableAutomaticEndpoints.filter { $0.continent == region }
            guard let endpoint = candidates.first(where: { webSDR.receiverHealth[$0.id] == true })
                ?? candidates.first(where: { webSDR.receiverHealth[$0.id] != false }),
                  endpoint.id != webSDR.primaryAutomaticEndpoint?.id,
                  !webSDR.selectedParallelEndpointIDs.contains(endpoint.id) else { continue }
            webSDR.toggleParallelEndpoint(endpoint.id)
        }
    }

    private func scanDXOpportunities() {
        guard webSDR.isMonitoring else { return }
        let now = Date()
        for message in webSDR.consensusMessages where abs(now.timeIntervalSince(message.slotStart)) < 90 {
            guard let call = message.transmittingCallsign else { continue }
            let status = webSDRLogbook.status(for: call, band: webSDR.selectedBand)
            guard status.isNewDXCC || status.isNewBand else { continue }
            let key = "\(status.entity.entityName)|\(webSDR.selectedBand)"
            guard alertedDXKeys.insert(key).inserted else { continue }
            activeDXAlert = status.isNewDXCC
                ? "New DXCC: \(status.entity.flagEmoji) \(status.entity.entityName) · \(call)"
                : "New band: \(status.entity.flagEmoji) \(status.entity.entityName) on \(webSDR.selectedBand) · \(call)"
            if webSDRDXAudioAlertsEnabled && now.timeIntervalSince(lastDXAlertSoundAt) > 15 {
                NSSound(named: NSSound.Name("Glass"))?.play()
                lastDXAlertSoundAt = now
            }
            break
        }
    }

    private var customWebSDRSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a classic WebSDR receiver").font(.headline)
            Text("Enter the receiver page for \(webSDR.selectedBand). YAAM will tune it automatically and use its browser audio or WAV recorder when supported.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Receiver name", text: $customWebSDRName)
            TextField("http://receiver.example:8901/", text: $customWebSDRURL)
            HStack {
                Picker("Region", selection: $customWebSDRContinent) {
                    ForEach(["AS", "EU", "AF", "NA", "SA", "OC"], id: \.self) { code in
                        Text(continentName(code)).tag(code)
                    }
                }
                TextField("Flag emoji", text: $customWebSDRFlag)
                    .frame(width: 100)
            }
            if !customWebSDRError.isEmpty {
                Text(customWebSDRError).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { showCustomWebSDR = false }
                Button("Add receiver") {
                    guard webSDR.addCustomEndpoint(name: customWebSDRName, urlText: customWebSDRURL,
                                                   flag: customWebSDRFlag, continent: customWebSDRContinent) else {
                        customWebSDRError = "Enter a name and a valid http(s) receiver URL."
                        return
                    }
                    showCustomWebSDR = false
                    customWebSDRName = ""
                    customWebSDRURL = ""
                    customWebSDRFlag = ""
                    webSDR.checkAvailableReceivers()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 465)
    }

    private var icomConnectionSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IC-7300MK2 network connection").font(.headline)
            Text("Enter the radio's LAN address and Icom network credentials. The password is saved in macOS Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Model", selection: $icomModelName) {
                ForEach(IcomNetworkModel.allCases) { model in Text(model.rawValue).tag(model.rawValue) }
            }
            TextField("IP address or host", text: $icomHost)
            TextField("Control port", value: $icomPort, format: .number.grouping(.never))
            TextField("Username", text: $icomUsername)
            SecureField("Password", text: $icomPassword)
            HStack {
                Text(appState.icomNetworkRadio.state.title)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { showIcomConnection = false }
                Button(appState.icomNetworkRadio.state.canDisconnect ? "Disconnect" : "Connect") {
                    if appState.icomNetworkRadio.state.canDisconnect {
                        appState.icomNetworkRadio.disconnect()
                    } else {
                        let password = icomPassword.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !password.isEmpty { _ = CredentialVault.set(password, for: .icomNetworkPassword) }
                        appState.icomNetworkRadio.connect(settings: IcomNetworkSettings(
                            host: icomHost.trimmingCharacters(in: .whitespacesAndNewlines),
                            controlPort: icomPort,
                            username: icomUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                            clientName: icomClientName,
                            model: IcomNetworkModel(rawValue: icomModelName) ?? .ic7300MK2),
                            password: password)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 430)
    }

    private func followLatestWebSDRReply() {
        guard let plan = webSDR.consensusTargetMatches.lazy.compactMap({
            WebSDRReplyPlanner.plan(for: $0.text, targetCallsign: engine.targetCallsign)
        }).first else { return }
        guard selectedWebSDRReply != plan || webSDRReplyDraft.isEmpty else { return }
        selectedWebSDRReply = plan
        webSDRReplyDraft = plan.draft
        selectedWebSDRTxParity = appState.ft8Engine.txParity
        webSDRReplyStatus = ""
    }

    private func queueWebSDRReply(_ plan: WebSDRReplyPlan) {
        guard WebSDRReplyPlanner.isReady(webSDRReplyDraft, for: plan,
                                         targetCallsign: engine.targetCallsign) else {
            webSDRReplyStatus = "Enter your actual received report before transmitting."
            return
        }
        let ft8 = appState.ft8Engine
        ft8.txParity = selectedWebSDRTxParity
        if let issue = ft8.prepareWebSDRReply(webSDRReplyDraft,
                                               targetCallsign: engine.targetCallsign,
                                               grid: appState.activeStationProfile?.grid ?? "LM55",
                                               dialHz: UInt64(webSDR.dialHz),
                                               radio: appState.icomNetworkRadio,
                                               usbOutputUID: webSDRFT8OutputDeviceUID) {
            webSDRReplyStatus = issue
            return
        }
        ft8.scheduleTransmission()
        webSDRReplyStatus = ft8.status
    }

    // Sub-Table 1: Live Spots Table View
    private var liveSpotsTableView: some View {
        let filtered = engine.spots.filter { spot in
            guard !streamFilterText.isEmpty else { return true }
            let q = streamFilterText.uppercased()
            return spot.receiverCall.contains(q) || spot.receiverGrid.contains(q) || spot.band.uppercased().contains(q) || spot.receiverCountry.uppercased().contains(q)
        }

        return Group {
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(engine.status.isLive ? "Listening for digital transmissions..." : "No spots detected in window")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(engine.status.isLive ? "Waiting for \(engine.targetCallsign) to transmit on FT8/FT4." : "Click 'Start Live Track' to begin real-time monitoring.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filtered) { spot in
                    spotRowView(spot)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                .listStyle(.plain)
            }
        }
    }

    private func spotRowView(_ spot: HamTrackSpot) -> some View {
        HStack(spacing: 8) {
            // Live MQTT Indicator vs History
            if spot.isRealtimeMQTT {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .help("Live MQTT packet from mqtt.pskreporter.info")
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .help("Historical report from sliding window")
            }

            // Spotter Call & Flag
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(spot.receiverFlag)
                    Text(spot.receiverCall)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    if !spot.receiverGrid.isEmpty {
                        Text(spot.receiverGrid)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(spot.receiverCountry)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            // SNR Badge
            Text("\(spot.snr > 0 ? "+" : "")\(spot.snr) dB")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(spot.snrBadgeColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(spot.snrBadgeColor)

            // Distance & Bearing
            VStack(alignment: .trailing, spacing: 1) {
                if let dist = spot.distanceKm {
                    Text(String(format: "%.0f km", dist))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                if let comp = spot.bearingCompass, let brg = spot.bearingDeg {
                    Text("\(Int(brg))° \(comp)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 65, alignment: .trailing)

            // Cycle & Time
            VStack(alignment: .trailing, spacing: 1) {
                Text(timeString(from: spot.timestamp))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(spot.cycleType)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 68, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Check WebSDR messages for \(engine.targetCallsign)") {
                isWebSDRWorkspace = true
            }

            if let brg = spot.bearingDeg {
                Button("Turn Rotator to \(Int(brg))° (\(spot.receiverCall))") {
                    rotatorService.turnTo(azimuth: brg)
                    rotatorActionNotification = "Rotator turning to \(Int(brg))°"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        rotatorActionNotification = nil
                    }
                }
            }

            Button("Tune Transceiver to \(String(format: "%.4f", spot.frequencyMHz)) MHz") {
                tuneTransceiver(freqMHz: spot.frequencyMHz)
            }

            Divider()

            Button("View \(spot.receiverCall) in Call Intelligence") {
                appState.quickLogDraft.callsign = spot.receiverCall
                appState.openOperatorDesk(.quickLog)
            }
        }
    }

    // Sub-Table 2: DX Cluster Spots
    private var clusterSpotsTableView: some View {
        Group {
            if engine.clusterSpots.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No DX Cluster spots for \(engine.targetCallsign)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Button("Query Cluster Now") {
                        engine.refreshClusterSpots()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(engine.clusterSpots) { spot in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(spot.spotterCall)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(.blue)

                            if spot.frequencyKHz > 0 {
                                Text(String(format: "%.1f kHz", spot.frequencyKHz))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }

                            Spacer()

                            Text(spot.timeString)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Text(spot.comment)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain)
            }
        }
    }

    // Sub-Table 3: Top Spotters Table
    private var topSpottersTableView: some View {
        let uniqueList = computeUniqueSpotters()

        return List(uniqueList, id: \.callsign) { item in
            HStack(spacing: 8) {
                Text(item.flag)
                Text(item.callsign)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))

                Text(item.country)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Text("Max \(item.maxSNR > 0 ? "+" : "")\(item.maxSNR) dB")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(snrColor(item.maxSNR))

                Text(String(format: "%.0f km", item.distanceKm))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("\(item.count) spots")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
        }
        .listStyle(.plain)
    }

    private struct UniqueSpotterItem {
        let callsign: String
        let flag: String
        let country: String
        let maxSNR: Int
        let distanceKm: Double
        let count: Int
    }

    private func computeUniqueSpotters() -> [UniqueSpotterItem] {
        var dict: [String: [HamTrackSpot]] = [:]
        for s in engine.spots {
            dict[s.receiverCall, default: []].append(s)
        }

        return dict.compactMap { call, spots in
            guard let first = spots.first else { return nil }
            let maxSNR = spots.map(\.snr).max() ?? 0
            let dist = spots.compactMap(\.distanceKm).max() ?? 0.0
            return UniqueSpotterItem(
                callsign: call,
                flag: first.receiverFlag,
                country: first.receiverCountry,
                maxSNR: maxSNR,
                distanceKm: dist,
                count: spots.count
            )
        }.sorted(by: { $0.maxSNR > $1.maxSNR })
    }

    // Sub-Table 4: Partner Contacts Table View (Active Live Contact + Session Completed Contacts)
    private var partnerContactsTableView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Section 1: Active Partner Right Now
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.line.dotted.person.fill")
                            .foregroundStyle(engine.activePartner != nil ? .green : .secondary)
                            .font(.system(size: 12))
                        Text("POSSIBLE PARTNER · SPOT INFERENCE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(engine.activePartner != nil ? .green : .secondary)
                        Spacer()
                        if let partner = engine.activePartner {
                            Text("\(partner.confidencePercentage)% SPOT SCORE")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(partner.confidenceBadgeColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(partner.confidenceBadgeColor)
                        }
                    }

                    if let partner = engine.activePartner {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Text(partner.flag)
                                    .font(.system(size: 24))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(partner.callsign)
                                            .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                            .foregroundStyle(.primary)

                                        if !partner.grid.isEmpty {
                                            Text("[\(partner.grid)]")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Text(partner.country)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.swap")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.cyan)
                                        Text("\(partner.matchedCyclesCount) Matched cycles")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    }

                                    Text("\(partner.frequencyOffsetHz >= 0 ? "+" : "")\(partner.frequencyOffsetHz) Hz offset")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(abs(partner.frequencyOffsetHz) <= 15 ? Color.green : Color.cyan)

                                    if let dist = partner.distanceKmFromTarget {
                                        Text(String(format: "%.0f km from target", dist))
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Divider()

                            HStack(spacing: 8) {
                                Button {
                                    isWebSDRWorkspace = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "waveform")
                                        Text("Check WebSDR messages")
                                    }
                                    .font(.system(size: 10.5, weight: .bold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.6), lineWidth: 1))
                                    .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    engine.switchTracker(to: partner.callsign)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text("Track Partner")
                                    }
                                    .font(.system(size: 10.5, weight: .bold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.6), lineWidth: 1))
                                    .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Menu {
                                    Button("Tune Transceiver to \(String(format: "%.4f", partner.frequencyMHz)) MHz") {
                                        tuneTransceiver(freqMHz: partner.frequencyMHz)
                                    }
                                    if let brg = partner.bearingDegFromTarget {
                                        Button("Turn Rotator to \(Int(brg))°") {
                                            rotatorService.turnTo(azimuth: brg)
                                            rotatorActionNotification = "Rotator turning to \(Int(brg))°"
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                                rotatorActionNotification = nil
                                            }
                                        }
                                    }
                                    Divider()
                                    Button("View in Call Intelligence") {
                                        appState.quickLogDraft.callsign = partner.callsign
                                        appState.openOperatorDesk(.quickLog)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 18)
                            }
                        }
                        .padding(11)
                        .background(
                            LinearGradient(
                                colors: [Color.green.opacity(0.12), Color.blue.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.4), lineWidth: 1.2))
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: engine.cycleStatus.isTargetTransmittingNow ? "waveform.badge.magnifyingglass" : "antenna.radiowaves.left.and.right")
                                .foregroundStyle(engine.cycleStatus.isTargetTransmittingNow ? .red : .secondary)
                                .font(.system(size: 14))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.cycleStatus.isTargetTransmittingNow ? "\(engine.targetCallsign.isEmpty ? "Target" : engine.targetCallsign) may be calling CQ" : "No partner inferred from spots")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.primary)

                                Text(engine.cycleStatus.isTargetTransmittingNow ? "Watch the alternate cycle for possible replies; use WebSDR RX to read them." : "Spot timing and frequency may suggest a partner; WebSDR RX shows decoded replies.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Divider()

                // Section 2: Completed Contacts This Session
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("EXCHANGES INFERRED FROM SPOTS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(engine.recentCompletedQSOs.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }

                    if engine.recentCompletedQSOs.isEmpty {
                        VStack(spacing: 6) {
                            Text("No exchange inferred from spots in this session.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            Text("These correlations cannot confirm message contents or a completed QSO.")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        ForEach(engine.recentCompletedQSOs) { qso in
                            HStack(spacing: 8) {
                                Text(qso.flag)
                                    .font(.system(size: 16))

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(qso.callsign)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        if !qso.grid.isEmpty {
                                            Text("[\(qso.grid)]")
                                                .font(.system(size: 9.5, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(qso.country)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 1) {
                                    Text("\(qso.band) • \(qso.mode)")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("\(qso.totalCycles) cycles • \(qso.timeAgoDescription)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }

                                Button {
                                    isWebSDRWorkspace = true
                                } label: {
                                    HStack(spacing: 2) {
                                        Image(systemName: "waveform")
                                        Text("Verify")
                                    }
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)
                                .help("Check decoded WebSDR messages before logging \(qso.callsign)")

                                Button {
                                    engine.switchTracker(to: qso.callsign)
                                } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 9.5))
                                        .padding(4)
                                        .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .help("Track \(qso.callsign)")
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    // MARK: - 5. Bottom Action Toolbar

    private var bottomActionToolbar: some View {
        HStack(spacing: 10) {
            // Action 1: Pre-fill Quick Log
            Button {
                appState.quickLogDraft.callsign = engine.targetCallsign
                if !engine.statistics.primaryBand.isEmpty {
                    appState.quickLogDraft.band = engine.statistics.primaryBand
                }
                if !engine.statistics.primaryMode.isEmpty {
                    appState.quickLogDraft.mode = engine.statistics.primaryMode
                }
                appState.openOperatorDesk(.quickLog)
            } label: {
                Label("Log in Quick Log", systemImage: "plus.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            // Action 2: Tune Radio (CAT)
            if engine.statistics.primaryFrequencyMHz > 0 {
                Button {
                    tuneTransceiver(freqMHz: engine.statistics.primaryFrequencyMHz)
                } label: {
                    Label("Tune Radio (CAT)", systemImage: "radio")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Action 3: Align Rotator to Furthest or Average Bearing
            if engine.statistics.furthestDistanceKm > 0,
               let bestSpot = engine.spots.first(where: { $0.bearingDeg != nil }),
               let az = bestSpot.bearingDeg {
                Button {
                    rotatorService.turnTo(azimuth: az)
                    rotatorActionNotification = "Turning Rotator to \(Int(az))°"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        rotatorActionNotification = nil
                    }
                } label: {
                    Label("Turn Rotator \(Int(az))°", systemImage: "location.north.line.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Action 4: Open Call Intelligence
            Button {
                appState.quickLogDraft.callsign = engine.targetCallsign
                appState.openOperatorDesk(.quickLog)
            } label: {
                Label("Call Intelligence", systemImage: "brain.head.profile")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            // Action 5: PSKReporter Web Map
            Button {
                let urlStr = "https://pskreporter.info/pskmap.html?preset&callsign=\(engine.targetCallsign)"
                if let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("PSKReporter Map", systemImage: "safari")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            // Action 6: Copy Activity Summary
            Button {
                copyActivitySummary()
            } label: {
                Label(showExportNotification ? "Copied!" : "Copy Report", systemImage: showExportNotification ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(showExportNotification ? .green : .secondary)
        }
    }

    // MARK: - CLI Diagnostic Sheet

    private var cliDiagnosticSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.green)
                    Text("ham_tracker.py :: Python CLI Runner & Diagnostics")
                        .font(.headline)
                }

                Spacer()

                Button("Close") {
                    isShowingCLISheet = false
                }
                .keyboardShortcut(.cancelAction)
            }

            Text("Executes the exact ham_tracker.py script via macOS Terminal sub-process and prints its live raw socket / MQTT feed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Run Controls
            HStack(spacing: 10) {
                Button {
                    engine.runPythonScript(callsign: engine.targetCallsign, duration: 15, detectPartner: false)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text(engine.isRunningCLI ? "Running..." : "Run ham_tracker.py (15s)")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(engine.isRunningCLI || engine.targetCallsign.isEmpty)

                Button {
                    engine.runPythonScript(callsign: engine.targetCallsign, duration: 30, detectPartner: true)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.wave.2")
                        Text(engine.isRunningCLI ? "Running..." : "Detect Partner (--partner 30s)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(engine.isRunningCLI || engine.targetCallsign.isEmpty)

                if engine.isRunningCLI {
                    ProgressView().controlSize(.small)
                }
            }

            // Terminal Screen
            ScrollView {
                Text(engine.cliTerminalLog.isEmpty ? "Click 'Run ham_tracker.py' or 'Detect Partner' to execute Python test script." : engine.cliTerminalLog)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color.black, in: RoundedRectangle(cornerRadius: 6))
            .frame(height: 280)
        }
        .padding(16)
        .frame(width: 640, height: 420)
    }

    // MARK: - Helpers

    private func tuneTransceiver(freqMHz: Double) {
        let hz = UInt64(freqMHz * 1_000_000.0)
        appState.rigControlClient.setFrequencyHz(hz)
    }

    private func copyActivitySummary() {
        var text = "=== YAAM HAM TRACKER ACTIVITY REPORT ===\n"
        text += "Target Callsign: \(engine.targetCallsign) (\(engine.statistics.targetFlag) \(engine.statistics.targetCountry))\n"
        if let partner = engine.activePartner {
            text += "Possible partner from spot correlation: \(partner.flag) \(partner.callsign) (\(partner.country)) [\(partner.grid)] | Matched cycles: \(partner.matchedCyclesCount) | Offset: \(partner.frequencyOffsetHz >= 0 ? "+" : "")\(partner.frequencyOffsetHz) Hz | Spot score: \(partner.confidencePercentage)%\n"
        }
        text += "Primary Frequency: \(String(format: "%.4f", engine.statistics.primaryFrequencyMHz)) MHz (\(engine.statistics.primaryBand) \(engine.statistics.primaryMode))\n"
        text += "Transmission Cadence: \(engine.cycleStatus.detectedCadence)\n"
        text += "Total Spotters: \(engine.statistics.uniqueSpottersCount) stations\n"
        text += "Average SNR: \(String(format: "%+.1f dB", engine.statistics.averageSNR))\n"
        text += "Peak Spotter: \(engine.statistics.peakSpotter) (\(engine.statistics.peakSNR) dB)\n"
        text += "Furthest DX: \(engine.statistics.furthestFlag) \(engine.statistics.furthestSpotter) (\(String(format: "%.0f km", engine.statistics.furthestDistanceKm)))\n\n"
        text += "--- Recent Spotters ---\n"
        for s in engine.spots.prefix(15) {
            text += "[\(timeString(from: s.timestamp))] \(s.receiverCall) (\(s.receiverGrid)) | SNR: \(s.snr > 0 ? "+" : "")\(s.snr) dB | \(s.cycleType)\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        showExportNotification = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showExportNotification = false
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date) + "Z"
    }

    private func snrColor(_ snr: Int) -> Color {
        if snr >= 0 { return .green }
        if snr >= -10 { return .cyan }
        if snr >= -18 { return .orange }
        return .purple
    }
}
