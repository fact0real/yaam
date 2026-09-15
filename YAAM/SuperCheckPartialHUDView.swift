//
//  SuperCheckPartialHUDView.swift
//  YAAM
//
//  Interactive Super Check Partial (SCP) Live Autocomplete HUD
//  Displays real-time contest callsign predictions, DXCC country flags,
//  and Dupe / Multiplier status badges with 1-click autocomplete.
//

import Combine
import SwiftUI

struct SuperCheckPartialHUDView: View {
    @ObservedObject private var scp = SuperCheckPartialEngine.shared
    @Binding var targetCallsign: String
    var activeBand: String
    var activeMode: String
    var qsoRecords: [QSORecordModel]
    var onSelect: ((String) -> Void)?

    init(
        targetCallsign: Binding<String>,
        activeBand: String = "",
        activeMode: String = "CW",
        qsoRecords: [QSORecordModel] = [],
        onSelect: ((String) -> Void)? = nil
    ) {
        self._targetCallsign = targetCallsign
        self.activeBand = activeBand
        self.activeMode = activeMode
        self.qsoRecords = qsoRecords
        self.onSelect = onSelect
    }

    var body: some View {
        let matches = scp.findEnrichedMatches(
            for: targetCallsign,
            band: activeBand,
            mode: activeMode,
            qsoRecords: qsoRecords,
            maxResults: 8
        )

        if !matches.isEmpty && targetCallsign.trimmingCharacters(in: .whitespaces).count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                // Top Header with Super Check Partial Icon
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.blue)

                    Text("SUPER CHECK PARTIAL")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    if let exact = matches.first(where: { $0.isExact }) {
                        HStack(spacing: 3) {
                            Text(exact.country.flagEmoji)
                            Text("\(exact.country.entityName) (Zone \(exact.country.cqZone))")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Horizontally Scrollable Autocomplete Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(matches) { match in
                            Button {
                                commitCallsign(match.callsign)
                            } label: {
                                HStack(spacing: 5) {
                                    // Country Flag
                                    Text(match.country.flagEmoji)
                                        .font(.system(size: 11))

                                    // Callsign with Monospace Typography
                                    Text(match.callsign)
                                        .font(.system(size: 11, weight: match.isExact ? .bold : .semibold, design: .monospaced))
                                        .foregroundColor(match.status == .duplicate ? .secondary : .primary)

                                    // Status Badge (MULT, NEW, DUPE)
                                    statusBadge(for: match)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(pillBackground(for: match))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(pillBorder(for: match), lineWidth: match.isExact ? 1.5 : 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Click to select \(match.callsign) (\(match.country.entityName))")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .transition(.opacity)
        }
    }

    private func commitCallsign(_ call: String) {
        targetCallsign = call
        onSelect?(call)
    }

    private func statusBadge(for match: SuperCheckPartialMatch) -> some View {
        Group {
            switch match.status {
            case .newMultiplier:
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 7))
                    Text("MULT")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange)
                .cornerRadius(3)

            case .validNewCall:
                Text("NEW")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.green)
                    .cornerRadius(3)

            case .duplicate:
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 7))
                    Text(match.workedCount > 1 ? "DUPE (\(match.workedCount))" : "DUPE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.18))
                .cornerRadius(3)
            }
        }
    }

    private func pillBackground(for match: SuperCheckPartialMatch) -> Color {
        if match.isExact {
            return match.status == .duplicate ? Color.secondary.opacity(0.15) : Color.green.opacity(0.15)
        } else if match.status == .newMultiplier {
            return Color.orange.opacity(0.12)
        } else {
            return Color(NSColor.controlBackgroundColor)
        }
    }

    private func pillBorder(for match: SuperCheckPartialMatch) -> Color {
        if match.isExact {
            return match.status == .duplicate ? Color.secondary.opacity(0.4) : Color.green.opacity(0.6)
        } else if match.status == .newMultiplier {
            return Color.orange.opacity(0.4)
        } else {
            return Color.primary.opacity(0.12)
        }
    }
}
