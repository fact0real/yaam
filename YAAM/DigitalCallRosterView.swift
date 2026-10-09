//
//  DigitalCallRosterView.swift
//  YAAM
//
//  Live Digital Call Roster Console for macOS.
//  Real-time triage of WSJT-X / JTDX and internal FT8 decodes, matching against
//  the Master Log for New DXCC, New Band, New Grid, and 1-Click Double-Click Reply.
//

import AppKit
import AVFoundation
import FT8Codec
import FT8808Engine
import SwiftUI

public struct DigitalCallRosterView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var roster = DigitalCallRosterEngine.shared
    @ObservedObject private var audioAlerts = DigitalAudioAlertEngine.shared
    @ObservedObject private var targetQueue = DigitalTargetQueueEngine.shared
    @ObservedObject private var waitAndPounce = WaitAndPounceEngine.shared

    @State private var filterMode: RosterFilterMode = .neededOnly
    @State private var selectedSlice: String = "All"
    @State private var minSNRFilter: Int = -30
    @State private var searchText: String = ""
    @State private var manualSnipeInput: String = ""
    @State private var selectedEntryID: UUID? = nil
    @State private var showingAudioSettings = false
    @State private var showingUDPConfigPopover = false
    @State private var showingDetailSheet = false
    @State private var selectedEntryForDetail: DigitalRosterEntry? = nil
    /// Why the last reply sent nothing (no callsign or locator of the operator, or one that is not accepted).
    @State private var replyNotice: String = ""

    public enum RosterFilterMode: String, CaseIterable, Identifiable {
        case neededOnly = "⚡️ Needed"
        case cqOnly = "CQ Only"
        case directedToMe = "To Me"
        case all = "All Decodes"

        public var id: String { rawValue }
    }

    public init() {}

    private var activeBand: String {
        let reported = appState.wsjtxListener.lastStatus?.band.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reported.isEmpty ? "20M" : reported.uppercased()
    }

    private var filteredEntries: [DigitalRosterEntry] {
        roster.entries.filter { entry in
            // Filter mode
            switch filterMode {
            case .neededOnly:
                if !entry.status.isNeeded { return false }
            case .cqOnly:
                if !entry.isCQ { return false }
            case .directedToMe:
                if !entry.isToMe { return false }
            case .all:
                break
            }

            // Min SNR
            if entry.snr < Int32(minSNRFilter) {
                return false
            }

            // Search query
            if !searchText.isEmpty {
                let q = searchText.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let matchesCall = entry.callsign.contains(q)
                let matchesCountry = entry.countryInfo.entityName.uppercased().contains(q)
                let matchesGrid = entry.grid.contains(q)
                let matchesMsg = entry.message.uppercased().contains(q)
                if !matchesCall && !matchesCountry && !matchesGrid && !matchesMsg {
                    return false
                }
            }

            // Slice / Modem Source Filter
            if selectedSlice == "VFO A" && entry.sliceLabel != "VFO A" { return false }
            if selectedSlice == "VFO B" && entry.sliceLabel != "VFO B" { return false }
            if selectedSlice == "VFO C" && entry.sliceLabel != "VFO C" { return false }
            if selectedSlice == "VFO D" && entry.sliceLabel != "VFO D" { return false }
            if selectedSlice == "Internal" && entry.sliceLabel != "Internal" { return false }

            return true
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            topControlBar
            Divider()
            TacticalPilotHUDView()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            Divider()

            waitAndPounceSniperHUD
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            Divider()

            if targetQueue.activeTarget != nil || !targetQueue.queue.isEmpty {
                targetQueueStrip
                Divider()
            }

            filterAndStatsBar
            Divider()

            if !replyNotice.isEmpty {
                Text(replyNotice)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                Divider()
            }

            if filteredEntries.isEmpty {
                emptyRosterState
            } else {
                rosterTable
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingAudioSettings) {
            audioSettingsSheet
        }
        .sheet(item: $selectedEntryForDetail) { entry in
            entryDetailSheet(entry)
        }
        .onAppear {
            if !appState.wsjtxListener.state.isListening {
                appState.wsjtxListener.start()
            }
            syncContextAndRebuild()
            if !appState.wsjtxListener.liveDecodes.isEmpty {
                roster.processDecodes(appState.wsjtxListener.liveDecodes, activeBand: activeBand)
            }
            if !appState.ft8Engine.decodedRows.isEmpty {
                processInternalDecodes(appState.ft8Engine.decodedRows)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("DigitalTargetQueueDidTriggerCall"))) { notif in
            if let call = notif.userInfo?["callsign"] as? String,
               let match = roster.entries.first(where: { $0.callsign == call }) {
                callStation(match)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TransmitIdentity.identityChanged)) { _ in
            // A refusal shown for the previous profile no longer applies.
            replyNotice = ""
        }
        .onChange(of: appState.qsoRecordsRevision) { _, _ in
            roster.rebuildLogCache(records: appState.qsoRecords)
        }
        .onChange(of: appState.wsjtxListener.liveDecodes) { _, newDecodes in
            roster.processDecodes(newDecodes, activeBand: activeBand)
        }
        .onChange(of: appState.ft8Engine.decodedRows) { _, internalRows in
            processInternalDecodes(internalRows)
        }
    }

    private func processInternalDecodes(_ rows: [FT8DecodedRow]) {
        guard !rows.isEmpty else { return }
        let liveDecodes: [WSJTXLiveDecode] = rows.map { row in
            WSJTXLiveDecode(
                sourceID: "YAAM Internal FT8",
                isNew: true,
                timeMillis: UInt32(row.slotStart.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) * 1000),
                snr: Int32(row.estimatedSNR),
                deltaTimeSec: Double(row.timeOffset),
                deltaFrequencyHz: UInt32(max(0, row.audioFrequencyHz)),
                mode: appState.ft8Engine.operatingProtocol == .ft4 ? "FT4" : "FT8",
                message: row.text,
                lowConfidence: false,
                offAir: false,
                receivedAt: row.slotStart,
                callerCallsign: row.callerCall ?? "",
                targetCallsign: row.parsed?.toCall ?? "",
                grid: row.callerGrid ?? (row.parsed?.grid ?? ""),
                report: row.parsed?.report.map(String.init) ?? "",
                port: 0,
                sliceLabel: "Internal"
            )
        }
        roster.processDecodes(liveDecodes, activeBand: activeBand)
    }

    // MARK: - Wait & Pounce Sniper Console HUD

    // MARK: - Wait & Pounce Sniper Console HUD

    private var waitAndPounceSniperHUD: some View {
        VStack(spacing: 8) {
            waitAndPounceTopControlRow
            waitAndPounceCycleBar
            waitAndPounceBottomTelemetryRow
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(waitAndPounce.status.isArmedOrTracking ? waitAndPounce.status.badgeColor.opacity(0.5) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var waitAndPounceTopControlRow: some View {
        HStack(spacing: 10) {
            Button {
                waitAndPounce.isEnabled.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "scope")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(waitAndPounce.isEnabled ? Color.red : Color.secondary)
                    Text(waitAndPounce.isEnabled ? "SNIPER ACTIVE" : "Wait & Pounce Standby")
                        .font(.system(size: 10, weight: .black))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(waitAndPounce.isEnabled ? Color.red.opacity(0.18) : Color.gray.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(TargetHuntMode.allCases) { mode in
                    Button {
                        waitAndPounce.huntMode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: mode.iconName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: waitAndPounce.huntMode.iconName)
                        .font(.system(size: 10))
                    Text(waitAndPounce.huntMode.shortLabel)
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
            .menuStyle(.borderedButton)
            .fixedSize()

            Menu {
                ForEach(PounceFrequencyMode.allCases) { fq in
                    Button(fq.rawValue) {
                        waitAndPounce.frequencyMode = fq
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 9))
                    Text(waitAndPounce.frequencyMode == .simplex ? "Simplex" : "Split")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
            .menuStyle(.borderedButton)
            .fixedSize()

            HStack(spacing: 4) {
                Text("Tries:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(waitAndPounce.maxAttempts)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                Stepper("", value: $waitAndPounce.maxAttempts, in: 1...5)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 4) {
                TextField("Snipe Call...", text: $manualSnipeInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(width: 80)
                    .onSubmit {
                        quickSnipeInputTarget()
                    }
                Button("Snipe") {
                    quickSnipeInputTarget()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(.red)
                .disabled(manualSnipeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 9))
                Text(String(format: "Cycle: %.1fs", waitAndPounce.secondsRemainingInCycle))
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(waitAndPounce.secondsRemainingInCycle <= 2.0 ? Color.orange : Color.secondary)

            if waitAndPounce.status.isArmedOrTracking || waitAndPounce.status.isActivelyCalling {
                Button {
                    waitAndPounce.haltAndDisarm()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 9))
                        Text("HALT TX")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var waitAndPounceCycleBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 3)
                    .fill(cycleBarColor)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * waitAndPounce.cycleProgressPercentage)), height: 6)
            }
        }
        .frame(height: 6)
    }

    private var waitAndPounceBottomTelemetryRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: waitAndPounce.status.badgeIcon)
                    .font(.system(size: 10))
                Text(waitAndPounce.status.title)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(waitAndPounce.status == .idle ? Color.secondary : Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(waitAndPounce.status.badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if let target = waitAndPounce.activeTarget {
                HStack(spacing: 6) {
                    Text(target.flagEmoji)
                        .font(.system(size: 12))
                    Text(target.callsign)
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.red)
                    if !target.countryName.isEmpty {
                        Text(target.countryName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("(\(target.snr >= 0 ? "+\(target.snr)" : "\(target.snr)") dB • \(target.deltaFrequencyHz) Hz)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        waitAndPounce.clearTarget()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear sniper target")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text(waitAndPounce.lastEventMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Test W&P Simulation") {
                runWaitAndPounceSimulation()
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .font(.system(size: 9))
            .help("Simulate a DX target ending a QSO with RR73 to test W&P reaction")
        }
    }

    private var cycleBarColor: Color {
        let sec = waitAndPounce.secondsRemainingInCycle
        if waitAndPounce.status.isActivelyCalling {
            return .red
        } else if sec <= 0.4 {
            return .yellow
        } else if sec <= 2.5 {
            return .orange
        } else {
            return .accentColor
        }
    }

    private func quickSnipeInputTarget() {
        let clean = manualSnipeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        waitAndPounce.setTarget(callsign: clean)
        manualSnipeInput = ""
    }

    private func runWaitAndPounceSimulation() {
        let dxCall = "3D2RR"
        waitAndPounce.setTarget(callsign: dxCall, grid: "RH42", deltaHz: 1420, mode: "FT8")

        // Feed cycle 1: Target in QSO with W1AW
        let dec1 = WSJTXLiveDecode(
            sourceID: "Simulation",
            isNew: true,
            timeMillis: 120000,
            snr: 12,
            deltaTimeSec: 0.1,
            deltaFrequencyHz: 1420,
            mode: "FT8",
            message: "W1AW 3D2RR -12",
            lowConfidence: false,
            offAir: false,
            callerCallsign: "3D2RR",
            targetCallsign: "W1AW",
            grid: "RH42",
            report: "-12"
        )
        waitAndPounce.processDecodes([dec1], activeBand: activeBand)

        // After 2.5 seconds, simulate target sending RR73!
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let dec2 = WSJTXLiveDecode(
                sourceID: "Simulation",
                isNew: true,
                timeMillis: 135000,
                snr: 14,
                deltaTimeSec: 0.1,
                deltaFrequencyHz: 1420,
                mode: "FT8",
                message: "W1AW 3D2RR RR73",
                lowConfidence: false,
                offAir: false,
                callerCallsign: "3D2RR",
                targetCallsign: "W1AW",
                grid: "RH42",
                report: "RR73"
            )
            waitAndPounce.processDecodes([dec2], activeBand: activeBand)
        }
    }

    // MARK: - Smart Target Auto-Pilot Queue Strip

    private var targetQueueStrip: some View {
        HStack(spacing: 10) {
            Button {
                targetQueue.toggleAutoPilot()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: targetQueue.isAutoPilotActive ? "bolt.circle.fill" : "bolt.slash.circle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(targetQueue.isAutoPilotActive ? Color.yellow : Color.secondary)
                    Text(targetQueue.isAutoPilotActive ? "AUTO-PILOT ACTIVE" : "Auto-Pilot Standby")
                        .font(.system(size: 10, weight: .black))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(targetQueue.isAutoPilotActive ? Color.yellow.opacity(0.18) : Color.gray.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Cycle Countdown
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 10))
                Text(String(format: "Cycle: %.1fs", targetQueue.secondsRemainingInCycle))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.secondary)

            // Active Target Pill
            if let active = targetQueue.activeTarget {
                HStack(spacing: 6) {
                    Text("CALLING:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(active.callsign)
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    Text(active.grid)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Try \(active.attempts)/\(active.maxAttempts)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())

                    Button {
                        targetQueue.advanceToNextTarget()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Skip to next in queue")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Spacer()

            // Queue count & Clear
            if !targetQueue.queue.isEmpty {
                HStack(spacing: 6) {
                    Text("Queue: \(targetQueue.queue.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    ForEach(targetQueue.queue.prefix(3)) { item in
                        Text(item.callsign)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    Button("Clear") {
                        targetQueue.clear()
                    }
                    .font(.system(size: 9))
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(NSColor.textBackgroundColor).opacity(0.6))
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.and.person.filled")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Digital Call Roster")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("Real-Time FT8/FT4 Triage & Smart Log-Needs Matching")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Transceiver CAT Control HUD
            RigControlToolbarView()

            // Antenna Rotator Control HUD
            RotatorToolbarWidgetView()

            // Radio / Dial Band Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.wsjtxListener.state.isListening ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(appState.wsjtxListener.lastStatus?.frequencyMHz.isEmpty == false ?
                     "\(appState.wsjtxListener.lastStatus!.frequencyMHz) MHz (\(activeBand))" :
                     "Band: \(activeBand)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            // WSJT-X / JTDX Ingestion UDP Button & Popover
            Button {
                showingUDPConfigPopover.toggle()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.wsjtxListener.state.isListening ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text(appState.wsjtxListener.state.isListening ? "Listening (\(String(appState.wsjtxListener.currentPort)))" : "UDP (\(String(appState.wsjtxListener.currentPort))) Off")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(appState.wsjtxListener.state.isListening ? .green : .secondary)
            .popover(isPresented: $showingUDPConfigPopover) {
                UDPPortConfigPopoverView()
            }
            .help("Configure UDP port and ingestion for WSJT-X / JTDX / SDR-Control")

            // Audio Speech Alerts Popover Button
            Button {
                showingAudioSettings = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: audioAlerts.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundColor(audioAlerts.isEnabled ? .accentColor : .secondary)
                    Text("Voice Alerts")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .help("Configure Hands-Free Audio Speech Alerts")

            // Clear Roster Button
            Button {
                roster.clearRoster()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Clear current roster entries")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Filter & Counters Bar

    private func sliceLabelDisplay(_ slice: String) -> String {
        switch slice {
        case "All": return "All Slices"
        case "Internal": return "Internal FT8"
        case "VFO A": return "VFO A (2237)"
        case "VFO B": return "VFO B (2238)"
        case "VFO C": return "VFO C (2239)"
        case "VFO D": return "VFO D (2240)"
        default: return slice
        }
    }

    private var filterAndStatsBar: some View {
        HStack(spacing: 10) {
            // Mode Segmented Control
            Picker("", selection: $filterMode) {
                ForEach(RosterFilterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            // Multi-Slice & Internal Modem Selector
            Menu {
                Button {
                    selectedSlice = "All"
                } label: {
                    Label("All Slices & Modem", systemImage: "antenna.radiowaves.left.and.right")
                }

                Divider()

                Button {
                    selectedSlice = "Internal"
                } label: {
                    Label("Internal Modem (Direct Icom / Audio)", systemImage: "waveform.circle.fill")
                }

                Divider()

                Button {
                    selectedSlice = "VFO A"
                } label: {
                    Label("VFO A (UDP 2237)", systemImage: "1.circle")
                }

                Button {
                    selectedSlice = "VFO B"
                } label: {
                    Label("VFO B (UDP 2238)", systemImage: "2.circle")
                }

                Button {
                    selectedSlice = "VFO C"
                } label: {
                    Label("VFO C (UDP 2239)", systemImage: "3.circle")
                }

                Button {
                    selectedSlice = "VFO D"
                } label: {
                    Label("VFO D (UDP 2240)", systemImage: "4.circle")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: selectedSlice == "Internal" ? "waveform.circle.fill" : "antenna.radiowaves.left.and.right")
                        .foregroundColor(.accentColor)
                    Text(sliceLabelDisplay(selectedSlice))
                }
                .font(.caption)
            }
            .menuStyle(.borderedButton)
            .fixedSize()

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            // Min SNR Filter
            Menu {
                Button("All Signals") { minSNRFilter = -30 }
                Divider()
                Button("≥ -20 dB") { minSNRFilter = -20 }
                Button("≥ -15 dB") { minSNRFilter = -15 }
                Button("≥ -10 dB") { minSNRFilter = -10 }
                Button("≥ -5 dB") { minSNRFilter = -5 }
                Button("≥ 0 dB (Strong)") { minSNRFilter = 0 }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                    Text(minSNRFilter <= -30 ? "SNR: All" : "SNR ≥ \(minSNRFilter) dB")
                }
                .font(.caption)
            }
            .menuStyle(.borderedButton)
            .fixedSize()

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            // Search Field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search call, grid, country...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(minWidth: 130, maxWidth: 200)

            Spacer()

            // Summary Badges
            HStack(spacing: 8) {
                summaryBadge(title: "Total", count: roster.totalDecodesCount, color: .primary)
                summaryBadge(title: "Needed", count: roster.neededCount, color: .purple)
                summaryBadge(title: "CQs", count: roster.cqCount, color: .blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func summaryBadge(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(count)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }

    // MARK: - Roster Table

    private var rosterTable: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                // Table Header
                tableHeaderView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

                ForEach(filteredEntries) { entry in
                    rosterRow(entry)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            selectedEntryID == entry.id ?
                                Color.accentColor.opacity(0.15) :
                                (entry.status.isNeeded ? entry.status.badgeColor.opacity(0.06) : Color(NSColor.controlBackgroundColor).opacity(0.3))
                        )
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEntryID = entry.id
                        }
                        .onTapGesture(count: 2) {
                            callStation(entry)
                        }
                        .contextMenu {
                            Button("🎯 Wait & Pounce on \(entry.callsign)") {
                                waitAndPounce.setTarget(
                                    callsign: entry.callsign,
                                    grid: entry.grid,
                                    deltaHz: entry.deltaFrequencyHz,
                                    mode: entry.mode,
                                    interlocutor: entry.targetCallsign,
                                    snr: entry.snr,
                                    rawDecode: entry.rawDecode
                                )
                            }
                            Button("Call \(entry.callsign) (Reply)") {
                                callStation(entry)
                            }
                            Button("Inspect Details & Log History") {
                                selectedEntryForDetail = entry
                            }
                            Button("Open QRZ.com (\(entry.callsign))") {
                                if let url = URL(string: "https://www.qrz.com/db/\(entry.callsign)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var tableHeaderView: some View {
        HStack(spacing: 8) {
            Text("PRIORITY")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)

            Text("CALLSIGN & COUNTRY")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(minWidth: 180, alignment: .leading)

            Text("GRID / DISTANCE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)

            Text("SNR")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .center)

            Text("OFFSET")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .trailing)

            Text("MESSAGE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("ACTION")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .trailing)
        }
    }

    private func rosterRow(_ entry: DigitalRosterEntry) -> some View {
        HStack(spacing: 8) {
            // Priority Badge
            HStack(spacing: 4) {
                Image(systemName: entry.status.badgeIcon)
                    .font(.system(size: 10))
                Text(entry.status.rawValue)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(entry.status.badgeColor)
            .cornerRadius(4)
            .frame(width: 110, alignment: .leading)

            // Callsign & Country
            HStack(spacing: 6) {
                Text(entry.countryInfo.flagEmoji)
                    .font(.body)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(entry.callsign)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                        if waitAndPounce.activeTarget?.callsign == entry.callsign {
                            Image(systemName: "scope")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.red)
                                .help("Active Wait & Pounce Sniper Target")
                        }
                        if SuperCheckPartialEngine.shared.isKnownContestCallsign(entry.callsign) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                                .help("Verified in Master.scp Database")
                        }
                        if entry.sliceLabel == "VFO B" {
                            Text("VFO B")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.18))
                                .foregroundColor(.purple)
                                .clipShape(Capsule())
                        }
                    }
                    Text(entry.countryInfo.entityName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 180, alignment: .leading)

            // Grid / Distance / Bearing
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.grid.isEmpty ? "-" : entry.grid)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                if let dist = entry.distanceKm, let bearing = entry.bearingDeg {
                    HStack(spacing: 4) {
                        Text("\(Int(dist)) km • \(bearing)°")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Button {
                            RotatorControlEngine.shared.setAzimuth(Double(bearing))
                        } label: {
                            Image(systemName: "safari")
                                .font(.system(size: 8))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .help("Turn Rotator to \(bearing)°")
                    }
                }
            }
            .frame(width: 140, alignment: .leading)

            // SNR Badge
            Text(entry.snrFormatted)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(entry.snrColor)
                .frame(width: 65, alignment: .center)

            // Offset
            Text(entry.deltaFrequencyFormatted)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .trailing)

            // Raw Message
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(entry.isCQ ? .accentColor : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Action: 1-Click Tune Rig, Smart Queue, Wait & Pounce Snipe & Call Reply
            HStack(spacing: 4) {
                Button {
                    let dialHz = appState.wsjtxListener.lastStatus?.dialFrequencyHz ?? 14074000
                    RigControlEngine.shared.tune(frequencyHz: dialHz, mode: "USB-D")
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .help("Tune Transceiver to this Band/Freq")

                Button {
                    targetQueue.enqueue(
                        callsign: entry.callsign,
                        grid: entry.grid,
                        deltaFrequencyHz: entry.deltaFrequencyHz,
                        snr: entry.snr,
                        mode: entry.mode
                    )
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .foregroundColor(.accentColor)
                .help("Add to Smart Auto-Sequence Target Queue")

                Button {
                    if waitAndPounce.activeTarget?.callsign == entry.callsign {
                        waitAndPounce.clearTarget()
                    } else {
                        waitAndPounce.setTarget(
                            callsign: entry.callsign,
                            grid: entry.grid,
                            deltaHz: entry.deltaFrequencyHz,
                            mode: entry.mode,
                            interlocutor: entry.targetCallsign,
                            snr: entry.snr,
                            rawDecode: entry.rawDecode
                        )
                    }
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.bordered)
                .foregroundStyle(waitAndPounce.activeTarget?.callsign == entry.callsign ? Color.red : Color.secondary)
                .help(waitAndPounce.activeTarget?.callsign == entry.callsign ? "Disarm Wait & Pounce Target" : "Snipe with Wait & Pounce")

                Button {
                    callStation(entry)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("Call")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(entry.status.isNeeded ? .purple : .accentColor)
            }
            .frame(width: 165, alignment: .trailing)
        }
    }

    // MARK: - Empty State

    private var emptyRosterState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "waveform.and.person.filled")
                    .font(.system(size: 38))
                    .foregroundColor(.green)
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Operational Standby — Live Listening")
                        .font(.headline)
                        .fontWeight(.bold)
                }

                Text("YAAM is actively listening for live digital decodes (FT8 / FT4) on UDP port \(String(appState.wsjtxListener.currentPort)) and internal modem. As soon as signals are received, they will be triaged here against your log in real time.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            HStack(spacing: 12) {
                if !appState.wsjtxListener.state.isListening {
                    Button("Start UDP Listener (Port \(String(appState.wsjtxListener.currentPort)))") {
                        appState.wsjtxListener.start()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Load Simulation (Muted Preview)") {
                    loadSampleDecodes()
                }
                .buttonStyle(.bordered)
                .help("Loads sample decodes for layout testing without playing any voice alerts")
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadSampleDecodes() {
        let samples: [WSJTXLiveDecode] = [
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: 14, deltaTimeSec: 0.2, deltaFrequencyHz: 1420, mode: "FT8", message: "CQ 3D2RR RH42", lowConfidence: false, offAir: false, callerCallsign: "3D2RR", targetCallsign: "", grid: "RH42", report: "", port: 2237, sliceLabel: "VFO A"),
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: -4, deltaTimeSec: 0.1, deltaFrequencyHz: 1650, mode: "FT8", message: "CQ JA1ABC PM95", lowConfidence: false, offAir: false, callerCallsign: "JA1ABC", targetCallsign: "", grid: "PM95", report: "", port: 2237, sliceLabel: "VFO A"),
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: 6, deltaTimeSec: 0.3, deltaFrequencyHz: 980, mode: "FT8", message: "CQ W1AW FN31", lowConfidence: false, offAir: false, callerCallsign: "W1AW", targetCallsign: "", grid: "FN31", report: "", port: 2238, sliceLabel: "VFO B"),
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: -12, deltaTimeSec: 0.2, deltaFrequencyHz: 2100, mode: "FT8", message: "CQ VK3XYZ QF22", lowConfidence: false, offAir: false, callerCallsign: "VK3XYZ", targetCallsign: "", grid: "QF22", report: "", port: 2237, sliceLabel: "VFO A"),
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: -6, deltaTimeSec: 0.1, deltaFrequencyHz: 1200, mode: "FT8", message: "CQ DL1ABC JO50", lowConfidence: false, offAir: false, callerCallsign: "DL1ABC", targetCallsign: "", grid: "JO50", report: "", port: 2238, sliceLabel: "VFO B"),
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: 8, deltaTimeSec: 0.4, deltaFrequencyHz: 1850, mode: "FT8", message: "CQ ZL1BQD RE78", lowConfidence: false, offAir: false, callerCallsign: "ZL1BQD", targetCallsign: "", grid: "RE78", report: "", port: 2238, sliceLabel: "VFO B")
        ]
        roster.processDecodes(samples, activeBand: activeBand, isSimulation: true)
    }

    private func callStation(_ entry: DigitalRosterEntry) {
        if let raw = entry.rawDecode {
            if raw.sliceLabel == "Internal" || raw.port == 0 {
                // Reply directly via YAAM Internal FT8 Modem
                if let match = appState.ft8Engine.decodedRows.first(where: { $0.callerCall == entry.callsign }) {
                    appState.ft8Engine.selectForReply(match)
                } else {
                    // The engine takes the operator's callsign and locator from the active profile, as the FT8 screen does.
                    appState.ft8Engine.configureStation(
                        callsign: appState.currentStationCallsign,
                        grid: appState.activeStationProfile?.normalizedGrid ?? ""
                    )
                    if let text = appState.ft8Engine.directedGridMessage(to: entry.callsign) {
                        replyNotice = ""
                        appState.ft8Engine.txText = text
                        appState.ft8Engine.txAudioFrequencyHz = Float(entry.deltaFrequencyHz)
                        appState.ft8Engine.transmitArmed = true
                    } else {
                        replyNotice = TransmitIdentity.refusal(callsign: appState.ft8Engine.myCall, grid: appState.ft8Engine.myGrid)
                            ?? TransmitIdentity.noMessageText
                    }
                }
            } else {
                appState.wsjtxListener.sendReply(to: raw)
            }
        }
        if RigControlEngine.shared.isConnected {
            let dialHz = appState.wsjtxListener.lastStatus?.dialFrequencyHz ?? (appState.ft8Engine.dialFrequencyHz > 0 ? appState.ft8Engine.dialFrequencyHz : 14074000)
            RigControlEngine.shared.tune(frequencyHz: dialHz, mode: "USB-D")
        }
    }

    private func syncContextAndRebuild() {
        roster.updateStationContext(
            callsign: appState.currentStationCallsign,
            grid: appState.activeStationProfile?.grid ?? ""
        )
        roster.rebuildLogCache(records: appState.qsoRecords)
    }

    // MARK: - Audio Settings Sheet

    private var audioSettingsSheet: some View {
        AudioAlertSettingsView(showDismissButton: true) {
            showingAudioSettings = false
        }
        .frame(width: 480, height: 550)
    }

    // MARK: - Detail Sheet

    private func entryDetailSheet(_ entry: DigitalRosterEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(entry.countryInfo.flagEmoji)
                    .font(.system(size: 32))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.callsign)
                        .font(.title2)
                        .bold()
                    Text(entry.countryInfo.entityName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") {
                    selectedEntryForDetail = nil
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Decoder Source:").foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: entry.sliceLabel == "Internal" ? "waveform.circle.fill" : "antenna.radiowaves.left.and.right")
                            .foregroundColor(.accentColor)
                        Text(entry.sliceLabel == "Internal" ? "YAAM Internal FT8 Modem" : "WSJT-X UDP (\(entry.sliceLabel))")
                            .fontWeight(.semibold)
                    }
                }
                GridRow {
                    Text("Triage Status:").foregroundColor(.secondary)
                    Text(entry.status.rawValue).fontWeight(.bold).foregroundColor(entry.status.badgeColor)
                }
                GridRow {
                    Text("Super Check Partial:").foregroundColor(.secondary)
                    if SuperCheckPartialEngine.shared.isKnownContestCallsign(entry.callsign) {
                        Label("Verified Master Contest Call (SCP)", systemImage: "rosette")
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                    } else {
                        Text("Standard Amateur Call").foregroundColor(.secondary)
                    }
                }
                GridRow {
                    Text("Previous in Log:").foregroundColor(.secondary)
                    let prevQSOs = appState.qsoRecords.filter { $0.call.uppercased() == entry.callsign.uppercased() }
                    if prevQSOs.isEmpty {
                        Text("0 QSOs (All-Time New Station)")
                            .foregroundColor(.purple)
                            .fontWeight(.semibold)
                    } else {
                        Text("\(prevQSOs.count) QSO(s) logged (\(prevQSOs.map(\.band).joined(separator: ", ")))")
                            .foregroundColor(.primary)
                    }
                }
                GridRow {
                    Text("Grid Square:").foregroundColor(.secondary)
                    Text(entry.grid.isEmpty ? "Unknown" : entry.grid).font(.system(.body, design: .monospaced))
                }
                if let dist = entry.distanceKm, let bearing = entry.bearingDeg {
                    GridRow {
                        Text("Distance / Beam:").foregroundColor(.secondary)
                        Text("\(Int(dist)) km · Bearing \(bearing)°")
                    }
                }
                GridRow {
                    Text("Signal Report:").foregroundColor(.secondary)
                    Text("\(entry.snrFormatted) at \(entry.deltaFrequencyFormatted)")
                }
                GridRow {
                    Text("Raw Message:").foregroundColor(.secondary)
                    Text(entry.message).font(.system(.caption, design: .monospaced))
                }
            }
            .font(.caption)

            Spacer()

            HStack {
                Button("Open in QRZ.com") {
                    if let url = URL(string: "https://www.qrz.com/db/\(entry.callsign)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button(entry.sliceLabel == "Internal" ? "Reply via YAAM FT8 Modem ⚡️" : "Reply in WSJT-X ⚡️") {
                    callStation(entry)
                    selectedEntryForDetail = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480, height: 380)
    }
}

// MARK: - Dedicated Voice & Speech Alerts Settings View

public struct AudioAlertSettingsView: View {
    @ObservedObject private var audioAlerts = DigitalAudioAlertEngine.shared
    public var showDismissButton: Bool = false
    public var onDismiss: (() -> Void)? = nil

    private var currentSpeedLabel: String {
        let mult = audioAlerts.speechRate / 0.5
        if mult < 0.85 {
            return String(format: "%.1fx (Slow)", mult)
        } else if mult <= 1.15 {
            return String(format: "%.1fx (Normal)", mult)
        } else if mult <= 1.35 {
            return String(format: "%.1fx (Fast)", mult)
        } else {
            return String(format: "%.1fx (Rapid)", mult)
        }
    }

    public init(showDismissButton: Bool = false, onDismiss: (() -> Void)? = nil) {
        self.showDismissButton = showDismissButton
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showDismissButton {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.accentColor)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart Voice & Audio Alerts")
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("Real-time spoken alerts for DXCC, bands, grids, and directed calls")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button("Done") {
                        onDismiss?()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Master Switch
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Enable Hands-Free Speech Alerts", isOn: $audioAlerts.isEnabled)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("When enabled, incoming DX opportunities and direct calls are spoken aloud using macOS Speech Synthesis.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    if audioAlerts.isEnabled {
                        // Section 1: Voice & Speed
                        VStack(alignment: .leading, spacing: 12) {
                            Label("SPEAKER VOICE & SPEED", systemImage: "waveform")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)

                            // Voice Selector
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Speaker Voice:")
                                    .font(.caption)
                                    .fontWeight(.medium)

                                Picker("", selection: $audioAlerts.selectedVoiceID) {
                                    Text("🇺🇸 Samantha (System Default)").tag("")
                                    Divider()
                                    ForEach(audioAlerts.voiceOptions) { voice in
                                        Text(voice.displayName).tag(voice.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }

                            Divider()

                            // Speech Speed / Rate Slider & Presets
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Speech Speed:")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(currentSpeedLabel)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundColor(.accentColor)
                                }

                                HStack(spacing: 8) {
                                    Text("🐢").font(.caption)
                                    Slider(value: $audioAlerts.speechRate, in: 0.30...0.75, step: 0.02)
                                    Text("⚡️").font(.caption)
                                }

                                HStack(spacing: 6) {
                                    Button("Slow (0.8x)") {
                                        audioAlerts.speechRate = 0.40
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Normal (1.0x)") {
                                        audioAlerts.speechRate = 0.50
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Fast (1.2x)") {
                                        audioAlerts.speechRate = 0.60
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Rapid (1.4x)") {
                                        audioAlerts.speechRate = 0.70
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            Divider()

                            // Volume Slider
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Volume:")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("\(Int(audioAlerts.speechVolume * 100))%")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $audioAlerts.speechVolume, in: 0.1...1.0, step: 0.05)
                            }

                            // Chime
                            Toggle("Play chime before speaking announcement", isOn: $audioAlerts.playChimeFirst)
                                .font(.caption)

                            // Test & Stop
                            HStack(spacing: 10) {
                                Button {
                                    audioAlerts.testVoiceAlert()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "play.circle.fill")
                                        Text("Test Voice Announcement")
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                if audioAlerts.isSpeaking {
                                    Button {
                                        audioAlerts.stopSpeaking()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "stop.circle.fill")
                                            Text("Stop")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.red)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)

                        // Section 2: Alert Triggers
                        VStack(alignment: .leading, spacing: 10) {
                            Label("ALERT TRIGGERS", systemImage: "bell.badge.fill")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)

                            Toggle("⭐️ All-Time New DXCC (ATNO)", isOn: $audioAlerts.alertOnNewDXCC)
                            Toggle("🎯 New DXCC Entity on Current Band", isOn: $audioAlerts.alertOnNewBand)
                            Toggle("💠 New Maidenhead Grid Square", isOn: $audioAlerts.alertOnNewGrid)
                            Toggle("🔔 Station Calling Me Directly", isOn: $audioAlerts.alertOnDirectedToMe)
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(showDismissButton ? 18 : 10)
    }
}

// MARK: - UDP Port Configuration Popover

struct UDPPortConfigPopoverView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("wsjtxUDPPort") private var wsjtxPort = 2237
    @AppStorage("multiSliceEnabled") private var multiSliceEnabled = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Digital Ingestion (UDP)", systemImage: "network")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                if appState.wsjtxListener.state.isListening {
                    HStack(spacing: 5) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("LISTENING (\(String(appState.wsjtxListener.currentPort)))")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12), in: Capsule())
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(Color.secondary).frame(width: 7, height: 7)
                        Text("STOPPED")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            Text("YAAM ingests live decodes and sends 1-click QSO replies via local UDP broadcast with WSJT-X, JTDX, or SDR-Control.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            // Port Selection
            VStack(alignment: .leading, spacing: 6) {
                Text("UDP Listener Port:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("2237", value: $wsjtxPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 100)

                    Text("Active: \(String(appState.wsjtxListener.currentPort))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Quick Port Presets
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick Port Presets:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    portPresetButton(title: "2237", subtitle: "WSJT-X / JTDX", port: 2237)
                    portPresetButton(title: "2238", subtitle: "JTDX / VFO B", port: 2238)
                    portPresetButton(title: "2239", subtitle: "Slice C", port: 2239)
                    portPresetButton(title: "2240", subtitle: "Slice D", port: 2240)
                }
            }

            Divider()

            // Multi-Slice Option
            Toggle("Multi-Slice Quad Listeners (Ports 2237–2240)", isOn: $multiSliceEnabled)
                .font(.caption)
                .help("Simultaneously listen on secondary ports for FlexRadio / SDR multi-slice decodes")
                .onChange(of: multiSliceEnabled) { _, newValue in
                    appState.wsjtxListener.multiSliceEnabled = newValue
                }

            Divider()

            // Footer Actions
            HStack {
                Button(appState.wsjtxListener.state.isListening ? "Stop Listener" : "Start Listener") {
                    if appState.wsjtxListener.state.isListening {
                        appState.wsjtxListener.stop()
                    } else {
                        appState.wsjtxListener.start(port: wsjtxPort)
                    }
                }
                .buttonStyle(.bordered)
                .tint(appState.wsjtxListener.state.isListening ? .red : .green)

                Spacer()

                Button("Apply & Restart") {
                    appState.wsjtxListener.start(port: wsjtxPort)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private func portPresetButton(title: String, subtitle: String, port: Int) -> some View {
        Button {
            wsjtxPort = port
            if appState.wsjtxListener.state.isListening {
                appState.wsjtxListener.start(port: port)
            }
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(wsjtxPort == port ? Color.accentColor : Color.primary)
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(wsjtxPort == port ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(wsjtxPort == port ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
