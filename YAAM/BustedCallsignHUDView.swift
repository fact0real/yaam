//
//  BustedCallsignHUDView.swift
//  YAAM
//
//  Intelligent Busted Callsign Warning & Instant Correction HUD
//  ("کارت هوشمند هشدار و تصحیح کال‌ساین‌های اشتباه")
//  Renders real-time visual alerts for Voice (Phone) and CW (Morse) miscopies,
//  explaining the acoustic/telegraphic error and offering 1-click replacement.
//

import AppKit
import Combine
import SwiftUI

struct BustedCallsignHUDView: View {
    @ObservedObject private var engine = BustedCallsignEngine.shared
    @Binding var targetCallsign: String
    var activeMode: String
    var activeBand: String
    var logRecords: [QSORecordModel]
    var onSelect: ((String) -> Void)?

    @State private var isDismissed: Bool = false
    @State private var lastEvaluatedCall: String = ""

    init(
        targetCallsign: Binding<String>,
        activeMode: String = "CW",
        activeBand: String = "",
        logRecords: [QSORecordModel] = [],
        onSelect: ((String) -> Void)? = nil
    ) {
        self._targetCallsign = targetCallsign
        self.activeMode = activeMode
        self.activeBand = activeBand
        self.logRecords = logRecords
        self.onSelect = onSelect
    }

    private var currentSuggestion: BustedCallsignSuggestion? {
        guard !isDismissed else { return nil }
        let clean = targetCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 3 else { return nil }

        return engine.evaluate(
            callsign: clean,
            mode: activeMode,
            band: activeBand,
            logRecords: logRecords
        )
    }

    private var isExactVerified: Bool {
        let clean = targetCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 3 else { return false }
        return engine.isVerifiedCallsign(clean)
    }

    var body: some View {
        let clean = targetCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        Group {
            if let suggestion = currentSuggestion {
                bustedCallAlertCard(suggestion)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if isExactVerified && clean.count >= 4 {
                verifiedStationIndicator(call: clean)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentSuggestion != nil)
        .onChange(of: targetCallsign) { _, newCall in
            let cleanNew = newCall.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if cleanNew != lastEvaluatedCall {
                lastEvaluatedCall = cleanNew
                isDismissed = false
            }
        }
    }

    // MARK: - 1. Busted Call Alert Card (Glowing Amber / Gold)
    private func bustedCallAlertCard(_ suggestion: BustedCallsignSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row: Warning Icon, Mode Badge & Dismiss Button
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.orange)

                Text("SUSPECTED BUSTED CALLSIGN")
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.orange)

                // Operating Mode Badge
                HStack(spacing: 3) {
                    Image(systemName: suggestion.modeCategory.icon)
                        .font(.system(size: 8.5))
                    Text(suggestion.modeCategory.rawValue)
                        .font(.system(size: 8.5, weight: .bold))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(suggestion.modeCategory.badgeColor.opacity(0.18), in: Capsule())
                .foregroundStyle(suggestion.modeCategory.badgeColor)

                Spacer()

                // Confidence Badge
                HStack(spacing: 3) {
                    Text("\(suggestion.confidencePercentage)% Match")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(suggestion.confidenceColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(suggestion.confidenceColor.opacity(0.15), in: Capsule())

                // Dismiss Button
                Button {
                    withAnimation {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss warning and keep '\(suggestion.originalCall)'")
            }

            // Diagnostic Explanation Line
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: suggestion.errorType.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)

                Text(suggestion.explanation)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Divider().opacity(0.4)

            // Action Row: Suggestion Pill & Apply Button
            HStack(spacing: 8) {
                // Correct Callsign Display
                HStack(spacing: 5) {
                    Text(suggestion.country.flagEmoji)
                        .font(.system(size: 13))

                    Text(suggestion.suggestedCall)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.primary)

                    Text(suggestion.country.entityName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Source Badges (SCP, LoTW, Worked)
                HStack(spacing: 3) {
                    ForEach(suggestion.verifiedSources) { src in
                        Text(src.shortTag)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(src.tagColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(src.tagColor)
                    }
                    if suggestion.workedCount > 0 {
                        Text("\(suggestion.workedCount)x")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(Color.orange)
                    }
                }

                // 1-Click Replace Button
                Button {
                    applyCorrection(suggestion.suggestedCall)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Apply \(suggestion.suggestedCall)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
                .help("Click to replace '\(suggestion.originalCall)' with verified call '\(suggestion.suggestedCall)'")
            }
        }
        .padding(10)
        .background(
            Color.orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.45), lineWidth: 1.2)
        )
    }

    // MARK: - 2. Verified Station Indicator (Subtle Green)
    private func verifiedStationIndicator(call: String) -> some View {
        let dxcc = DXCCDatabase.resolve(callsign: call)

        return HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.green)

            Text("VERIFIED ACTIVE STATION:")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.green)

            Text(dxcc.flagEmoji)
                .font(.system(size: 10))

            Text("\(call) — \(dxcc.entityName) (Zone \(dxcc.cqZone))")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }

    private func applyCorrection(_ corrected: String) {
        targetCallsign = corrected
        onSelect?(corrected)
        withAnimation {
            isDismissed = true
        }
    }
}
