//
//  ContestCalendarAndPropagationView.swift
//  YAAM
//

import AppKit
import SwiftUI

struct ContestCalendarAndPropagationPanel: View {
    @EnvironmentObject private var appState: AppState

    private let calendarURL = URL(string: "https://www.contestcalendar.com/fivewkcal.php")!
    private let pskReporterURL = URL(string: "https://pskreporter.info/pskmap.html")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Contest Calendar & 6m Watch",
                    subtitle: "Contest planning, PSK Reporter reception evidence, and Magic Band opening alerts",
                    icon: "calendar.badge.clock",
                    color: .blue
                )

                contestCalendar
                sixMeterAlert
                signalReporter
                sixMeterEvidence
                propagationContext
            }
            .padding(22)
        }
        .onAppear {
            appState.fetchPropagationSnapshot()
            appState.fetchPSKReporterSignals()
            appState.fetchContestCalendar()
        }
    }

    private var contestCalendar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Upcoming contests", systemImage: "flag.checkered")
                    .font(.headline)
                Spacer()
                Button {
                    appState.fetchContestCalendar(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh contest calendar")
                .disabled(appState.isFetchingContestCalendar)
                Link(destination: calendarURL) {
                    Label("WA7BNM 5-week calendar", systemImage: "arrow.up.right.square")
                }
            }

            if appState.contestCalendarEntries.isEmpty {
                ContentUnavailableView(
                    "Contest calendar unavailable",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Open the official WA7BNM calendar or refresh when your connection is available.")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                    ForEach(Array(appState.contestCalendarEntries.prefix(12))) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: item.isMiddleEastRelevant ? "location.north.line.fill" : "flag.checkered")
                                .foregroundStyle(item.isMiddleEastRelevant ? .green : .blue)
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Spacer()
                        }
                        Text(item.utcWindow)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if item.isMiddleEastRelevant {
                            Text("Middle East relevant")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Text(item.operatingSummary.isEmpty ? item.geographicFocus : item.operatingSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke((item.isMiddleEastRelevant ? Color.green : Color.blue).opacity(0.28)))
                    }
                }
            }

            HStack(spacing: 6) {
                if appState.isFetchingContestCalendar {
                    ProgressView().controlSize(.small)
                }
                Text(appState.contestCalendarStatus)
                if let updated = appState.contestCalendarLastUpdated {
                    Text("· Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                }
            }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contestOperationsBand(color: .blue)
    }

    private var sixMeterAlert: some View {
        let assessment = appState.sixMeterAssessment
        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(assessment.color.opacity(0.18))
                Image(systemName: assessment.icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(assessment.color)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(assessment.title)
                    .font(.title3.weight(.bold))
                Text(assessment.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                appState.fetchPSKReporterSignals()
                appState.fetchPropagationSnapshot()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isFetchingPSKReporter || appState.isFetchingPropagation)
        }
        .padding(16)
        .background(assessment.color.opacity(assessment.isOpen ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(assessment.color.opacity(assessment.isOpen ? 0.55 : 0.24), lineWidth: assessment.isOpen ? 1.6 : 1))
    }

    private var signalReporter: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live PSK Reporter", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Link(destination: pskReporterURL) {
                    Label("Open map", systemImage: "map")
                }
            }

            HStack(spacing: 10) {
                PropagationMetric(title: "Reports", value: appState.pskReporterSignals.count.formatted(), icon: "antenna.radiowaves.left.and.right", color: .green)
                PropagationMetric(title: "6m reports", value: appState.sixMeterSignalCount.formatted(), icon: "waveform.path.ecg", color: .orange)
                PropagationMetric(title: "Middle East", value: appState.middleEastSixMeterSignalCount.formatted(), icon: "location.north.circle", color: .blue)
                PropagationMetric(title: "Best SNR", value: appState.bestSixMeterSNRText, icon: "gauge.high", color: .purple)
            }

            if appState.isFetchingPSKReporter {
                ProgressView("Loading PSK Reporter reports...")
                    .controlSize(.small)
            } else if appState.pskReporterSignals.isEmpty {
                ContentUnavailableView("No reports loaded", systemImage: "waveform.slash", description: Text(appState.pskReporterStatus.isEmpty ? "Refresh to query recent reception reports for your callsign." : appState.pskReporterStatus))
                    .frame(minHeight: 140)
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.pskReporterSignals.prefix(12)) { spot in
                        HStack(spacing: 10) {
                            Image(systemName: spot.isSixMeters ? "6.circle.fill" : "circle")
                                .foregroundStyle(spot.isSixMeters ? .orange : .secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Heard by \(spot.receiverCallsign)")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(spot.bandLabel) · \(spot.mode) · \(spot.receiverLocator.isEmpty ? "locator unknown" : spot.receiverLocator)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(spot.snrText)
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(spot.snrColor)
                            Text(spot.ageText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }

            if !appState.pskReporterStatus.isEmpty {
                Text(appState.pskReporterStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contestOperationsBand(color: .green)
    }

    private var sixMeterEvidence: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("6m Middle East evidence", systemImage: "scope")
                .font(.headline)

            Text(appState.sixMeterAssessment.evidence)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(["50000000-54000000", "50000000-50500000", "50280000-50350000"], id: \.self) { range in
                    Button(range) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(range, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .help("Copy PSK Reporter frange value")
                }
            }
        }
        .contestOperationsBand(color: .orange)
    }

    private var propagationContext: some View {
        let snapshot = appState.propagationSnapshot
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Solar and VHF context", systemImage: "sun.max.fill")
                    .font(.headline)
                Spacer()
                Text(snapshot.updatedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Not updated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                PropagationMetric(title: "SFI", value: snapshot.solarFlux, icon: "sun.max", color: .yellow)
                PropagationMetric(title: "K", value: snapshot.kIndex, icon: "k.circle", color: .orange)
                PropagationMetric(title: "A", value: snapshot.aIndex, icon: "a.circle", color: .red)
                PropagationMetric(title: "E-skip EU", value: snapshot.vhfConditions["E-Skip|Europe 6m"] ?? snapshot.vhfConditions["E-Skip|Europe"] ?? "-", icon: "sparkles", color: .blue)
            }
        }
        .contestOperationsBand(color: .yellow)
    }
}

private func sectionHeader(title: String, subtitle: String, icon: String, color: Color) -> some View {
    HStack(spacing: 14) {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.14))
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
        }
        .frame(width: 46, height: 46)

        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
    }
    .padding(14)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
}

private extension View {
    func contestOperationsBand(color: Color) -> some View {
        self
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2)))
    }
}

private struct PropagationMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}
