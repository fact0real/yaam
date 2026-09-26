//
//  FieldOperationsWorkspaceView.swift
//  YAAM
//
//  Comprehensive POTA & SOTA Field Operations Workspace
//  Unifies Active Field Activation (Rapid Pileup Logger), Live Spots Radar,
//  Offline Park/Summit MapKit Directory, and Activities & Official Log Export.
//

import AppKit
import SwiftUI

public enum FieldOpsTab: String, CaseIterable, Identifiable {
    case activeSession = "Field Activation"
    case liveSpots = "Live Spots & P2P"
    case parkMap = "Park Explorer"
    case activities = "History & Export"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .activeSession: return "bolt.fill"
        case .liveSpots: return "antenna.radiowaves.left.and.right"
        case .parkMap: return "map.fill"
        case .activities: return "clock.arrow.circlepath"
        }
    }
}

public struct FieldOperationsWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var potaEngine = POTASOTAEngine.shared
    @State private var selectedTab: FieldOpsTab = .activeSession
    @State private var programFilter = "All"

    private var summaries: [PortableActivitySummary] { appState.portableActivitySummaries }
    private var filteredSummaries: [PortableActivitySummary] {
        programFilter == "All" ? summaries : summaries.filter { $0.program.rawValue == programFilter }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Workspace Top Navigation Bar
            workspaceHeaderBar

            Divider()

            // Tab Content
            switch selectedTab {
            case .activeSession:
                FieldPileupLoggerView()
            case .liveSpots:
                FieldSpotsRadarView()
            case .parkMap:
                FieldParkMapView()
            case .activities:
                activitiesHistoryTab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appState.refreshAwardProgress()
            if potaEngine.activeSession?.isActive == true {
                selectedTab = .activeSession
            }
        }
    }

    // MARK: - Workspace Top Navigation Bar
    private var workspaceHeaderBar: some View {
        HStack(spacing: 14) {
            // Title & Status
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 30, height: 30)

                    Image(systemName: "figure.hiking")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("POTA / SOTA Field Operations")
                        .font(.system(size: 12.5, weight: .black))

                    if let session = potaEngine.activeSession, session.isActive {
                        Text("\(session.myReference) · \(session.qsoCount)/\(session.targetGoal) QSOs")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    } else {
                        Text("Outdoor Tactical Companion")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Tab Picker
            Picker("", selection: $selectedTab) {
                ForEach(FieldOpsTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 460)

            Spacer()

            // Station Callsign Pill
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                Text(appState.activeStationProfile?.normalizedCallsign ?? appState.currentStationCallsign)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Tab 4: Activities History & Official Export
    private var activitiesHistoryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header & Metrics
                HStack(spacing: 12) {
                    OperationsMetric(title: "Activity Days", value: summaries.count, icon: "calendar", color: .blue)
                    OperationsMetric(title: "POTA Ready", value: summaries.filter { $0.program == .pota && $0.isActivationReady }.count, icon: "checkmark.circle.fill", color: .green)
                    OperationsMetric(title: "Portable QSOs", value: summaries.reduce(0) { $0 + $1.qsoCount }, icon: "antenna.radiowaves.left.and.right", color: .orange)
                }

                // Filter Picker
                Picker("Program", selection: $programFilter) {
                    Text("All Programs").tag("All")
                    ForEach(PortableProgram.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)

                // Summaries Grid
                if filteredSummaries.isEmpty {
                    ContentUnavailableView(
                        "No Portable Activities Found",
                        systemImage: "figure.hiking",
                        description: Text("Start an activation session or import standard portable ADIF records.")
                    )
                    .frame(minHeight: 260)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                        ForEach(filteredSummaries) { summary in
                            activitySummaryCard(summary: summary)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func activitySummaryCard(summary: PortableActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: summary.program.icon)
                    .foregroundStyle(.green)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.reference)
                        .font(.headline.monospaced())
                    Text(portableDate(summary.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if summary.program == .pota {
                    Label(
                        summary.isActivationReady ? "Qualified" : "\(max(0, 10 - summary.qsoCount)) needed",
                        systemImage: summary.isActivationReady ? "checkmark.circle.fill" : "clock"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(summary.isActivationReady ? .green : .orange)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.qsoCount)")
                        .font(.headline.monospacedDigit())
                    Text("QSOs").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.confirmedCount)")
                        .font(.headline.monospacedDigit())
                    Text("Confirmed").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.uniqueCallsigns)")
                        .font(.headline.monospacedDigit())
                    Text("Unique Calls").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(summary.bands.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button {
                    appState.exportPortableActivity(summary)
                } label: {
                    Label("Export ADIF", systemImage: "square.and.arrow.up")
                        .font(.caption.bold())
                }

                Spacer()

                let filename = FieldLogExporter.generatePOTAFilename(
                    callsign: appState.currentStationCallsign,
                    reference: summary.reference
                )
                Text(filename)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.2), lineWidth: 1))
    }

    private func portableDate(_ value: String) -> String {
        guard value.count == 8 else { return value }
        return "\(value.prefix(4))-\(value.dropFirst(4).prefix(2))-\(value.suffix(2)) UTC"
    }
}
