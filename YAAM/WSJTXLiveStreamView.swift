//
//  WSJTXLiveStreamView.swift
//  YAAM
//
//  Live 2-Way WSJT-X / JTDX Digital Console & Stream View for macOS.
//  Features real-time stream decoding, 1-click Reply (Type 4) dispatch,
//  Halt TX, band activity clearing, and smart DXCC / CQ filtering.
//

import SwiftUI
import AppKit

public struct WSJTXLiveStreamView: View {
    @ObservedObject var wsjtx: WSJTXListener
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var contestEngine = DigitalContestEngine.shared

    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all
    @State private var showContestMatrix = false

    public enum FilterMode: String, CaseIterable, Identifiable {
        case all = "All Decodes"
        case newMultsOnly = "⚡️ Mults"
        case cqOnly = "CQ Only"
        case directedToMe = "To Me"
        case unworked = "Unworked DX"

        public var id: String { rawValue }
    }

    public init(wsjtx: WSJTXListener) {
        self.wsjtx = wsjtx
    }

    private var myCall: String {
        appState.currentStationCallsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeBand: String {
        let reported = wsjtx.lastStatus?.band.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reported.isEmpty ? "20m" : reported
    }

    private var filteredDecodes: [WSJTXLiveDecode] {
        wsjtx.liveDecodes.filter { dec in
            // Search text filter
            if !searchText.isEmpty {
                let query = searchText.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let matchesCall = dec.callerCallsign.uppercased().contains(query)
                let matchesTarget = dec.targetCallsign.uppercased().contains(query)
                let matchesGrid = dec.grid.uppercased().contains(query)
                let matchesMsg = dec.message.uppercased().contains(query)
                let matchesCountry = dec.countryInfo.country.uppercased().contains(query)
                if !matchesCall && !matchesTarget && !matchesGrid && !matchesMsg && !matchesCountry {
                    return false
                }
            }

            // Mode filter
            switch filterMode {
            case .all:
                return true
            case .newMultsOnly:
                let status = dec.contestStatus(engine: contestEngine, onBand: activeBand)
                return status.isMultiplier
            case .cqOnly:
                return dec.isCQ
            case .directedToMe:
                return dec.isDirectedToMe(myCall: myCall)
            case .unworked:
                guard !dec.callerCallsign.isEmpty else { return false }
                let worked = appState.qsoRecords.contains { rec in
                    (rec.fields["CALL"] ?? "").uppercased() == dec.callerCallsign.uppercased()
                }
                return !worked
            }
        }
    }

    private var cqCount: Int {
        wsjtx.liveDecodes.filter { $0.isCQ }.count
    }

    private var directedToMeCount: Int {
        wsjtx.liveDecodes.filter { $0.isDirectedToMe(myCall: myCall) }.count
    }

    private var newMultsCount: Int {
        wsjtx.liveDecodes.filter { $0.contestStatus(engine: contestEngine, onBand: activeBand).isMultiplier }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Top Telemetry & Control Bar
            telemetryControlBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))

            Divider()

