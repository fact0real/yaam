//
//  CWPileupSimulatorView.swift
//  YAAM
//
//  Native High-Performance Pileup Contest Simulator (Morse Runner Workstation)
//  Spectral audio passband monitor, high-speed contest logging desk,
//  Enter-Sends-Message (ESM) automation, real-time rate meter, and contest logbook.
//

import Combine
import SwiftUI

public struct CWPileupSimulatorView: View {
    @ObservedObject private var sim = CWPileupSimulatorEngine.shared
    @FocusState private var isCallsignFocused: Bool
    @State private var showingSettingsSheet: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Top Contest Header & Status HUD
            contestHeaderHUD

            // Live Receiver Spectral Passband Scope
            spectralPassbandScope

            // Central Contest Operating Desk
            contestOperatingDesk

            // Function Keys & ESM Action Strip
            functionKeyActionStrip

            // Real-Time Contest Logbook Feed
            contestLogbookFeed
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(12)
        .onAppear {
            isCallsignFocused = true
        }
        .sheet(isPresented: $showingSettingsSheet) {
            simulatorSettingsSheet
        }
    }

    // MARK: - Top Contest Header & Status HUD

    private var contestHeaderHUD: some View {
        HStack(spacing: 16) {
            // Difficulty Preset Pill
            Menu {
                ForEach(CWPileupDifficulty.allCases) { diff in
                    Button {
                        sim.applyDifficultyPreset(diff)
                    } label: {
                        HStack {
                            Image(systemName: diff.iconName)
                            Text(diff.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: sim.difficulty.iconName)
                        .foregroundColor(.accentColor)
                    Text(sim.difficulty.shortTitle)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Station Callsign Indicator
            HStack(spacing: 4) {
                Text("DE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(sim.myCallsign.isEmpty ? "EP2AES" : sim.myCallsign.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
            .cornerRadius(6)

            // Live State Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(sim.state.statusBadgeColor)
                    .frame(width: 8, height: 8)
                Text(sim.state.rawValue.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(sim.state.statusBadgeColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(sim.state.statusBadgeColor.opacity(0.12))
            .cornerRadius(6)

            Spacer()

            // Real-Time Statistics Gauges
            HStack(spacing: 16) {
                statGauge(
                    title: "RATE",
                    value: String(format: "%.0f", sim.qsoRatePerHour),
                    unit: "/hr",
                    color: .cyan
                )

                statGauge(
                    title: "QSOS",
                    value: "\(sim.qsoCount)",
                    unit: "worked",
                    color: .green
                )

                statGauge(
                    title: "MULTS",
                    value: "\(sim.multiplierCount)",
                    unit: "px",
                    color: .orange
                )

                statGauge(
                    title: "SCORE",
                    value: "\(sim.totalScore)",
                    unit: "pts",
                    color: .yellow
                )

                statGauge(
                    title: "ACCURACY",
                    value: String(format: "%.0f%%", sim.accuracyPercentage),
                    unit: sim.currentStreak > 0 ? "🔥 \(sim.currentStreak)" : "streak",
                    color: sim.accuracyPercentage >= 90 ? .green : .orange
                )

                statGauge(
                    title: "ELAPSED",
                    value: formattedElapsed(sim.elapsedTimeSec),
                    unit: "utc",
                    color: .primary
                )
            }

            // Session Control Buttons
            HStack(spacing: 8) {
                if !sim.isRunning {
                    Button {
                        sim.startSession()
                        isCallsignFocused = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                            Text("Start Contest")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        sim.stopSession()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showingSettingsSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Contest Environment Settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
    }

    private func statGauge(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Live Receiver Spectral Passband Scope

    private var spectralPassbandScope: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                    Text("CW RECEIVER PASSBAND SPECTRUM")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Text("PITCH: \(Int(sim.centerPitchHz)) Hz")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)

                    Text("FILTER: \(Int(sim.filterBandwidthHz)) Hz BW")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)

                    Text("SPEED: \(sim.baseWPM) WPM")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)

                    if sim.qrnLevel > 0 {
                        Text("QRN: \(Int(sim.qrnLevel * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }

                    if sim.qsbEnabled {
                        Text("QSB: ON")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
            }

            // Canvas rendering the spectrum reticle, filter passband, and caller markers
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                ZStack(alignment: .leading) {
                    // Dark radio display background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.65))

                    // Grid lines (Frequency divisions: 400Hz, 500Hz, 600Hz, 700Hz, 800Hz, 900Hz)
                    HStack(spacing: 0) {
                        ForEach(0..<6) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(width: 1)
                            Spacer()
                        }
                    }

                    // Filter Passband Highlight (shaded band representing crystal/DSP IF filter)
                    let minFreq = 350.0
                    let maxFreq = 950.0
                    let freqRange = maxFreq - minFreq

                    let centerOffset = (sim.centerPitchHz - minFreq) / freqRange
                    let bwFraction = sim.filterBandwidthHz / freqRange
                    let filterWidth = max(20.0, width * CGFloat(bwFraction))
                    let filterStartX = max(0.0, width * CGFloat(centerOffset) - (filterWidth / 2.0))

                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: min(width, filterWidth), height: height)
                        .offset(x: filterStartX)

                    // Center Pitch Reticle Line
                    let centerX = width * CGFloat(centerOffset)
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: 1.5, height: height)
                        .offset(x: centerX)

                    // Active Caller Tone Markers
                    ForEach(sim.spectralMarkers) { marker in
                        let markerOffset = (marker.pitchHz - minFreq) / freqRange
                        let xPos = width * CGFloat(markerOffset)
                        let barHeight = max(10.0, height * CGFloat(marker.amplitude) * 0.85)

                        VStack(spacing: 2) {
                            Spacer()
                            Text(marker.isActive ? marker.callsign : "?")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(marker.isActive ? .green : .secondary)
                                .shadow(radius: 2)

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(marker.isActive ? Color.green : Color.orange.opacity(0.6))
                                .frame(width: 3, height: barHeight)
                        }
                        .offset(x: max(2.0, min(width - 40.0, xPos - 15.0)))
                    }
                }
            }
            .frame(height: 52)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(8)
    }

    // MARK: - Central Contest Operating Desk

    private var contestOperatingDesk: some View {
        HStack(spacing: 12) {
            // Callsign Entry Box
            VStack(alignment: .leading, spacing: 4) {
                Text("CALLSIGN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)

                    TextField("CALLSIGN", text: $sim.draftCallsign)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .textFieldStyle(.plain)
                        .focused($isCallsignFocused)
                        .onSubmit {
                            sim.handleEnterKey()
                        }
                        .onChange(of: sim.draftCallsign) { _, newValue in
                            sim.draftCallsign = newValue.uppercased()
                        }

                    if !sim.draftCallsign.isEmpty {
                        Button {
                            sim.draftCallsign = ""
                            isCallsignFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isCallsignFocused ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isCallsignFocused ? 2 : 1)
                )

                // Super Check Partial (SCP) Autocomplete HUD
                SuperCheckPartialHUDView(
                    targetCallsign: $sim.draftCallsign,
                    activeBand: "20M",
                    activeMode: "CW"
                ) { selectedCall in
                    sim.draftCallsign = selectedCall
                    isCallsignFocused = true
                }
            }
            .frame(maxWidth: 320)

            // Sent Exchange: RST + Serial
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SENT RST")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    Text(sim.draftRstSent)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 50, height: 32)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("SENT NR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    Text(String(format: "%03d", sim.draftSerialSent))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .frame(width: 60, height: 32)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                        .cornerRadius(6)
                }
            }

            // Received Exchange: RST + Serial
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RCVD RST")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    TextField("599", text: $sim.draftRstRcvd)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .textFieldStyle(.plain)
                        .frame(width: 50, height: 32)
                        .padding(.horizontal, 6)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("RCVD NR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    TextField("NR", text: $sim.draftSerialRcvd)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .textFieldStyle(.plain)
                        .frame(width: 65, height: 32)
                        .padding(.horizontal, 6)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .onSubmit {
                            sim.handleEnterKey()
                        }
                }
            }

            Spacer()

            // Large ESM Dynamic Action Button
            Button {
                sim.handleEnterKey()
                isCallsignFocused = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: esmIconName)
                        .font(.system(size: 14, weight: .bold))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(esmButtonTitle)
                            .font(.system(size: 13, weight: .bold))
                        Text(esmButtonSubtitle)
                            .font(.system(size: 9, weight: .medium))
                            .opacity(0.85)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minWidth: 150, minHeight: 46)
                .background(esmButtonColor)
                .cornerRadius(8)
                .shadow(color: esmButtonColor.opacity(0.3), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
        .cornerRadius(8)
    }

    private var esmButtonTitle: String {
        switch sim.state {
        case .idle, .paused:
            return sim.draftCallsign.isEmpty ? "⚡ Send CQ (↵)" : "⚡ Send Exch (↵)"
        case .pileupCalling:
            return sim.draftCallsign.isEmpty ? "⚡ Re-CQ (↵)" : "⚡ Send Exch (↵)"
        case .stationResponding:
            return "⚡ TU & Log (↵)"
        case .transmittingCQ:
            return "TX: Calling CQ..."
        case .transmittingExchange:
            return "TX: Sending Exch..."
        case .transmittingTU:
            return "TX: Finalizing..."
        }
    }

    private var esmButtonSubtitle: String {
        switch sim.state {
        case .idle, .paused:
            return sim.draftCallsign.isEmpty ? "F1: CQ TEST \(sim.myCallsign)" : "F2: \(sim.draftCallsign) 5NN \(String(format: "%03d", sim.draftSerialSent))"
        case .pileupCalling:
            return sim.draftCallsign.isEmpty ? "No call selected" : "Addressing \(sim.draftCallsign)"
        case .stationResponding:
            return "F3: TU \(sim.myCallsign) TEST"
        case .transmittingCQ, .transmittingExchange, .transmittingTU:
            return "Press Esc to Abort"
        }
    }

    private var esmButtonColor: Color {
        switch sim.state {
        case .idle, .paused:
            return sim.draftCallsign.isEmpty ? .blue : .orange
        case .pileupCalling:
            return sim.draftCallsign.isEmpty ? .secondary : .orange
        case .stationResponding:
            return .green
        case .transmittingCQ, .transmittingExchange, .transmittingTU:
            return .red
        }
    }

    private var esmIconName: String {
        switch sim.state {
        case .idle, .paused:
            return sim.draftCallsign.isEmpty ? "radiowaves.right" : "paperplane.fill"
        case .pileupCalling:
            return "person.3.sequence.fill"
        case .stationResponding:
            return "checkmark.circle.fill"
        case .transmittingCQ, .transmittingExchange, .transmittingTU:
            return "waveform"
        }
    }

    // MARK: - Function Keys & Macro Quick Bar

    private var functionKeyActionStrip: some View {
        HStack(spacing: 8) {
            macroButton(title: "F1: CQ", keyHint: "F1") {
                sim.executeSendCQ()
                isCallsignFocused = true
            }

            macroButton(title: "F2: Exch", keyHint: "F2") {
                sim.executeSendExchange()
                isCallsignFocused = true
            }

            macroButton(title: "F3: TU & Log", keyHint: "F3") {
                sim.executeSendTUAndLog()
                isCallsignFocused = true
            }

            macroButton(title: "F4: My Call", keyHint: "F4") {
                sim.executeSendCQ()
            }

            macroButton(title: "F7: ? (AGN)", keyHint: "F7") {
                sim.sendQueryAGN()
            }

            Spacer()

            if sim.state.isTransmitting {
                Button {
                    sim.abortTransmission()
                    isCallsignFocused = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.octagon.fill")
                        Text("Esc: Abort")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }

    private func macroButton(title: String, keyHint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Real-Time Contest Logbook Feed

    private var contestLogbookFeed: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text("CONTEST QSO LOGBOOK")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(sim.qsoRecords.count) QSOS LOGGED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if sim.qsoRecords.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No QSOs logged in this session yet.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Press 'Start Contest' or hit Enter to call CQ and start working the pileup!")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(sim.qsoRecords) { qso in
                            HStack(spacing: 12) {
                                Text(String(format: "#%03d", qso.qsoIndex))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, alignment: .leading)

                                Text(formattedTime(qso.timestamp))
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 55, alignment: .leading)

                                Text(qso.callsign)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(width: 90, alignment: .leading)

                                HStack(spacing: 4) {
                                    Text(qso.rstSent)
                                    Text(String(format: "%03d", qso.serialSent))
                                }
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 75, alignment: .leading)

                                HStack(spacing: 4) {
                                    Text(qso.rstRcvd)
                                    Text(String(format: "%03d", qso.serialRcvd))
                                }
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.cyan)
                                .frame(width: 75, alignment: .leading)

                                if qso.isMultiplier {
                                    Text("MULT")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange)
                                        .cornerRadius(3)
                                }

                                Spacer()

                                HStack(spacing: 4) {
                                    Image(systemName: qso.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(qso.isCorrect ? .green : .red)
                                    Text("+\(qso.points) pts")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(qso.isCorrect ? .green : .red)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(qso.isCorrect ? Color(NSColor.controlBackgroundColor).opacity(0.3) : Color.red.opacity(0.08))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 180)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Contest Environment Settings Sheet

    private var simulatorSettingsSheet: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.accentColor)
                    Text("Contest Simulator Configuration")
                        .font(.system(size: 14, weight: .bold))
                }
                Spacer()
                Button("Done") {
                    showingSettingsSheet = false
                    isCallsignFocused = true
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 4)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    // Operator Station Callsign
                    HStack {
                        Text("My Callsign:")
                            .frame(width: 140, alignment: .leading)
                        TextField("EP2AES", text: $sim.myCallsign)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Keyer Speed WPM
                    HStack {
                        Text("Contest Speed:")
                            .frame(width: 140, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(sim.baseWPM) },
                            set: { sim.baseWPM = Int($0) }
                        ), in: 16...45, step: 1)
                        Text("\(sim.baseWPM) WPM")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 65, alignment: .trailing)
                    }

                    // Center Pitch Hz
                    HStack {
                        Text("Sidetone Pitch:")
                            .frame(width: 140, alignment: .leading)
                        Slider(value: $sim.centerPitchHz, in: 450...850, step: 10)
                        Text("\(Int(sim.centerPitchHz)) Hz")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 65, alignment: .trailing)
                    }

                    // Receiver Filter Bandwidth
                    HStack {
                        Text("Receiver Bandwidth:")
                            .frame(width: 140, alignment: .leading)
                        Picker("", selection: $sim.filterBandwidthHz) {
                            Text("100 Hz (Ultra-Narrow)").tag(100.0)
                            Text("250 Hz (Contest CW)").tag(250.0)
                            Text("400 Hz (Standard CW)").tag(400.0)
                            Text("500 Hz (Wide)").tag(500.0)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Atmospheric Noise (QRN)
                    HStack {
                        Text("Atmospheric Noise (QRN):")
                            .frame(width: 140, alignment: .leading)
                        Slider(value: $sim.qrnLevel, in: 0.0...0.45, step: 0.05)
                        Text("\(Int(sim.qrnLevel * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 65, alignment: .trailing)
                    }

                    // Fading (QSB)
                    Toggle(isOn: $sim.qsbEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signal Fading (QSB)")
                                .fontWeight(.medium)
                            Text("Simulates natural ionospheric fading and signal flutter")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Interference (QRM)
                    Toggle(isOn: $sim.qrmEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Adjacent Interference (QRM)")
                                .fontWeight(.medium)
                            Text("Simulates interfering stations calling on adjacent frequencies")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Master Volume
                    HStack {
                        Text("Audio Sidetone Volume:")
                            .frame(width: 140, alignment: .leading)
                        Slider(value: $sim.audioVolume, in: 0.1...1.0)
                        Text("\(Int(sim.audioVolume * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 65, alignment: .trailing)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 480, height: 420)
    }

    // MARK: - Helpers

    private func formattedElapsed(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
