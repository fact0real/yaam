//
//  ContestESMControlView.swift
//  YAAM
//
//  Visual ESM (Enter Sends Message) Live HUD Ribbon & Contest Macro Controller
//  Displays real-time state machine transitions, next-action prompts, RUN vs S&P mode,
//  live Morse character streaming, and one-click function key overrides.
//

import AppKit
import SwiftUI

public struct ContestESMControlView: View {
    @ObservedObject private var esm = ContestESMEngine.shared
    @ObservedObject private var cw = CWKeyerService.shared

    @Binding var inputCall: String
    @Binding var inputSentExchange: String
    @Binding var inputRcvdExchange: String

    var onTriggerESM: () -> Void
    var onAbortWipe: () -> Void

    public init(
        inputCall: Binding<String>,
        inputSentExchange: Binding<String>,
        inputRcvdExchange: Binding<String>,
        onTriggerESM: @escaping () -> Void,
        onAbortWipe: @escaping () -> Void
    ) {
        self._inputCall = inputCall
        self._inputSentExchange = inputSentExchange
        self._inputRcvdExchange = inputRcvdExchange
        self.onTriggerESM = onTriggerESM
        self.onAbortWipe = onAbortWipe
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Top Bar: ESM Master Toggle + RUN/S&P Segment + Dynamic Action Indicator
            HStack(spacing: 12) {
                // ESM Active Pill
                HStack(spacing: 6) {
                    Toggle("ESM Mode", isOn: $esm.isESMEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                // Operator Role (RUN vs S&P)
                Picker("Role", selection: $esm.role) {
                    ForEach(ContestOperatorRole.allCases) { r in
                        Text(r.shortTitle).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .onChange(of: esm.role) { _, _ in
                    esm.evaluateState(callsign: inputCall, rcvdExchange: inputRcvdExchange)
                }

                // Dynamic Live Action Prompt Button
                Button {
                    onTriggerESM()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.left")
                            .font(.caption.bold())
                        Text("ENTER: \(esm.currentState.actionDescription)")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(esm.currentState.actionColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(esm.currentState.actionColor, lineWidth: 1.2))
                    .foregroundColor(esm.currentState.actionColor)
                }
                .buttonStyle(.plain)

                Spacer()

                // Emergency Abort / Wipe Button
                Button(role: .destructive) {
                    onAbortWipe()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                        Text("Abort (ESC)")
                    }
                    .font(.caption2.bold())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Real-Time Transmit HUD (Visible during transmission)
            if esm.isTransmitting || cw.isTransmitting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("TX:")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                    Text(esm.activeOutgoingText.isEmpty ? cw.activeBufferText : esm.activeOutgoingText)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Function Keys Quick Bar (F1...F8)
            HStack(spacing: 6) {
                macroButton("F1: CQ", macro: esm.f1CQ)
                macroButton("F2: Exch", macro: esm.f2Exch)
                macroButton("F3: TU", macro: esm.f3TU)
                macroButton("F4: MyCall", macro: esm.f4MyCall)
                macroButton("F5: His+TU", macro: esm.f5HisCallTU)
                macroButton("F6: Rpt", macro: esm.f6RepeatExch)
                macroButton("F7: ?", macro: esm.f7Question)
                macroButton("F8: AGN", macro: esm.f8AGN)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .onChange(of: inputCall) { _, newCall in
            esm.evaluateState(callsign: newCall, rcvdExchange: inputRcvdExchange)
        }
        .onChange(of: inputRcvdExchange) { _, newExch in
            esm.evaluateState(callsign: inputCall, rcvdExchange: newExch)
        }
    }

    private func macroButton(_ title: String, macro: String) -> some View {
        Button {
            esm.executeMacro(macro, call: inputCall, sentExch: inputSentExchange, rcvdExch: inputRcvdExchange)
        } label: {
            Text(title)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}
