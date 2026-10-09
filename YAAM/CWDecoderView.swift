//
//  CWDecoderView.swift
//  YAAM
//
//  Real-Time DSP Morse Audio Decoder & Adaptive Station Co-Pilot Workstation
//  Combines Goertzel tone tracking, tuning spectrum scope, live acoustic metrics,
//  color-coded token stream, and 1-click adaptive reply automation.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

public struct CWDecoderView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var decoder = CWAudioDecoderEngine.shared
    @ObservedObject private var assistant = CWAdaptiveAssistant.shared
    @ObservedObject private var keyer = CWKeyerService.shared

    @State private var decoderMode: Int = 0 // 0: Single-Tone AFC Decoder, 1: Multi-Channel Passband Skimmer
    @State private var isDecodingFile: Bool = false
    @State private var fileDecodeStatus: String? = nil

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Mode Segmented Selector
            HStack {
                Picker("Decoder Mode", selection: $decoderMode) {
                    Label("Single-Tone AFC Decoder", systemImage: "waveform.path.badge.plus").tag(0)
                    Label("Multi-Channel Passband Skimmer", systemImage: "chart.bar.xaxis").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)

                Spacer()
            }

            if decoderMode == 0 {
                topControlBar
                tuningScopeAndMetricsRow
                decodedTextTerminal
                adaptiveAssistantRibbon
            } else {
                CWMultiChannelSkimmerView()
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(12)
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 12) {
            // Master Start / Stop Listening Button
            Button {
                if decoder.isListening {
                    decoder.stopListening()
                } else {
                    decoder.startListening()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: decoder.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title3)
                    Text(decoder.isListening ? "STOP DECODER" : "START DECODER")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(decoder.isListening ? .red : .green)

            // Audio Level VU Meter
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .foregroundColor(decoder.isSignalDetected ? .green : .secondary)
                    .font(.caption)

                ProgressView(value: Double(decoder.audioInputLevel), total: 1.0)
                    .frame(width: 60)
                    .tint(decoder.isSignalDetected ? .green : .accentColor)
            }

            Divider().frame(height: 20)

            // Center Frequency, AFC & Auto-Tune
            HStack(spacing: 5) {
                Text("TONE:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                Button {
                    decoder.decreasePitch()
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Decrease tone pitch by 25 Hz")

                Text("\(Int(decoder.centerFrequencyHz)) Hz")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(width: 48)

                Button {
                    decoder.increasePitch()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Increase tone pitch by 25 Hz")

                Button {
                    decoder.autoTunePitch()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.badge.automatic.fill")
                            .foregroundColor(.yellow)
                        Text("AUTO-TUNE")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                }
                .buttonStyle(.bordered)
                .help("Automatically detect and lock onto dominant CW tone across 300 - 1800 Hz.")

                Toggle("Auto-Track", isOn: $decoder.autoTrackPitch)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Continuously track tone pitch drifting across the spectrum.")

                Toggle("AFC", isOn: $decoder.afcEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Automatic Frequency Control: fine-tunes pitch within ±60 Hz.")
            }

            Divider().frame(height: 20)

            // Audio File Decoder Button
            Button {
                selectAndDecodeAudioFile()
            } label: {
                HStack(spacing: 4) {
                    if isDecodingFile {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "folder.badge.waveform")
                    }
                    Text(isDecodingFile ? "Decoding..." : "Decode File...")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isDecodingFile)
            .help("Open and decode an audio file (.m4a, .wav, .mp3, .aiff)")

            // Simulation / Practice Feed
            Button {
                decoder.toggleSimulation()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: decoder.isSimulationActive ? "bolt.fill" : "bolt")
                        .foregroundColor(decoder.isSimulationActive ? .yellow : .secondary)
                    Text(decoder.isSimulationActive ? "Sim Active" : "Practice Feed")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .tint(decoder.isSimulationActive ? .yellow : .secondary)
            .help("Toggle simulated on-air Morse traffic for testing without an audio source.")

            Spacer()

            // Clear Buffer
            Button {
                decoder.clearBuffer()
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Tuning Scope & Acoustic Metrics Row

    private var tuningScopeAndMetricsRow: some View {
        HStack(spacing: 12) {
            // Spectrum Scope Visualizer
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("AUDIO SPECTRUM (300 - 1800 Hz):")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.secondary)

                    Spacer()

                    if decoder.isSignalDetected {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text("TONE DETECTED")
                                .font(.system(size: 8.5, weight: .black))
                                .foregroundColor(.green)
                        }
                    }
                }

                // Bar spectrum graph
                HStack(alignment: .bottom, spacing: 2) {
                    if decoder.spectrumBins.isEmpty {
                        ForEach(0..<22, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(height: 12)
                        }
                    } else {
                        ForEach(decoder.spectrumBins) { bin in
                            let isTarget = abs(bin.frequencyHz - decoder.centerFrequencyHz) <= 20.0
                            let normalizedHeight = min(36.0, max(4.0, CGFloat(bin.magnitude) * 350.0))

                            RoundedRectangle(cornerRadius: 1)
                                .fill(isTarget ? Color.green : Color.accentColor.opacity(0.55))
                                .frame(height: normalizedHeight)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    decoder.setPitch(bin.frequencyHz)
                                }
                                .help("Click to tune to \(Int(bin.frequencyHz)) Hz")
                        }
                    }
                }
                .frame(height: 38)
            }
            .padding(10)
            .frame(maxWidth: 360)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Metrics Cards
            HStack(spacing: 10) {
                metricCard(
                    title: "EST. SPEED",
                    value: String(format: "%.1f WPM", decoder.estimatedWPM),
                    icon: "speedometer",
                    color: .blue
                )

                metricCard(
                    title: "SIGNAL / NOISE",
                    value: String(format: "+%.0f dB", decoder.signalToNoiseRatioDb),
                    icon: "waveform.path.ecg",
                    color: .green
                )

                metricCard(
                    title: "DIT / DAH",
                    value: String(format: "1 : %.2f", decoder.ditDahRatio),
                    icon: "slider.horizontal.2.square",
                    color: .purple
                )

                metricCard(
                    title: "PITCH LOCK",
                    value: "\(Int(decoder.centerFrequencyHz)) Hz",
                    icon: "tuningfork",
                    color: .orange
                )
            }
        }
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption2)
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Decoded Text Terminal

    private var decodedTextTerminal: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DECODED MORSE STREAM:")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(decoder.rawDecodedText, forType: .string)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(decoder.rawDecodedText.isEmpty)
            }

            if let status = fileDecodeStatus {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(status)
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Button {
                        fileDecodeStatus = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(4)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if decoder.decodedTokens.isEmpty {
                        Text(decoder.isListening ? "Listening for Morse tones on \(Int(decoder.centerFrequencyHz)) Hz..." : "Click 'Start Decoder' or 'Practice Feed' to begin decoding.")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    } else {
                        // Flow of color-coded tokens
                        FlowLayout(spacing: 6) {
                            ForEach(decoder.decodedTokens) { token in
                                Text(token.text)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(tokenBackgroundColor(token))
                                    .foregroundColor(tokenForegroundColor(token))
                                    .cornerRadius(4)
                            }
                            // Trailing anchor for auto-scroll
                            Color.clear.frame(width: 1, height: 1).id("bottomAnchor")
                        }
                        .padding(10)
                    }
                }
                .frame(minHeight: 110, maxHeight: 160)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                .onChange(of: decoder.decodedTokens.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottomAnchor", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func tokenBackgroundColor(_ token: CWDecodedToken) -> Color {
        if token.isCallsign {
            return Color.cyan.opacity(0.2)
        } else if token.isQCode {
            return Color.orange.opacity(0.2)
        } else if token.isReport {
            return Color.green.opacity(0.2)
        }
        return Color.secondary.opacity(0.1)
    }

    private func tokenForegroundColor(_ token: CWDecodedToken) -> Color {
        if token.isCallsign {
            return Color.cyan
        } else if token.isQCode {
            return Color.orange
        } else if token.isReport {
            return Color.green
        }
        return Color.primary
    }

    // MARK: - Adaptive Assistant Ribbon

    private var adaptiveAssistantRibbon: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile.fill")
                    .foregroundColor(.accentColor)
                Text("ADAPTIVE CW CO-PILOT:")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.primary)

                Text(assistant.intentDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()
            }

            if assistant.hasActionableSuggestion {
                HStack(spacing: 12) {
                    // Suggested Reply Box
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SUGGESTED REPLY:")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(assistant.suggestedReply)
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundColor(.accentColor)
                    }

                    Spacer()

                    // Action 1: Transmit Suggested Reply
                    Button {
                        assistant.sendSuggestedReply(myCall: appState.activeStationProfile?.normalizedCallsign ?? "")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                            Text("Send Reply")
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)

                    // Action 2: Sync Keyer WPM to incoming speed
                    Button {
                        assistant.syncSpeedToDecoder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "speedometer")
                            Text("Match \(Int(round(decoder.estimatedWPM))) WPM")
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Set your transmit keyer speed to match the incoming station's speed.")

                    // Action 3: Fill QuickLog
                    if !assistant.detectedCallsign.isEmpty {
                        Button {
                            assistant.populateQuickLog(appState: appState)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                Text("Fill QuickLog")
                                    .font(.caption.bold())
                            }
                        }
                        .buttonStyle(.bordered)
                        .help("Transfers detected callsign, RST report, and QTH directly into QuickLog.")
                    }
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
            }

            // Why "Send Reply" sent nothing (no callsign of the operator, or one that is not accepted)
            if !keyer.transmitRefusal.isEmpty {
                Text(keyer.transmitRefusal)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Audio File Selection & Decoding

    private func selectAndDecodeAudioFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Morse Audio File"
        panel.prompt = "Decode Audio"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .audio,
            .init(filenameExtension: "m4a") ?? .audio,
            .init(filenameExtension: "wav") ?? .audio,
            .init(filenameExtension: "mp3") ?? .audio,
            .init(filenameExtension: "aiff") ?? .audio
        ]

        if panel.runModal() == .OK, let url = panel.url {
            isDecodingFile = true
            fileDecodeStatus = "Decoding \(url.lastPathComponent)..."
            Task {
                do {
                    let text = try await decoder.decodeAudioFile(at: url)
                    await MainActor.run {
                        self.isDecodingFile = false
                        self.fileDecodeStatus = text.isEmpty ? "Decoded file: No clear Morse detected." : "Decoded: \(text)"
                    }
                } catch {
                    await MainActor.run {
                        self.isDecodingFile = false
                        self.fileDecodeStatus = "Decode error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

// MARK: - Minimal Flow Layout for Token Stream

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 500
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            height = currentY + lineHeight
        }

        return CGSize(width: maxWidth, height: max(height, 30))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