            // 1.5. Live Contest Telemetry Strip
            if contestEngine.isContestActive {
                contestHUDStrip
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.08))
                Divider()

                contestQueueHUDStrip
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.12, green: 0.10, blue: 0.05).opacity(0.7))
                Divider()
            }

            // 2. Active Reply Notification Toast
            if let toast = wsjtx.activeReplyToast {
                activeReplyBanner(message: toast)
                Divider()
            }

            // 3. Filter & Search Toolbar
            filterToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 4. Live Decodes Feed
            if wsjtx.liveDecodes.isEmpty {
                emptyStreamPlaceholder
            } else if filteredDecodes.isEmpty {
                noMatchPlaceholder
            } else {
                decodesList
            }

            Divider()

            // 5. Bottom Status Strip
            bottomStatusStrip
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        }
        .onChange(of: wsjtx.liveDecodes.first?.id) { _, _ in
            guard contestEngine.isContestActive && contestEngine.autoQueueIncomingCallers else { return }
            guard let latest = wsjtx.liveDecodes.first else { return }
            let dxCurrent = wsjtx.lastStatus?.dxCallsign ?? ""
            if latest.isDirectedToMe(myCall: myCall) && latest.callerCallsign != dxCurrent {
                _ = contestEngine.enqueueCaller(
                    callsign: latest.callerCallsign,
                    grid: latest.grid.isEmpty ? nil : latest.grid,
                    countryName: latest.countryInfo.country,
                    countryFlag: latest.countryInfo.flag,
                    snr: Int(latest.snr),
                    audioFrequencyHz: Int(latest.deltaFrequencyHz),
                    band: activeBand,
                    activeDX: dxCurrent,
                    source: .wsjtx
                )
            }
        }
        .onChange(of: wsjtx.loggedEvents.count) { _, _ in
            guard contestEngine.isContestActive && contestEngine.autoEngageNext else { return }
            if let next = contestEngine.popNextCaller() {
                replyToQueuedCaller(next)
            }
        }
    }

    // MARK: - Contest HUD Strip

    private var contestHUDStrip: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.yellow)
                Text(contestEngine.contestTitle)
                    .font(.system(size: 11, weight: .bold))
            }

            Spacer()

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("Score:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(contestEngine.claimedScore.formatted())
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.yellow)
                }

                HStack(spacing: 4) {
                    Text("QSOs:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(contestEngine.totalQSOs)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }

                HStack(spacing: 4) {
                    Text("Mults:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(contestEngine.totalMultipliers)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.orange)
                }

                HStack(spacing: 4) {
                    Text("Rate:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(contestEngine.rate60Min)/hr")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.green)
                }
            }
        }
    }

    // MARK: - Contest Smart Runner Queue Strip

    private var contestQueueHUDStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.15))
                        .font(.system(size: 11))
                    Text("Auto-Runner Queue")
                        .font(.system(size: 11, weight: .bold))
                    Text("(\(contestEngine.queuedCallers.count))")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(contestEngine.queuedCallers.isEmpty ? .secondary : Color.yellow)
                }

                Divider()
                    .frame(height: 16)

                Toggle(isOn: $contestEngine.autoEngageNext) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(contestEngine.autoEngageNext ? Color.green : Color.secondary)
                        Text("Zero-Idle Auto-Engage")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Toggle(isOn: $contestEngine.autoQueueIncomingCallers) {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(contestEngine.autoQueueIncomingCallers ? Color.cyan : Color.secondary)
                        Text("Auto-Queue Pile-up")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Spacer()

                if !contestEngine.queuedCallers.isEmpty {
                    if let top = contestEngine.queuedCallers.first {
                        Button {
                            if let caller = contestEngine.popNextCaller() {
                                replyToQueuedCaller(caller)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                                Text("Engage #1 (\(top.callsign))")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.orange)
                        .controlSize(.mini)
                    }

                    Button {
                        contestEngine.clearQueue()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 8))
                            Text("Clear")
                                .font(.system(size: 9))
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }

            if contestEngine.queuedCallers.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Pile-up queue is empty. Directed decodes during active QSOs will be ranked and queued automatically.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(contestEngine.queuedCallers.enumerated()), id: \.element.id) { index, caller in
                            queueCard(caller: caller, rank: index + 1)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func queueCard(caller: ContestQueuedCaller, rank: Int) -> some View {
        HStack(spacing: 8) {
            // Rank Badge
            Text("#\(rank)")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(rank == 1 ? Color.yellow : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(caller.callsign)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    if caller.contestStatus.isMultiplier {
                        Text(caller.contestStatus.badgeLabel)
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(red: 1.0, green: 0.72, blue: 0.15), in: RoundedRectangle(cornerRadius: 3))
                    } else if caller.contestStatus.isDupe {
                        Text("DUPE")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 2))
                    } else if caller.contestStatus.points > 0 {
                        Text("+\(caller.contestStatus.points) PTS")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color(red: 0.15, green: 0.75, blue: 0.38), in: RoundedRectangle(cornerRadius: 2))
                    }
                }

                HStack(spacing: 6) {
                    if !caller.countryFlag.isEmpty {
                        Text(caller.countryFlag)
                            .font(.system(size: 9))
                    }
                    if let grid = caller.grid {
                        Text(grid)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(String(format: "%+02d dB", caller.snr))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(caller.snr >= -10 ? Color.green : Color.secondary)
                    Text("\(caller.audioFrequencyHz) Hz")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 3) {
                Button {
                    replyToQueuedCaller(caller)
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Send Reply in WSJT-X now")

                if rank > 1 {
                    Button {
                        contestEngine.promoteQueuedCallerToTop(id: caller.id)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Promote to top of queue")
                }

                Button {
                    contestEngine.removeQueuedCaller(id: caller.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .foregroundStyle(.secondary)
                .help("Remove from queue")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rank == 1 ? Color.yellow.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(rank == 1 ? Color.yellow.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func replyToQueuedCaller(_ caller: ContestQueuedCaller) {
        if let dec = wsjtx.liveDecodes.first(where: { $0.callerCallsign.uppercased() == caller.callsign.uppercased() }) {
            wsjtx.sendReply(to: dec, port: wsjtx.currentPort)
        } else {
            let synthetic = WSJTXLiveDecode(
                id: UUID(),
                sourceID: wsjtx.lastStatus?.sourceID ?? "WSJT-X",
                isNew: true,
                timeMillis: UInt32(Date().timeIntervalSince1970 * 1000) % 86_400_000,
                snr: Int32(caller.snr),
                deltaTimeSec: 0.1,
                deltaFrequencyHz: UInt32(max(100, caller.audioFrequencyHz)),
                mode: "~",
                message: "\(myCall) \(caller.callsign) \(caller.grid ?? "")",
                lowConfidence: false,
                offAir: false,
                receivedAt: Date(),
                callerCallsign: caller.callsign,
                targetCallsign: myCall,
                grid: caller.grid ?? "",
                report: String(format: "%+03d", caller.snr)
            )
            wsjtx.sendReply(to: synthetic, port: wsjtx.currentPort)
        }
        contestEngine.removeQueuedCaller(id: caller.id)
    }

    // MARK: - 1. Telemetry Control Bar

    private var telemetryControlBar: some View {
        HStack(spacing: 16) {
            // Connection Status Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(wsjtx.state.isListening ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(wsjtx.state.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())

            // WSJT-X Radio Status
            if let status = wsjtx.lastStatus {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "app.connected.to.app.below.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(status.sourceID)
                            .font(.system(size: 12, weight: .bold))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "dial.low.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                        Text("\(status.frequencyMHz) MHz")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                    }

                    Text(status.mode)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(3)

                    // DX Selected in WSJT-X
                    if !status.dxCallsign.isEmpty {
                        HStack(spacing: 4) {
                            Text("DX:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(status.dxCallsign)
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.orange)
                            if !status.dxGrid.isEmpty {
                                Text("(\(status.dxGrid))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Activity Indicator Badge
                    HStack(spacing: 5) {
                        Circle()
                            .fill(status.transmitting ? Color.red : (status.decoding ? Color.green : Color.blue))
                            .frame(width: 6, height: 6)
                        Text(status.transmitting ? "TRANSMITTING" : (status.decoding ? "DECODING" : "MONITORING"))
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(status.transmitting ? Color.red : (status.decoding ? Color.green : Color.blue))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((status.transmitting ? Color.red : (status.decoding ? Color.green : Color.blue)).opacity(0.15))
                    .cornerRadius(4)
                }
            }

            Spacer()

            // 2-Way Quick Action Buttons
            HStack(spacing: 8) {
                // Contest Matrix Button
                Button {
                    showContestMatrix.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(Color.yellow)
                        Text("Contest Matrix")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showContestMatrix) {
                    DigitalContestBandMatrixView(engine: contestEngine)
                }

                // Halt TX Button
                Button {
                    wsjtx.sendHaltTx(autoTxOnly: false, port: wsjtx.currentPort)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                        Text("Halt TX")
                    }
                    .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .help("Command WSJT-X to stop transmitting immediately (Type 7 Packet)")

                // Sync Grid Button
                if let grid = appState.activeStationProfile?.normalizedGrid, !grid.isEmpty {
                    Button {
                        wsjtx.sendSetLocation(grid: grid, port: wsjtx.currentPort)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                            Text("Sync Grid (\(grid))")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Send current station Maidenhead grid to WSJT-X (Type 9 Packet)")
                }

                // Clear Band Activity
                Button {
                    wsjtx.sendClear(window: 2, port: wsjtx.currentPort)
                    wsjtx.clearLiveDecodes()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Clear band activity and local stream buffer (Type 3 Packet)")
            }
        }
    }

    // MARK: - 2. Active Reply Banner

    private func activeReplyBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.green)

            Text(message)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.green)

            Spacer()

            Button("Cancel TX") {
                wsjtx.sendHaltTx(autoTxOnly: false, port: wsjtx.currentPort)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.mini)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.12))
    }

    // MARK: - 3. Filter Toolbar

    private var filterToolbar: some View {
        HStack(spacing: 12) {
            // Search Input
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search callsign, grid, country, or message...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .frame(width: 260)

            // Mode Filter Picker
            Picker("", selection: $filterMode) {
                Text("All (\(wsjtx.liveDecodes.count))").tag(FilterMode.all)
                Text("⚡️ Mults (\(newMultsCount))").tag(FilterMode.newMultsOnly)
                Text("CQ (\(cqCount))").tag(FilterMode.cqOnly)
                Text("To Me (\(directedToMeCount))").tag(FilterMode.directedToMe)
                Text("Unworked DX").tag(FilterMode.unworked)
            }
            .pickerStyle(.segmented)
            .frame(width: 440)

            Spacer()

            // Count Badge
            Text("\(filteredDecodes.count) Decodes")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 4. Decodes List

    private var decodesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredDecodes) { decode in
                        let status = decode.contestStatus(engine: contestEngine, onBand: activeBand)
                        WSJTXDecodeRowView(
                            decode: decode,
                            myCall: myCall,
                            isActiveReply: wsjtx.activeReplyDecode?.id == decode.id,
                            isWorked: isCallWorked(decode.callerCallsign),
                            contestStatus: status
                        ) {
                            wsjtx.sendReply(to: decode, port: wsjtx.currentPort)
                        }
                        .id(decode.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Placeholders

    private var emptyStreamPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Waiting for Live Decodes from WSJT-X / JTDX...")
                .font(.headline)
            Text("Ensure WSJT-X has UDP reporting enabled on port \(wsjtx.currentPort) under Settings → Reporting.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var noMatchPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No decodes match current filter.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    // MARK: - 5. Bottom Status Strip

    private var bottomStatusStrip: some View {
        HStack(spacing: 14) {
            Text("Tip: Click 'Reply' or double-click any row to instantly transmit reply in WSJT-X.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            if !wsjtx.lastSentCommand.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                    Text("Last Command: \(wsjtx.lastSentCommand)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func isCallWorked(_ call: String) -> Bool {
        guard !call.isEmpty else { return false }
        let clean = call.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return appState.qsoRecords.contains { ($0.fields["CALL"] ?? "").uppercased() == clean }
    }
}

// MARK: - Subview for Individual Decode Row

private struct WSJTXDecodeRowView: View {
    let decode: WSJTXLiveDecode
    let myCall: String
    let isActiveReply: Bool
    let isWorked: Bool
    let contestStatus: DecodedContestStatus
    let onReply: () -> Void

    @State private var isHovered: Bool = false

    private var isDirected: Bool {
        decode.isDirectedToMe(myCall: myCall)
    }

    private var callsignColor: Color {
        if isDirected { return Color.red }
        if contestStatus.isMultiplier { return Color.orange }
        if contestStatus.isDupe { return Color.secondary.opacity(0.6) }
        if decode.isCQ { return Color.green }
        return Color.primary
    }

    private var rowBackground: Color {
        if isActiveReply {
            return Color.green.opacity(0.2)
        }
        if isDirected {
            return Color.red.opacity(0.12)
        }
        if contestStatus.isMultiplier {
            return Color.orange.opacity(0.14)
        }
        if decode.isCQ {
            return Color.green.opacity(0.06)
        }
        if isHovered {
            return Color.secondary.opacity(0.08)
        }
        return Color.clear
    }

    private var rowBorder: Color {
        if isActiveReply {
            return Color.green
        }
        if isDirected {
            return Color.red.opacity(0.4)
        }
        if contestStatus.isMultiplier {
            return Color.orange.opacity(0.6)
        }
        if decode.isCQ {
            return Color.green.opacity(0.2)
        }
        return Color.clear
    }

    var body: some View {
        HStack(spacing: 10) {
            // Time UTC
            Text(decode.timeUTCString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .frame(width: 60, alignment: .leading)

            // SNR Badge
            Text(decode.snrFormatted)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(decode.snrColor)
                .frame(width: 50, alignment: .trailing)

            // Delta Time (DT)
            Text(decode.deltaTimeFormatted)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            // Audio Frequency (DF)
            Text(decode.deltaFrequencyFormatted)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.blue)
                .frame(width: 56, alignment: .trailing)

            // Mode
            Text(decode.mode)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(3)
                .frame(width: 34)

            // Country Flag & Name
            HStack(spacing: 4) {
                Text(decode.countryInfo.flag)
                    .font(.system(size: 12))
                Text(decode.countryInfo.country)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .leading)

            // Callsign
            let call = decode.callerCallsign.isEmpty ? decode.targetCallsign : decode.callerCallsign
            Text(call)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(callsignColor)
                .frame(width: 85, alignment: .leading)

            // Grid
            if !decode.grid.isEmpty {
                Text(decode.grid)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .cornerRadius(3)
                    .frame(width: 50, alignment: .leading)
            } else {
                Spacer().frame(width: 50)
            }

            // Contest Multiplier / Points / Dupe Badge
            if contestStatus.isMultiplier {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7))
                    Text(contestStatus.badgeLabel)
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange)
                .foregroundStyle(Color.black)
                .cornerRadius(3)
            } else if contestStatus.isDupe {
                Text("DUPE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.2))
                    .foregroundStyle(Color.secondary)
                    .cornerRadius(3)
            } else if contestStatus.points > 0 {
                Text("+\(contestStatus.points) PTS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(Color.green)
                    .cornerRadius(3)
            }

            // Message text
            Text(decode.message)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(decode.isCQ ? Color.green : Color.primary)
                .lineLimit(1)

            Spacer()

            // Worked indicator
            if isWorked {
                Text("Worked")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }

            // 1-Click Reply Action Button
            Button(action: onReply) {
                HStack(spacing: 4) {
                    Image(systemName: isActiveReply ? "antenna.radiowaves.left.and.right" : "bolt.fill")
                    Text(isActiveReply ? "Calling..." : "Reply")
                }
                .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(isActiveReply ? Color.orange : (decode.isCQ ? Color.green : Color.accentColor))
            .controlSize(.small)
            .help("Send 1-click Type 4 Reply packet to WSJT-X for \(decode.callerCallsign)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(rowBackground))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(rowBorder, lineWidth: 1))
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onReply()
        }
    }
}
