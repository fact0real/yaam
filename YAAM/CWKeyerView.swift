//
//  CWKeyerView.swift
//  YAAM
//
//  Interactive CW Keyer & Macro Console UI
//  F1-F8 macro buttons with hotkeys, WPM speed adjustment, live Morse text input,
//  sidetone pitch control, and real-time transmit queue monitoring.
//

import Combine
import SwiftUI

public struct CWKeyerView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var keyer = CWKeyerService.shared

    @State private var liveInputText: String = ""
    @State private var showMacroEditor: Bool = false
    @State private var selectedMacroIndex: Int = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Top Controls Bar
            HStack(spacing: 14) {
                // Keyer Mode
                Picker("Backend", selection: $keyer.transmissionMode) {
                    ForEach(CWTransmissionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(width: 170)

                Divider().frame(height: 20)

                // WPM Speed Controller
                HStack(spacing: 6) {
                    Text("SPEED:")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)

                    Button {
                        keyer.decreaseWPM()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)

                    Text("\(keyer.wpm) WPM")
                        .font(.headline.monospacedDigit().bold())
                        .frame(width: 65)

                    Button {
                        keyer.increaseWPM()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 20)

                // Sidetone Toggle
                Toggle("Sidetone (\(Int(keyer.sidetonePitchHz))Hz)", isOn: $keyer.sidetoneEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Spacer()

                // Emergency Stop / ESC Button
                if keyer.isTransmitting {
                    Button(role: .destructive) {
                        keyer.stop()
                    } label: {
                        Label("STOP (ESC)", systemImage: "stop.circle.fill")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)

            // Live Transmit Status Banner
            if keyer.isTransmitting {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text("TX ON AIR:")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                    Text(keyer.activeBufferText)
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(10)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            // F1 - F8 Macro Buttons Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(keyer.macros) { macro in
                    Button {
                        triggerMacro(macro)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(macro.label)
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                            Text(previewTemplate(macro.template))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(macro.id)")), modifiers: .command)
                }
            }

            // Freeform Live CW Text Input
            HStack(spacing: 8) {
                Image(systemName: "tuningfork")
                    .foregroundColor(.secondary)

                TextField("Type text to transmit over CW (Press Enter to Send)...", text: $liveInputText)
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
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }

    private func previewTemplate(_ template: String) -> String {
        return keyer.expandMacro(
            template,
            myCall: appState.activeStationProfile?.callsign ?? "EP2AES",
            call: appState.quickLogDraft.callsign.isEmpty ? "W1AW" : appState.quickLogDraft.callsign,
            rst: appState.quickLogDraft.rstSent.isEmpty ? "599" : appState.quickLogDraft.rstSent,
            name: appState.quickLogDraft.name,
            qth: appState.quickLogDraft.qth,
            serial: max(1, appState.qsoRecords.count + 1)
        )
    }

    private func triggerMacro(_ macro: CWMacro) {
        keyer.send(
            text: macro.template,
            myCall: appState.activeStationProfile?.callsign ?? "EP2AES",
            call: appState.quickLogDraft.callsign,
            rst: appState.quickLogDraft.rstSent.isEmpty ? "599" : appState.quickLogDraft.rstSent,
            name: appState.quickLogDraft.name,
            qth: appState.quickLogDraft.qth,
            serial: max(1, appState.qsoRecords.count + 1)
        )
    }

    private func sendLiveText() {
        let trimmed = liveInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        keyer.send(
            text: trimmed,
            myCall: appState.activeStationProfile?.callsign ?? "EP2AES",
            call: appState.quickLogDraft.callsign,
            rst: appState.quickLogDraft.rstSent.isEmpty ? "599" : appState.quickLogDraft.rstSent,
            name: appState.quickLogDraft.name,
            qth: appState.quickLogDraft.qth,
            serial: max(1, appState.qsoRecords.count + 1)
        )

        liveInputText = ""
    }
}
