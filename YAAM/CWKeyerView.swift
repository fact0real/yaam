//
//  CWKeyerView.swift
//  YAAM
//
//  Interactive CW Keyer & Macro Console UI
//  Professional amateur-radio CW workstation featuring F1-F12 memory banks (RUN, S&P, Ragchew, Custom),
//  dynamic token previews, Auto-CQ repeater loop, WPM dial with speed presets, cut-numbers toggle,
//  sidetone pitch/volume controls, live type-ahead transmitter, and sent history.
//

import Combine
import SwiftUI

public struct CWKeyerView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var keyer = CWKeyerService.shared
    @ObservedObject private var esm = CWESMEngine.shared

    @State private var liveInputText: String = ""
    @State private var editingMacro: CWMacro? = nil
    @State private var showResetAlert: Bool = false
    @State private var showTokenCheatSheet: Bool = false
    @State private var showHardwareSetupSheet: Bool = false

    public init() {}

    private static let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    public var body: some View {
        VStack(spacing: 12) {
            // Workstation Top Segment Selector
            HStack {
                Picker("Workstation", selection: $appState.cwWorkstationSection) {
                    Label("Memories Console", systemImage: "tuningfork").tag(0)
                    Label("CW Academy & Trainer", systemImage: "graduationcap.fill").tag(1)
                    Label("Q-Codes & Prosigns", systemImage: "book.closed.fill").tag(2)
                    Label("DSP Audio Decoder", systemImage: "headphones").tag(3)
                    Label("Pileup Trainer", systemImage: "antenna.radiowaves.left.and.right.circle").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 820)

                Spacer()
            }

            if appState.cwWorkstationSection == 0 {
                topControlBar
                liveStatusHUD
                bankSelectorBar
                macroGrid
                autoCQAndTokenBar
                liveTypewriterBar
            } else if appState.cwWorkstationSection == 1 {
                CWAcademyView()
            } else if appState.cwWorkstationSection == 2 {
                CWReferenceDeskView()
            } else if appState.cwWorkstationSection == 3 {
                CWDecoderView()
            } else {
                CWPileupSimulatorView()
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(12)
        .sheet(item: $editingMacro) { macro in
            MacroEditorSheet(macro: macro) { updatedLabel, updatedTemplate in
                keyer.updateMacro(
                    bank: keyer.activeBank,
                    id: macro.id,
                    label: updatedLabel,
                    template: updatedTemplate
                )
            }
        }
        .sheet(isPresented: $showHardwareSetupSheet) {
            CWHardwareSetupSheet()
        }
        .alert("Reset Bank to Defaults?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                keyer.resetBankToDefaults(bank: keyer.activeBank)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore all F1–F12 memories in '\(keyer.activeBank.rawValue)' to their default templates.")
        }
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 12) {
            // Backend Selector
            Menu {
                ForEach(CWTransmissionMode.allCases) { mode in
                    Button {
                        keyer.transmissionMode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: mode.iconName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: keyer.transmissionMode.iconName)
                        .foregroundColor(.accentColor)
                    Text(keyer.transmissionMode.rawValue)
                        .font(.caption.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Hardware Status Pill & Setup Trigger
            let hwStatus = keyer.hardwareStatusSummary
            Button {
                showHardwareSetupSheet = true
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(hwStatus.isConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(hwStatus.title)
                        .font(.caption2.bold())
                    Text("(\(hwStatus.detail))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "gearshape.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hwStatus.isConnected ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .help("Configure CW Hardware Keying (WinKeyer, DTR/RTS, CAT)")

            Divider().frame(height: 20)

            // WPM Speed Controller & Presets
            HStack(spacing: 6) {
                Text("SPEED:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                Button {
                    keyer.decreaseWPM()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Text("\(keyer.wpm) WPM")
                    .font(.system(.subheadline, design: .monospaced).bold())
                    .frame(width: 68)

                Button {
                    keyer.increaseWPM()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                // Quick Speed Presets
                HStack(spacing: 3) {
                    ForEach([18, 22, 26, 30, 34], id: \.self) { speed in
                        Button("\(speed)") {
                            keyer.setWPM(speed)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, weight: keyer.wpm == speed ? .bold : .regular, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(keyer.wpm == speed ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                    }
                }
            }

            Divider().frame(height: 20)

            // Sidetone Pitch & Toggle
            HStack(spacing: 6) {
                Toggle("Sidetone", isOn: $keyer.sidetoneEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                if keyer.sidetoneEnabled {
                    Text("\(Int(keyer.sidetonePitchHz))Hz")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)

                    Slider(value: $keyer.sidetonePitchHz, in: 400...900, step: 25)
                        .frame(width: 60)
                        .controlSize(.mini)
                }
            }

            Divider().frame(height: 20)

            // Cut Numbers Toggle
            Toggle(isOn: $keyer.useCutNumbers) {
                HStack(spacing: 4) {
                    Text("5NN")
                        .font(.caption.bold())
                    Text("Cut")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .help("Cut numbers: replaces 9 with N, 0 with T, 1 with A in reports and serials.")

            Spacer()

            // Emergency Stop / ESC Button
            if keyer.isTransmitting || keyer.isAutoCQActive {
                Button(role: .destructive) {
                    keyer.stop()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.circle.fill")
                        Text("STOP (ESC)")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Live Status HUD

    private var liveStatusHUD: some View {
        Group {
            if keyer.isTransmitting {
                HStack(spacing: 12) {
                    // Pulsing Red TX Indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.red.opacity(0.5), lineWidth: 3)
                                    .scaleEffect(1.3)
                            )
                        Text("ON AIR TX")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                    }

                    Image(systemName: "waveform")
                        .foregroundColor(.red)
                        .font(.caption)

                    // Monospace Stream of Active Outgoing Text
                    Text(keyer.activeBufferText)
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    if !keyer.currentlyTransmittingChar.isEmpty {
                        Text("Char: [\(keyer.currentlyTransmittingChar)]")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                .padding(10)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 1))
            } else if keyer.isAutoCQActive {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "repeat.circle.fill")
                            .foregroundColor(.orange)
                        Text("AUTO-CQ ACTIVE")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }

                    Text("Next CQ in \(keyer.autoCQCountdown)s (Interval: \(keyer.autoCQIntervalSeconds)s)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Stop Loop") {
                        keyer.stopAutoCQ()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            }
        }
    }

    // MARK: - Bank Selector Bar

    private var bankSelectorBar: some View {
        HStack(spacing: 10) {
            Picker("Memory Bank", selection: $keyer.activeBank) {
                ForEach(CWMemoryBank.allCases) { bank in
                    Label(bank.rawValue, systemImage: bank.iconName).tag(bank)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)
            .onChange(of: keyer.activeBank) { _, newBank in
                if newBank == .run {
                    esm.operatingMode = .run
                } else if newBank == .searchAndPounce {
                    esm.operatingMode = .searchAndPounce
                }
            }

            // ESM Contest Automation Pill
            Button {
                esm.isEnabled.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: esm.isEnabled ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 11, weight: .bold))
                    Text("ESM:")
                        .font(.caption.bold())
                    Text(esm.isEnabled ? esm.operatingMode.shortCode : "OFF")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(esm.isEnabled ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12))
                )
                .foregroundColor(esm.isEnabled ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Enter-Sends-Message (ESM): Pressing Enter in QuickLog sends CW automatically (Ctrl+M)")

            Spacer()

            Button {
                showResetAlert = true
            } label: {
                Label("Reset Bank", systemImage: "arrow.counterclockwise")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - F1 - F12 Macro Cards Grid

    private var macroGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: 10) {
            ForEach(keyer.macros) { macro in
                MacroCardView(
                    macro: macro,
                    evaluatedPreview: evaluateMacro(macro.template),
                    onTrigger: {
                        triggerMacro(macro)
                    },
                    onEdit: {
                        editingMacro = macro
                    }
                )
            }
        }
    }

    // MARK: - Auto-CQ & Token Helper Ribbon

    private var autoCQAndTokenBar: some View {
        HStack(spacing: 12) {
            // Auto-CQ trigger button and interval controller
            HStack(spacing: 6) {
                Button {
                    let firstMacro = keyer.macros.first?.template ?? "CQ TEST {MYCALL} {MYCALL} TEST"
                    keyer.toggleAutoCQ(
                        template: firstMacro,
                        myCall: currentMyCall,
                        call: currentTargetCall,
                        rst: currentRST,
                        name: currentName,
                        qth: currentQTH,
                        serial: currentSerial,
                        exch: currentExchange,
                        band: currentBand,
                        freq: currentFreq
                    )
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: keyer.isAutoCQActive ? "stop.fill" : "play.fill")
                        Text(keyer.isAutoCQActive ? "Stop Auto-CQ" : "Auto-CQ [F1]")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(keyer.isAutoCQActive ? .orange : .accentColor)

                Text("Pause:")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Stepper("\(keyer.autoCQIntervalSeconds)s", value: $keyer.autoCQIntervalSeconds, in: 2...15)
                    .font(.caption2.monospacedDigit())
            }

            Spacer()

            // Token chips palette
            HStack(spacing: 4) {
                Text("Tokens:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                ForEach(["{CALL}", "{SERIAL}", "{EXCH}", "{MYCALL}", "{SENT_RST}"], id: \.self) { token in
                    Button(token) {
                        liveInputText += (liveInputText.isEmpty ? "" : " ") + token
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)
                    .help("Click to insert \(token) into live transmitter")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Freeform Live CW Typewriter & Sent History

    private var liveTypewriterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "tuningfork")
                    .foregroundColor(.accentColor)

                TextField("Type live Morse message... (Enter to Send, ESC to Abort)", text: $liveInputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        sendLiveText()
                    }

                Button("SEND") {
                    sendLiveText()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(liveInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Recent Sent Messages
            if !keyer.sentHistory.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Recent:")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.secondary)

                        ForEach(keyer.sentHistory.prefix(6), id: \.self) { item in
                            Button {
                                liveInputText = item
                            } label: {
                                Text(item)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var currentMyCall: String {
        appState.activeStationProfile?.callsign ?? "EP2AES"
    }

    private var currentTargetCall: String {
        appState.quickLogDraft.callsign.isEmpty ? "W1AW" : appState.quickLogDraft.callsign
    }

    private var currentRST: String {
        appState.quickLogDraft.rstSent.isEmpty ? "599" : appState.quickLogDraft.rstSent
    }

    private var currentName: String {
        appState.quickLogDraft.name
    }

    private var currentQTH: String {
        appState.quickLogDraft.qth
    }

    private var currentSerial: Int {
        if let s = Int(appState.quickLogDraft.sentSerial), s > 0 {
            return s
        }
        return max(1, appState.qsoRecords.count + 1)
    }

    private var currentExchange: String {
        appState.quickLogDraft.receivedExchange.isEmpty ? "001" : appState.quickLogDraft.receivedExchange
    }

    private var currentBand: String {
        appState.quickLogDraft.band
    }

    private var currentFreq: String {
        appState.quickLogDraft.frequencyMHz
    }

    private func evaluateMacro(_ template: String) -> String {
        return keyer.expandMacro(
            template,
            myCall: currentMyCall,
            call: currentTargetCall,
            rst: currentRST,
            name: currentName,
            qth: currentQTH,
            serial: currentSerial,
            exch: currentExchange,
            band: currentBand,
            freq: currentFreq
        )
    }

    private func triggerMacro(_ macro: CWMacro) {
        keyer.send(
            text: macro.template,
            myCall: currentMyCall,
            call: appState.quickLogDraft.callsign,
            rst: currentRST,
            name: currentName,
            qth: currentQTH,
            serial: currentSerial,
            exch: currentExchange,
            band: currentBand,
            freq: currentFreq
        )
    }

    private func sendLiveText() {
        let trimmed = liveInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        keyer.send(
            text: trimmed,
            myCall: currentMyCall,
            call: appState.quickLogDraft.callsign,
            rst: currentRST,
            name: currentName,
            qth: currentQTH,
            serial: currentSerial,
            exch: currentExchange,
            band: currentBand,
            freq: currentFreq
        )

        liveInputText = ""
    }
}

// MARK: - Macro Card Component

private struct MacroCardView: View {
    let macro: CWMacro
    let evaluatedPreview: String
    let onTrigger: () -> Void
    let onEdit: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            onTrigger()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    // Function Key Badge
                    Text(macro.functionKeyTitle)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)

                    // Macro Title
                    Text(macro.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    // Edit button
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundColor(isHovered ? .accentColor : .secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Edit Macro \(macro.functionKeyTitle)")
                }

                // Dynamic Live Preview
                Text(evaluatedPreview)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isHovered ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Macro Editor Sheet

private struct MacroEditorSheet: View {
    let macro: CWMacro
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var labelText: String = ""
    @State private var templateText: String = ""

    init(macro: CWMacro, onSave: @escaping (String, String) -> Void) {
        self.macro = macro
        self.onSave = onSave
        _labelText = State(initialValue: macro.label)
        _templateText = State(initialValue: macro.template)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit \(macro.functionKeyTitle) Macro")
                    .font(.headline.bold())
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Button Label:")
                    .font(.caption.bold())
                TextField("Label (e.g. CQ TEST, 5NN TU)", text: $labelText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Morse Template:")
                    .font(.caption.bold())
                TextField("Template text with {TOKENS}", text: $templateText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            // Quick Token Inserters
            VStack(alignment: .leading, spacing: 4) {
                Text("Insert Token:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    ForEach(["{MYCALL}", "{CALL}", "{SERIAL}", "{EXCH}", "{RST}", "{NAME}", "{QTH}"], id: \.self) { token in
                        Button(token) {
                            templateText += (templateText.isEmpty ? "" : " ") + token
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .font(.system(size: 9.5, design: .monospaced))
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Save Macro") {
                    onSave(labelText, templateText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
