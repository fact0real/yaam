//
//  DigitalQSOConfirmationSheet.swift
//  YAAM
//
//  The one confirmation of the Digital Suite, and its setting.
//

import SwiftUI

/// Shown before a Digital Suite QSO is saved: always for SSTV and with the "Always" setting, otherwise only when
/// something is missing. Nothing is saved or uploaded until Record QSO is pressed.
struct DigitalQSOConfirmationSheet: View {
    @ObservedObject var center: DigitalQSOConfirmationCenter
    @State private var draft: DigitalQSODraft

    init(center: DigitalQSOConfirmationCenter, draft: DigitalQSODraft) {
        self.center = center
        self._draft = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Record this \(draft.mode) QSO?")
                .font(.headline)

            Form {
                TextField("Callsign", text: $draft.callsign)
                TextField(draft.isSSTV ? "RSV sent" : "Report sent", text: $draft.reportSent)
                TextField(draft.isSSTV ? "RSV received" : "Report received", text: $draft.reportReceived)
                TextField("Frequency (MHz)", text: $draft.frequencyText)
                LabeledContent("Band", value: draft.band ?? "-")
            }

            Text(draft.radioFrequencyHz == nil
                 ? "No radio connected: type the frequency you worked on."
                 : "Frequency read from the radio.")
                .font(.caption2)
                .foregroundColor(draft.radioFrequencyHz == nil ? .orange : .secondary)
            if draft.isSSTV {
                Text("RSV: readability 1-5, signal 1-9, video 1-5.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Discard QSO", role: .cancel) {
                    center.discardPending()
                }
                .keyboardShortcut(.cancelAction)
                Button("Record QSO") {
                    center.recordPending(draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isComplete)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

/// The Digital Suite setting: when to ask before a QSO is saved.
struct DigitalQSOConfirmationModePicker: View {
    @AppStorage(DigitalQSOConfirmationMode.storageKey) private var setting: DigitalQSOConfirmationMode = .whenFrequencyMissing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker("Confirm QSO:", selection: $setting) {
                ForEach(DigitalQSOConfirmationMode.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("SSTV QSOs are always confirmed. With a radio connected, the frequency and band come from it.")
            Text(setting.tradeOffs)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 320, alignment: .leading)
        }
    }
}
