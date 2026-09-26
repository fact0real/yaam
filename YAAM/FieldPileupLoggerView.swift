//
//  FieldPileupLoggerView.swift
//  YAAM
//
//  Ultra-Fast Keyboard-First Pileup Logger for POTA & SOTA Field Operations.
//  Includes Outdoor Direct Sunlight High-Contrast Mode, 10-QSO Milestone Dial,
//  CAT-synced frequency/band readouts, and immediate Space/Enter logging ergonomics.
//

import AppKit
import Combine
import SwiftUI

public struct FieldPileupLoggerView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var potaEngine = POTASOTAEngine.shared
    @ObservedObject private var rigEngine = RigControlEngine.shared

    // Form inputs
    @State private var inputCallsign: String = ""
    @State private var inputSentRST: String = "59"
    @State private var inputRcvdRST: String = "59"
    @State private var inputContactedRef: String = ""
    @State private var inputComment: String = ""

    // Session Start / Config Sheet
    @State private var showStartSessionSheet: Bool = false
    @State private var sessionParkRef: String = "EP-0005"
    @State private var sessionParkName: String = "Lar National Park"
    @State private var sessionProgram: FieldProgramType = .pota
    @State private var sessionGrid: String = "LM35"

    // UI Feedback
    @State private var dupeWarning: String? = nil
    @State private var statusToast: String? = nil
    @FocusState private var isCallsignFocused: Bool
    @FocusState private var isRefFocused: Bool

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Session Control & Telemetry Strip
            sessionHeaderStrip

            Divider()

            // 2. Main Work Area: Pileup Logger HUD + 10-QSO Dial + Recent QSOs
            if let session = potaEngine.activeSession, session.isActive {
                HStack(alignment: .top, spacing: 16) {
                    // Left Column: Fast-Input Logger Console
                    VStack(alignment: .leading, spacing: 14) {
                        // Radio Frequency / Mode Banner
                        rigSyncBanner

                        // Main Call Input Form
                        keyboardInputCard(session: session)

                        // Milestone Ring & Statistics Card
                        milestoneAndStatsCard(session: session)
                    }
                    .frame(maxWidth: .infinity)

                    // Right Column: Live Session Log Table
                    sessionLogTable(session: session)
                        .frame(width: 380)
                }
                .padding(16)
                .background(potaEngine.isOutdoorHighContrastMode ? Color.black : Color(NSColor.windowBackgroundColor))
            } else {
                noActiveSessionPlaceholder
            }
        }
        .sheet(isPresented: $showStartSessionSheet) {
            startSessionSheet
        }
        .onAppear {
            isCallsignFocused = true
            updateDefaultRST()
        }
        .onChange(of: rigEngine.mode) { _, _ in
            updateDefaultRST()
        }
    }

    // MARK: - Session Header Strip
    private var sessionHeaderStrip: some View {
        HStack(spacing: 12) {
            if let session = potaEngine.activeSession, session.isActive {
                Image(systemName: session.program.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("\(session.program.rawValue) ACTIVE:")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.green)

                        Text(session.myReference)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)

                        Text("· \(session.referenceName)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text("Grid: \(session.gridSquare) · Op: \(session.operatorCallsign)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Outdoor High Contrast Toggle
                Button {
                    potaEngine.isOutdoorHighContrastMode.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: potaEngine.isOutdoorHighContrastMode ? "sun.max.fill" : "sun.max")
                        Text(potaEngine.isOutdoorHighContrastMode ? "Sun Mode ON" : "Sun Mode")
                    }
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(potaEngine.isOutdoorHighContrastMode ? .yellow : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(potaEngine.isOutdoorHighContrastMode ? Color.yellow.opacity(0.18) : Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(potaEngine.isOutdoorHighContrastMode ? Color.yellow : Color.secondary.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Sound Toggle
                Button {
                    potaEngine.playAudioFeedbackOnLog.toggle()
                } label: {
                    Image(systemName: potaEngine.playAudioFeedbackOnLog ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(potaEngine.playAudioFeedbackOnLog ? .green : .secondary)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Play audio confirmation tone on every logged QSO")

                // End Session Button
                Button("End Session") {
                    potaEngine.endSession()
                }
                .font(.system(size: 10.5, weight: .bold))
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "figure.hiking")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Field Operations Standby")
                        .font(.system(size: 12, weight: .bold))
                    Text("Select or start a park/summit activation session")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showStartSessionSheet = true
                } label: {
                    Label("Start New Activation", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Rig Sync Banner
    private var rigSyncBanner: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(rigEngine.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                Text(rigEngine.isConnected ? rigEngine.rigModel : "CAT Disconnected")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Frequency Display
            HStack(spacing: 4) {
                Text("FREQ:")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(rigEngine.isConnected ? rigEngine.formattedFrequency : "14.074000 MHz")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(potaEngine.isOutdoorHighContrastMode ? Color.yellow : Color.accentColor)
            }

            // Band / Mode
            HStack(spacing: 4) {
                Text(rigEngine.isConnected ? rigEngine.currentBand : "20m")
                    .font(.system(size: 11, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))

                Text(rigEngine.isConnected ? rigEngine.mode : "SSB")
                    .font(.system(size: 11, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(potaEngine.isOutdoorHighContrastMode ? Color(white: 0.12) : Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Keyboard Input Card
    private var isHighContrast: Bool { potaEngine.isOutdoorHighContrastMode }

    private func keyboardInputCard(session: FieldActivationSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("QUICK-FIRE PILEUP LOGGER")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(isHighContrast ? Color.yellow : Color.secondary)

                Spacer()

                Text("⌨️ [Space] = Next Field  ·  [Enter] = Log QSO")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isHighContrast ? Color.white : Color.secondary)
            }

            // Main Callsign Input Row
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CALLSIGN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isHighContrast ? Color.yellow : Color.secondary)

                    TextField("EP2XXX, W1AW, ...", text: $inputCallsign)
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .textCase(.uppercase)
                        .focused($isCallsignFocused)
                        .onSubmit {
                            handleQuickLogSubmit()
                        }
                        .padding(8)
                        .background(isHighContrast ? Color(white: 0.15) : Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isHighContrast ? Color.yellow : Color.accentColor, lineWidth: isCallsignFocused ? 2 : 1)
                        )
                }

                // Sent & Rcvd RST
                VStack(alignment: .leading, spacing: 3) {
                    Text("SENT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isHighContrast ? Color.yellow : Color.secondary)
                    TextField("59", text: $inputSentRST)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .frame(width: 55)
                        .padding(8)
                        .background(isHighContrast ? Color(white: 0.15) : Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("RCVD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isHighContrast ? Color.yellow : Color.secondary)
                    TextField("59", text: $inputRcvdRST)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .frame(width: 55)
                        .padding(8)
                        .background(isHighContrast ? Color(white: 0.15) : Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }

                // Park to Park (P2P / S2S) Reference Field
                VStack(alignment: .leading, spacing: 3) {
                    Text("P2P / S2S REF")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isHighContrast ? Color.yellow : Color.orange)

                    TextField("e.g. K-0020", text: $inputContactedRef)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .textCase(.uppercase)
                        .focused($isRefFocused)
                        .frame(width: 120)
                        .padding(8)
                        .background(isHighContrast ? Color(white: 0.15) : Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }

                // Submit Button
                Button {
                    handleQuickLogSubmit()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("LOG")
                            .font(.system(size: 11, weight: .black))
                    }
                    .frame(width: 60, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.top, 14)
            }

            // Dupe warning or toast
            if let dupe = dupeWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(dupe)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(isHighContrast ? Color.black : Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isHighContrast ? Color.yellow.opacity(0.8) : Color.secondary.opacity(0.2), lineWidth: 1.2))
    }

    // MARK: - Milestone Dial & Statistics Card
    private func milestoneAndStatsCard(session: FieldActivationSession) -> some View {
        HStack(spacing: 20) {
            // Circular Progress Dial
            ZStack {
                Circle()
                    .stroke(isHighContrast ? Color(white: 0.25) : Color.secondary.opacity(0.2), lineWidth: 10)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: CGFloat(session.progressFraction))
                    .stroke(session.isQualified ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 80, height: 80)
                    .animation(.spring(), value: session.qsoCount)

                VStack(spacing: 0) {
                    Text("\(session.qsoCount)")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundStyle(session.isQualified ? .green : .primary)
                    Text("/ \(session.targetGoal)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }

            // Milestone Status & Rate
            VStack(alignment: .leading, spacing: 6) {
                if session.isQualified {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))
                        Text("ACTIVATION QUALIFIED!")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.green)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .foregroundStyle(.orange)
                        Text("\(session.remainingToQualify) QSOs to Qualify")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 16) {
                    statBox(title: "QSO Rate", value: String(format: "%.1f /hr", session.qsoRatePerHour))
                    statBox(title: "Park to Park (P2P)", value: "\(session.parkToParkCount)")
                    statBox(title: "Bands Worked", value: "\(session.workedBands.count)")
                }
            }

            Spacer()
        }
        .padding(14)
        .background(isHighContrast ? Color(white: 0.08) : Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(isHighContrast ? Color.white : Color.primary)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(isHighContrast ? Color.yellow.opacity(0.8) : Color.secondary)
        }
    }

    // MARK: - Session Log Table
    private func sessionLogTable(session: FieldActivationSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SESSION LOGS (\(potaEngine.sessionQSOs.count))")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(isHighContrast ? Color.yellow : Color.secondary)

                Spacer()

                Button {
                    let adif = FieldLogExporter.buildPOTAADIF(records: potaEngine.sessionQSOs, session: session)
                    let filename = FieldLogExporter.generatePOTAFilename(callsign: session.operatorCallsign, reference: session.myReference)
                    FieldLogExporter.promptSaveFile(filename: filename, content: adif)
                } label: {
                    Label("Export ADIF", systemImage: "square.and.arrow.up")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
            }

            Divider()

            if potaEngine.sessionQSOs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No contacts in this activation yet.\nCall CQ and log your callers above!")
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(potaEngine.sessionQSOs, id: \.id) { qso in
                        HStack(spacing: 8) {
                            Text(qso["TIME_ON"].prefix(4).description)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text(qso["CALL"])
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundStyle(isHighContrast ? Color.white : Color.primary)

                            Spacer()

                            Text("\(qso["BAND"]) · \(qso["MODE"])")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.secondary)

                            if !qso["POTA_REF"].isEmpty || !qso["SOTA_REF"].isEmpty {
                                Text("P2P")
                                    .font(.system(size: 8, weight: .heavy))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(.green)
                            }

                            Text(qso["RST_RCVD"])
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(12)
        .background(isHighContrast ? Color(white: 0.08) : Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - No Active Session Placeholder
    private var noActiveSessionPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "tent.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Ready for Field Operation")
                .font(.title2.bold())

            Text("Activate a park (POTA), mountain summit (SOTA), or nature reserve (WWFF).\nClick below to configure your field callsign, park reference, and antenna setup.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 450)

            Button {
                showStartSessionSheet = true
            } label: {
                Label("Start Activation Session", systemImage: "play.circle.fill")
                    .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Start Session Sheet
    private var startSessionSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Start Field Activation Session", systemImage: "figure.hiking")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    showStartSessionSheet = false
                }
            }
            .padding(16)

            Divider()

            Form {
                Picker("Program:", selection: $sessionProgram) {
                    ForEach(FieldProgramType.allCases) { prog in
                        Label(prog.rawValue, systemImage: prog.icon).tag(prog)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Park/Summit Reference (e.g. EP-0005 or K-0001):", text: $sessionParkRef)
                TextField("Location / Park Name:", text: $sessionParkName)
                TextField("Maidenhead Grid Square:", text: $sessionGrid)
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button("Start Activation") {
                    let call = appState.activeStationProfile?.normalizedCallsign ?? appState.currentStationCallsign
                    potaEngine.startSession(
                        program: sessionProgram,
                        reference: sessionParkRef,
                        parkName: sessionParkName,
                        callsign: call,
                        grid: sessionGrid
                    )
                    showStartSessionSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(16)
        }
        .frame(width: 480, height: 320)
    }

    // MARK: - Helpers
    private func handleQuickLogSubmit() {
        dupeWarning = nil
        let call = inputCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !call.isEmpty else { return }

        let result = potaEngine.logFieldQSO(
            callsign: call,
            sentRST: inputSentRST,
            receivedRST: inputRcvdRST,
            contactedRef: inputContactedRef,
            comment: inputComment,
            appState: appState
        )

        switch result {
        case .success:
            inputCallsign = ""
            inputContactedRef = ""
            inputComment = ""
            updateDefaultRST()
            isCallsignFocused = true
        case .failure(let err):
            dupeWarning = err.localizedDescription
        }
    }

    private func updateDefaultRST() {
        let currentMode = rigEngine.isConnected ? rigEngine.mode : appState.quickLogDraft.mode
        if currentMode.uppercased().contains("CW") || currentMode.uppercased().contains("FT8") || currentMode.uppercased().contains("DATA") {
            inputSentRST = "599"
            inputRcvdRST = "599"
        } else {
            inputSentRST = "59"
            inputRcvdRST = "59"
        }
    }
}
