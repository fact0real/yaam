//
//  CWMultiChannelSkimmerView.swift
//  YAAM
//
//  Native Multi-Channel CW Passband Mini-Skimmer Workstation View
//  Visual passband spectrum monitor, real-time multi-channel call roster,
//  1-click CAT Zero-Beat tuning, and QuickLog co-pilot.
//

import Combine
import SwiftUI

public struct CWMultiChannelSkimmerView: View {
    @ObservedObject private var skimmer = CWMultiChannelSkimmerEngine.shared
    @EnvironmentObject private var appState: AppState
    @State private var feedbackText: String? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Top Skimmer Control Bar
            topControlBar

            // Multichannel Audio Passband Spectrum Scope
            passbandSpectrumScope

            // Central Split: Live Skimmer Call Roster & Selected Channel Transcript
            HStack(alignment: .top, spacing: 12) {
                // Left: Live Skimmer Call Roster Table
                liveSkimmerRosterTable
                    .frame(minWidth: 420)

                // Right: Active Channel Transcript & Inspector
                channelInspectorPanel
                    .frame(width: 260)
            }
        }
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 12) {
            // Master Start / Stop Listening Button
            Button {
                if skimmer.isListening {
                    skimmer.stopSkimmer()
                } else {
                    skimmer.startSkimmer()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: skimmer.isListening ? "stop.circle.fill" : "antenna.radiowaves.left.and.right")
                        .font(.title3)
                    Text(skimmer.isListening ? "STOP SKIMMER" : "START SKIMMER")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(skimmer.isListening ? .red : .accentColor)

            // Audio Level VU Meter
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .foregroundColor(skimmer.audioInputLevel > 0.05 ? .green : .secondary)
                    .font(.caption)

                ProgressView(value: Double(skimmer.audioInputLevel), total: 1.0)
                    .frame(width: 65)
                    .tint(skimmer.audioInputLevel > 0.3 ? .green : .accentColor)
            }

            Divider().frame(height: 20)

            // Channel Bank Summary
            HStack(spacing: 6) {
                Text("BANK:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text("\(skimmer.channels.count) CHANNELS (450–900 Hz)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Divider().frame(height: 20)

            // Multi-Station Simulation Toggle
            Button {
                skimmer.toggleSimulation()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: skimmer.isSimulationActive ? "bolt.fill" : "bolt")
                        .foregroundColor(skimmer.isSimulationActive ? .yellow : .secondary)
                    Text(skimmer.isSimulationActive ? "Sim Traffic ON" : "Test Feed")
                        .font(.caption.bold())
                }
            }
            .buttonStyle(.bordered)
            .tint(skimmer.isSimulationActive ? .yellow : .secondary)
            .help("Toggle multi-station simulated Morse traffic across channels (W1AW @ 500Hz, DL1ABC @ 650Hz, JA1BJK @ 800Hz)")

            Spacer()

            // Feedback Banner
            if let feedback = feedbackText {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(feedback)
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
                .transition(.opacity)
            }

            // Clear Roster Button
            Button {
                skimmer.clearRoster()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Clear")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Multichannel Audio Passband Spectrum Scope

    private var passbandSpectrumScope: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text("AUDIO PASSBAND MULTI-CHANNEL SPECTRUM")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Text("CENTER: \(Int(skimmer.nominalPitchHz)) Hz")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)

                    Text("ACTIVE CHANNELS: \(skimmer.channels.filter { $0.isSignalActive }.count) / \(skimmer.channels.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(skimmer.channels.contains { $0.isSignalActive } ? .green : .secondary)
                }
            }

            // Visual Scope Canvas
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                ZStack(alignment: .bottomLeading) {
                    // Dark Scope Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.70))

                    // Frequency division grid lines (400, 500, 600, 700, 800, 900, 1000 Hz)
                    let minFreq = 400.0
                    let maxFreq = 950.0
                    let span = maxFreq - minFreq

                    HStack(spacing: 0) {
                        ForEach(0..<6) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 1)
                            Spacer()
                        }
                    }

                    // Nominal Sidetone Center Line (650 Hz)
                    let centerFraction = (skimmer.nominalPitchHz - minFreq) / span
                    Rectangle()
                        .fill(Color.cyan.opacity(0.65))
                        .frame(width: 1.5, height: height)
                        .offset(x: width * CGFloat(centerFraction))

                    // Channels Pillars & Floating Badges
                    ForEach(skimmer.channels) { ch in
                        let fraction = (ch.centerFreqHz - minFreq) / span
                        let xPos = width * CGFloat(fraction)
                        let barHeight = max(4.0, height * CGFloat(min(1.0, ch.signalLevel * 18.0)))

                        VStack(spacing: 2) {
                            Spacer()

                            // Callsign Bubble if station identified
                            if let call = ch.identifiedCallsign {
                                Text(call)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor)
                                    .cornerRadius(3)
                                    .shadow(radius: 2)
                            }

                            // Signal Level Needle
                            RoundedRectangle(cornerRadius: 2)
                                .fill(ch.isSignalActive ? Color.green : (ch.id == skimmer.selectedChannelId ? Color.accentColor : Color.white.opacity(0.35)))
                                .frame(width: 8, height: barHeight)

                            // Channel Frequency Label
                            Text("\(Int(ch.centerFreqHz))")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 32)
                        .offset(x: max(0, min(width - 32, xPos - 16)))
                        .onTapGesture {
                            skimmer.selectedChannelId = ch.id
                        }
                    }
                }
            }
            .frame(height: 75)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Live Skimmer Call Roster Table

    private var liveSkimmerRosterTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                    Text("LIVE SKIMMER CALL ROSTER")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(skimmer.spots.count) ACTIVE SPOTS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if skimmer.spots.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary.opacity(0.35))
                    Text("No CW stations detected in passband yet.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Click 'Test Feed' or connect receiver audio to monitor stations.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(skimmer.spots) { spot in
                            spotRow(spot)
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 260)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private func spotRow(_ spot: CWSkimmerSpot) -> some View {
        HStack(spacing: 8) {
            // Audio Pitch
            Text("\(Int(spot.audioFreqHz)) Hz")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
                .frame(width: 58, alignment: .leading)

            // Callsign & Country Flag
            HStack(spacing: 4) {
                Text(spot.countryFlag)
                Text(spot.callsign)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .frame(width: 100, alignment: .leading)

            // Speed WPM
            Text("\(spot.wpm) WPM")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 55, alignment: .leading)

            // SNR Badge
            Text(String(format: "+%.0f dB", spot.snrDb))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(spot.snrDb >= 12.0 ? .green : .orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background((spot.snrDb >= 12.0 ? Color.green : Color.orange).opacity(0.12))
                .cornerRadius(3)
                .frame(width: 55, alignment: .leading)

            // Intent Badge
            intentBadge(for: spot.intent)

            // Message Snippet
            Text(spot.snippet)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // 1-Click Zero-Beat & QuickLog Action Button
            Button {
                skimmer.tuneToSpot(spot)
                let delta = Int(skimmer.calculateZeroBeatDelta(for: spot))
                let sign = delta >= 0 ? "+" : ""
                feedbackText = "QSY \(sign)\(delta) Hz & Loaded \(spot.callsign)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    feedbackText = nil
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                    Text("QSY & Log")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Zero-Beat transceiver by adjusting VFO/RIT to match this station's pitch, and pre-fill QuickLog.")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(5)
    }

    private func intentBadge(for intent: CWQSOIntent) -> some View {
        Group {
            switch intent {
            case .callingCQ:
                Text("CQ")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue)
                    .cornerRadius(3)
            case .contestExchange:
                Text("EXCH")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .cornerRadius(3)
            case .signOff:
                Text("73")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.purple)
                    .cornerRadius(3)
            case .ragchewInfo, .general:
                EmptyView()
            }
        }
    }

    // MARK: - Active Channel Transcript & Inspector

    private var channelInspectorPanel: some View {
        let selectedCh = skimmer.channels.first { $0.id == skimmer.selectedChannelId } ?? skimmer.channels.first

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill((selectedCh?.isSignalActive ?? false) ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text("CH \(Int(selectedCh?.centerFreqHz ?? 650)) Hz")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }

                Spacer()

                Text("\(Int(selectedCh?.estimatedWPM ?? 20)) WPM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Channel Selector Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(skimmer.channels) { ch in
                        let isSel = ch.id == skimmer.selectedChannelId
                        Button {
                            skimmer.selectedChannelId = ch.id
                        } label: {
                            Text("\(Int(ch.centerFreqHz))")
                                .font(.system(size: 9, weight: isSel ? .bold : .medium, design: .monospaced))
                                .foregroundColor(isSel ? .white : .primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(isSel ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Dit-Dah Buffer
            HStack {
                Text("ELEMENTS:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Text((selectedCh?.activeCharacterBuffer.isEmpty ?? true) ? "idle" : selectedCh!.activeCharacterBuffer)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
            }

            // Decoded Text Stream for this Channel
            VStack(alignment: .leading, spacing: 2) {
                Text("DECODED STREAM:")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                ScrollView {
                    Text((selectedCh?.rawDecodedText.isEmpty ?? true) ? "Awaiting CW signals on this channel..." : selectedCh!.rawDecodedText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor((selectedCh?.rawDecodedText.isEmpty ?? true) ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(minHeight: 120, maxHeight: 180)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}
