//
//  DigitalMasterStationView.swift
//  YAAM
//
//  Unified Master Workstation for the Entire YAAM Digital Modes Suite
//  Provides one-click switching between RTTY/PSK, Hellschreiber, Olivia MFSK, JS8Call, and SSTV Studio.
//

import AppKit
import SwiftUI

public enum DigitalSuiteSection: String, CaseIterable, Identifiable, Sendable {
    case rttyPSK = "RTTY & PSK"
    case hellschreiber = "Feld Hell"
    case oliviaMFSK = "Olivia MFSK"
    case js8Station = "JS8 Station"
    case sstvStudio = "SSTV Studio"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .rttyPSK: return "teletype"
        case .hellschreiber: return "doc.plaintext.fill"
        case .oliviaMFSK: return "music.note.list"
        case .js8Station: return "bubble.left.and.bubble.right.fill"
        case .sstvStudio: return "tv.fill"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .rttyPSK: return .green
        case .hellschreiber: return .orange
        case .oliviaMFSK: return .cyan
        case .js8Station: return .purple
        case .sstvStudio: return .red
        }
    }
}

public struct DigitalMasterStationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var activeSection: DigitalSuiteSection = .rttyPSK

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Master Digital Mode Switcher Ribbon
            modeSwitcherBar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.65))

            Divider()

            // Active Mode Workstation View
            switch activeSection {
            case .rttyPSK:
                DigitalModemStationView(engine: appState.digitalModemEngine)
            case .hellschreiber:
                HellschreiberView(engine: HellschreiberEngine.shared)
            case .oliviaMFSK:
                OliviaMFSKView(engine: OliviaMFSKEngine.shared)
            case .js8Station:
                JS8StationView(engine: JS8Engine.shared)
            case .sstvStudio:
                SSTVStudioView(engine: SSTVEngine.shared)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            wireLoggingCallbacks()
        }
    }

    private var modeSwitcherBar: some View {
        HStack(spacing: 8) {
            Text("DIGITAL SUITE:")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(DigitalSuiteSection.allCases) { sec in
                    Button {
                        activeSection = sec
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: sec.iconName)
                                .font(.system(size: 10.5))
                            Text(sec.rawValue)
                                .font(.system(size: 11, weight: activeSection == sec ? .bold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            activeSection == sec
                            ? sec.badgeColor.opacity(0.2)
                            : Color.clear
                        )
                        .foregroundColor(activeSection == sec ? sec.badgeColor : .primary)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(activeSection == sec ? sec.badgeColor.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Station Callsign Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text(TransmitIdentity.usableCallsign(appState.currentStationCallsign) ?? TransmitIdentity.callsignNotSetLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(5)
        }
    }

    private func wireLoggingCallbacks() {
        let handler: (_ call: String, _ mode: String, _ sent: String, _ rcvd: String, _ freq: UInt64, _ band: String) -> Void = { [weak appState] call, mode, sent, rcvd, freq, band in
            appState?.logDigitalModemQSO(call: call, mode: mode, sentRST: sent, rcvdRST: rcvd, freqHz: freq, band: band)
        }

        HellschreiberEngine.shared.logQSOHandler = handler
        OliviaMFSKEngine.shared.logQSOHandler = handler
        JS8Engine.shared.logQSOHandler = handler
        SSTVEngine.shared.logQSOHandler = handler
    }
}
