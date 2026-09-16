//
//  MultiRigFT8View.swift
//  YAAM
//
//  Unified Multi-Transceiver FT8 Console (SO2R / SO3R / Multi-Rig Cluster)
//  Allows operators to monitor and pilot 2, 3, or 4 transceivers simultaneously
//  on different amateur radio bands with independent DSP pipelines, live waterfalls,
//  and centralized cross-rig transmit interlock coordination.
//

import SwiftUI
import FT8808Engine

struct MultiRigFT8View: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var hub: MultiRigFT8Hub
    @State private var configuringSlot: MultiRigSlot?
    @State private var currentSecond: Double = 0.0
    @State private var clockTimer: Timer?

    init(hub: MultiRigFT8Hub) {
        self.hub = hub
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Top Master Control Ribbon
            masterControlRibbon
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 2. Multi-Rig Slot Workspace
            GeometryReader { geo in
                VStack(spacing: 0) {
                    mainSlotLayout(totalSize: geo.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if hub.showCrossBandRoster {
                        Divider()
                        crossBandOpportunityDrawer
                            .frame(height: 140)
                    }
                }
            }

            Divider()

            // 3. Bottom Master Status Bar
            masterBottomBar
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.40))
        }
        .sheet(item: $configuringSlot) { slot in
            MultiRigHardwareSettingsSheet(slot: slot) {
                hub.saveConfiguration()
            }
        }
        .onAppear {
            hub.configureBridges(with: appState)
            startClockTimer()
        }
        .onDisappear {
            clockTimer?.invalidate()
            clockTimer = nil
        }
    }

    // MARK: - Master Control Ribbon

    private var masterControlRibbon: some View {
        HStack(spacing: 12) {
            // Title & Cluster Status
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Multi-Rig FT8 Cluster")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("SO2R / SO3R Multi-Transceiver Cockpit")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .fixedSize()

            Divider().frame(height: 26)

            // Slot Quick Status Pills
            HStack(spacing: 6) {
                ForEach(hub.slots) { slot in
                    slotQuickBadge(slot)
                }
                if hub.slots.count < 4 {
                    Button(action: { hub.addSlot() }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.secondary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .help("Add another transceiver slot (up to 4)")
                }
            }
            .fixedSize()

            Spacer(minLength: 16)

            // Right Control Cluster (Fixed layout - Zero Overlap)
            HStack(spacing: 10) {
                // Master UTC Clock & Slot Progress
                utcClockBadge

                Divider().frame(height: 26)

                // Layout Menu Selector
                layoutMenu

                // Interlock Policy Picker
                interlockMenu

                Divider().frame(height: 26)

                // Master Control Buttons
                masterActionButtons
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var layoutMenu: some View {
        Menu {
            ForEach(MultiRigLayoutMode.allCases) { mode in
                Button(action: { hub.activeLayout = mode }) {
                    HStack {
                        Label(mode.rawValue, systemImage: mode.icon)
                        if hub.activeLayout == mode {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: hub.activeLayout.icon)
                    .foregroundColor(.accentColor)
                Text(hub.activeLayout.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .menuStyle(.borderedButton)
        .fixedSize()
        .help("Select Multi-Rig Console Layout (Current: \(hub.activeLayout.rawValue))")
    }

    private var interlockMenu: some View {
        Menu {
            ForEach(MultiRigInterlockPolicy.allCases) { policy in
                Button(action: { hub.interlockPolicy = policy }) {
                    HStack {
                        Label(policy.rawValue, systemImage: policy.icon)
                        if hub.interlockPolicy == policy {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: hub.interlockPolicy.icon)
                    .foregroundColor(hub.interlockPolicy == .strictLockout ? .accentColor : (hub.interlockPolicy == .concurrent ? .orange : .purple))
                Text(hub.interlockPolicy.shortTitle)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .menuStyle(.borderedButton)
        .fixedSize()
        .help("TX Interlock: \(hub.interlockPolicy.rawValue)\n\(hub.interlockPolicy.summary)")
    }

    private var masterActionButtons: some View {
        HStack(spacing: 6) {
            if hub.isAllMonitoring {
                Button(action: { hub.stopAllMonitoring() }) {
                    Label("Stop All", systemImage: "stop.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .help("Stop monitoring across all transceiver slots")
            } else {
                Button(action: { hub.startAllMonitoring() }) {
                    Label("Start All", systemImage: "play.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .help("Start monitoring across all transceiver slots")
            }

            Button(action: { hub.disarmAllTransmitters() }) {
                Label("Disarm All TX", systemImage: "shield.slash.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .help("Emergency Stop: Immediately release PTT and disarm all transmitters")
        }
        .fixedSize()
    }

    private func slotQuickBadge(_ slot: MultiRigSlot) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(slot.engine.state == .transmitting ? Color.red : (slot.isMonitoring ? Color.green : Color.gray.opacity(0.5)))
                .frame(width: 8, height: 8)
            Text("\(slot.bandName)")
                .font(.caption)
                .fontWeight(.semibold)
            Text("(\(slot.driverType.shortTitle))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(slot.engine.state == .transmitting ? Color.red : Color.clear, lineWidth: 1)
        )
    }

    private var utcClockBadge: some View {
        HStack(spacing: 8) {
            let utc = utcTimeString()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(utc) UTC")
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.bold)
                let slotRem = 15.0 - currentSecond.truncatingRemainder(dividingBy: 15.0)
                Text(String(format: "Slot: %.1fs rem", slotRem))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(slotRem <= 2.0 ? .orange : .secondary)
            }

            // Radial slot phase indicator (15s cycle)
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(currentSecond.truncatingRemainder(dividingBy: 15.0) / 15.0))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.15))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .fixedSize()
    }

    // MARK: - Main Dynamic Multi-Rig Layout

    @ViewBuilder
    private func mainSlotLayout(totalSize: CGSize) -> some View {
        switch hub.activeLayout {
        case .tripleColumn:
            HStack(spacing: 10) {
                ForEach(hub.slots) { slot in
                    MultiRigSlotCardView(slot: slot, onConfigure: { configuringSlot = slot })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(10)

        case .heroAndSub:
            if let hero = hub.slots.first {
                VStack(spacing: 8) {
                    MultiRigSlotCardView(slot: hero, isHero: true, onConfigure: { configuringSlot = hero })
                        .frame(maxHeight: .infinity)

                    let subRigs = Array(hub.slots.dropFirst())
                    if !subRigs.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(subRigs) { slot in
                                MultiRigSlotCardView(slot: slot, isHero: false, onConfigure: { configuringSlot = slot })
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(height: totalSize.height * 0.45)
                    }
                }
                .padding(10)
            }

        case .dualSplit:
            HStack(spacing: 10) {
                let displayed = Array(hub.slots.prefix(2))
                ForEach(displayed) { slot in
                    MultiRigSlotCardView(slot: slot, onConfigure: { configuringSlot = slot })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(10)

        case .quadGrid:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(hub.slots) { slot in
                    MultiRigSlotCardView(slot: slot, onConfigure: { configuringSlot = slot })
                        .frame(height: max(260, (totalSize.height - 30) / 2))
                }
            }
            .padding(10)

        case .focusedSingle:
            VStack(spacing: 0) {
                // Focus Tab Switcher
                HStack(spacing: 6) {
                    ForEach(hub.slots) { slot in
                        Button(action: { hub.selectedFocusedSlotIndex = slot.slotIndex }) {
                            HStack {
                                Circle()
                                    .fill(slot.isMonitoring ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text("\(slot.name) · \(slot.bandName)")
                                    .fontWeight(hub.selectedFocusedSlotIndex == slot.slotIndex ? .bold : .regular)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(hub.selectedFocusedSlotIndex == slot.slotIndex ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                Divider()

                if let current = hub.slots.first(where: { $0.slotIndex == hub.selectedFocusedSlotIndex }) ?? hub.slots.first {
                    MultiRigSlotCardView(slot: current, isHero: true, onConfigure: { configuringSlot = current })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(10)
                }
            }
        }
    }

    // MARK: - Cross-Band Aggregated Opportunity Drawer

    private var crossBandOpportunityDrawer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Cross-Band DX Opportunity Radar", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
                Spacer()
                Button(action: { hub.showCrossBandRoster.toggle() }) {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            let opps = hub.aggregatedCrossBandOpportunities()
            if opps.isEmpty {
                Text("Listening across all connected bands... active CQ callers and new multipliers will appear here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(opps.prefix(12)) { opp in
                            crossBandOppCard(opp)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func crossBandOppCard(_ opp: CrossBandOpportunity) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(opp.band)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(3)
                Spacer()
                Text(String(format: "%+02.0f dB", opp.row.estimatedSNR))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(opp.row.estimatedSNR >= 0 ? .green : .secondary)
            }

            HStack(spacing: 4) {
                Text(opp.row.countryFlag)
                Text(opp.row.callerCall ?? "CQ")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
            }

            if let grid = opp.row.callerGrid, !grid.isEmpty {
                Text(grid)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Button("Answer on \(opp.slotName)") {
                if let slot = hub.slots.first(where: { $0.slotIndex == opp.slotIndex }) {
                    slot.engine.answerCallsign(opp.row)
                }
            }
            .font(.system(size: 9, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.mini)
        }
        .frame(width: 140)
        .padding(6)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(opp.row.isNewDXCC ? Color.yellow : Color.gray.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Master Bottom Status Bar

    private var masterBottomBar: some View {
        HStack {
            Text(hub.masterStatusMessage)
                .font(.caption)
                .foregroundColor(.secondary)

            if let conflict = hub.interlockCoordinator.lastInterlockConflict {
                Text("·")
                    .foregroundColor(.secondary)
                Label(conflict, systemImage: "exclamationmark.shield.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Spacer()

            Text("\(hub.slots.count) Radios Active · Interlock: \(hub.interlockPolicy.rawValue)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func startClockTimer() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let date = Date()
            let cal = Calendar(identifier: .gregorian)
            let secs = Double(cal.component(.second, from: date))
            let nanos = Double(cal.component(.nanosecond, from: date)) / 1_000_000_000.0
            currentSecond = secs + nanos
        }
    }

    private func utcTimeString() -> String {
        let df = DateFormatter()
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "HH:mm:ss"
        return df.string(from: Date())
    }
}

// MARK: - Individual Transceiver Slot Card View

struct MultiRigSlotCardView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var slot: MultiRigSlot
    @ObservedObject var engine: FT8EngineService
    var isHero: Bool = false
    var onConfigure: () -> Void

    @State private var selectedFilter = "ALL"
    @State private var autoHunterEnabled = false

    init(slot: MultiRigSlot, isHero: Bool = false, onConfigure: @escaping () -> Void) {
        self.slot = slot
        self.engine = slot.engine
        self.isHero = isHero
        self.onConfigure = onConfigure
    }

    var body: some View {
        VStack(spacing: 0) {
            // Slot Top Header Bar
            slotHeaderBar
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Mini Waterfall Display
            FT8SpectrumWaterfallView(
                engine: slot.engine,
                onSelectRxFrequency: { freq in
                    slot.engine.rxAudioFrequencyHz = freq
                    if slot.engine.lockTxRxFreq { slot.engine.txAudioFrequencyHz = freq }
                },
                onSelectTxFrequency: { freq in
                    slot.engine.txAudioFrequencyHz = freq
                    if slot.engine.lockTxRxFreq { slot.engine.rxAudioFrequencyHz = freq }
                }
            )
            .frame(height: isHero ? 160 : 110)
            .background(Color.black)

            Divider()

            // Telemetry & Transceiver Meters Ribbon
            slotTelemetryBar
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            Divider()

            // Decoded Messages Stream
            slotDecodesList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Transmit & Auto-Sequencer Bar
            slotTransmitBar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.2))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(slot.engine.state == .transmitting ? Color.red : (slot.isMonitoring ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2)), lineWidth: slot.engine.state == .transmitting ? 2 : 1)
        )
    }

    // MARK: - Slot Header

    private var slotHeaderBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(slot.engine.state == .transmitting ? Color.red : (slot.isMonitoring ? Color.green : Color.gray))
                .frame(width: 8, height: 8)

            Text(slot.name)
                .font(.headline)
                .fontWeight(.bold)

            Text(slot.driverType.shortTitle)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(4)

            Spacer()

            // Band preset selector
            Menu {
                ForEach(FT8BandPreset.common) { preset in
                    Button(action: { slot.setBandPreset(preset) }) {
                        Text(preset.label)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(slot.bandName)
                        .fontWeight(.bold)
                    Text(slot.formattedDialMHz)
                        .font(.system(.caption2, design: .monospaced))
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
            }
            .menuStyle(.borderlessButton)

            // Connect / Stop Toggle
            if slot.isMonitoring {
                Button(action: { slot.stopMonitoring() }) {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .help("Stop monitoring this radio")
            } else {
                Button(action: { slot.connectAndStartMonitoring(appState: appState) }) {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("Start monitoring this radio")
            }

            // Settings gear
            Button(action: onConfigure) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Transceiver hardware settings")
        }
    }

    // MARK: - Telemetry Gauges

    private var slotTelemetryBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text("S:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Text(String(format: "S%.0f", slot.engine.liveSMeter))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }

            HStack(spacing: 4) {
                Text("PWR:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f W", slot.engine.livePowerWatts))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }

            HStack(spacing: 4) {
                Text("SWR:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Text(String(format: "%.1f", slot.engine.liveSWR))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(slot.engine.liveSWR > 2.0 ? .red : .primary)
            }

            Spacer()

            Text(slot.slotStatusMessage)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Decodes List

    private var slotDecodesList: some View {
        VStack(spacing: 0) {
            let decodes = slot.engine.decodedRows
            if decodes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(slot.isMonitoring ? "Listening on \(slot.bandName)..." : "Radio offline. Click Play to start.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(decodes) { row in
                    decodeRowView(row)
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                }
                .listStyle(.plain)
            }
        }
    }

    private func decodeRowView(_ row: FT8DecodedRow) -> some View {
        HStack(spacing: 6) {
            // SNR
            Text(String(format: "%+03.0f", row.estimatedSNR))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(row.estimatedSNR >= 0 ? .green : (row.estimatedSNR > -10 ? .primary : .secondary))
                .frame(width: 26, alignment: .trailing)

            // Audio Frequency
            Text(String(format: "%04.0f", row.audioFrequencyHz))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .trailing)

            // Message text & flag
            HStack(spacing: 3) {
                Text(row.countryFlag)
                Text(row.text)
                    .font(.system(size: 11, design: .monospaced))
                    .fontWeight(row.isDirectedToMe ? .bold : (row.isCQ ? .semibold : .regular))
                    .foregroundColor(row.isDirectedToMe ? .purple : (row.isCQ ? .accentColor : .primary))
            }

            Spacer()

            // Badges
            if row.isNewDXCC {
                Text("DXCC")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.yellow.opacity(0.3))
                    .foregroundColor(.yellow)
                    .cornerRadius(3)
            }
            if row.isNewGrid {
                Text("GRID")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.25))
                    .foregroundColor(.green)
                    .cornerRadius(3)
            }

            // Quick Answer Button
            Button(action: {
                slot.engine.answerCallsign(row)
            }) {
                Text("Ans")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }

    // MARK: - Transmit Controls

    private var slotTransmitBar: some View {
        HStack(spacing: 6) {
            // Arm TX
            Toggle(isOn: $engine.transmitArmed) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(engine.transmitArmed ? Color.red : Color.gray)
                        .frame(width: 6, height: 6)
                    Text("Arm TX")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .toggleStyle(.button)
            .controlSize(.mini)
            .tint(.red)

            // Auto-Sequence
            Toggle(isOn: $engine.autoSequenceEnabled) {
                Text("Auto-Seq")
                    .font(.system(size: 10, weight: .semibold))
            }
            .toggleStyle(.button)
            .controlSize(.mini)

            // Call CQ
            Button(action: { engine.beginCQ() }) {
                Text("Call CQ")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            // Parity toggle
            Picker("", selection: $engine.txParity) {
                Text("1st (:00)").tag(SlotParity.even)
                Text("2nd (:15)").tag(SlotParity.odd)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
            .controlSize(.mini)

            Spacer()

            // DX Target Info
            if !slot.engine.dxCall.isEmpty {
                HStack(spacing: 4) {
                    Text("DX: \(slot.engine.dxCall)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                    if !slot.engine.dxGrid.isEmpty {
                        Text("(\(slot.engine.dxGrid))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
