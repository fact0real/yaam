//
//  ContestCalendarAndPropagationView.swift
//  YAAM
//

import AppKit
import SwiftUI
import UserNotifications

struct ContestCalendarAndPropagationPanel: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("contestPreferredModes") private var contestPreferredModes = "FT8, FT4"
    @AppStorage("contestInterestKeywords") private var contestInterestKeywords = "digital, FT8, FT4"
    @AppStorage("contestInterestNotifications") private var contestInterestNotifications = false
    @AppStorage("dxpeditionSpotNotifications") private var dxpeditionSpotNotifications = false
    @State private var showContestPreferences = false

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
                dxpeditionWatch
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
            appState.fetchDXpeditions()
        }
        .onChange(of: appState.dxClusterClient.spots.first?.id) { _, _ in
            appState.scheduleDXpeditionOpportunityNotifications()
        }
        .sheet(isPresented: $showContestPreferences) {
            ContestInterestSettingsView(
                modes: $contestPreferredModes,
                keywords: $contestInterestKeywords,
                notificationsEnabled: $contestInterestNotifications,
                dxpeditionNotificationsEnabled: $dxpeditionSpotNotifications
            )
        }
    }

    private var dxpeditionWatch: some View {
        let workIndex = appState.workIndex()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("DXpedition watch", systemImage: "binoculars.fill")
                    .font(.headline)
                Spacer()
                Button {
                    appState.fetchDXpeditions(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh DXpeditions")
                .disabled(appState.isFetchingDXpeditions)
            }

            if appState.dxpeditionEntries.isEmpty {
                ContentUnavailableView("DXpedition list unavailable", systemImage: "binoculars", description: Text(appState.dxpeditionStatus))
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                let visibleEntries = Array(appState.dxpeditionEntries.prefix(10))
                VStack(spacing: 0) {
                    ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                        dxpeditionRow(entry, workIndex: workIndex)
                        if index < visibleEntries.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            }

            Text(appState.dxpeditionStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contestOperationsBand(color: .purple)
    }

    private func dxpeditionRow(_ entry: DXpeditionEntry, workIndex: LogWorkIndex) -> some View {
        let spot = appState.dxClusterClient.spots.first { $0.callsign.uppercased() == entry.callsign.uppercased() }
        let isWorked = spot.map { workIndex.status(for: entry.callsign, band: $0.band) == .worked } ?? false

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: spot == nil ? (entry.isActive ? "clock.badge.checkmark" : "calendar") : "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(spot == nil ? (entry.isActive ? Color.orange : Color.gray) : Color.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(entry.callsign)
                        .font(.headline.monospaced())
                    Text(entry.entity)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(entry.sourceSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.11), in: RoundedRectangle(cornerRadius: 5))
                    if let sourceURL = entry.primarySourceURL {
                        Link(destination: sourceURL) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .help("Open source announcement")
                    }
                }

                HStack(spacing: 8) {
                    Text(entry.scheduleText)
                    if let spot {
                        Text("ON AIR · \(spot.band) · \(String(format: "%.3f", spot.frequencyMHz)) MHz")
                            .foregroundStyle(.green)
                        Text(isWorked ? "Worked on this band" : "New opportunity")
                            .foregroundStyle(isWorked ? Color.gray : Color.blue)
                    } else {
                        Text(entry.isActive ? "Within announced window" : "Planned")
                            .foregroundStyle(entry.isActive ? .orange : .secondary)
                    }
                }
                .font(.caption.monospaced())

                if !entry.details.isEmpty {
                    Text(entry.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 10)
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
                Button {
                    showContestPreferences = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .help("Contest interests")
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
                    ForEach(Array(prioritizedContests.prefix(12))) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: isPreferredContest(item) ? "star.circle.fill" : (item.isMiddleEastRelevant ? "location.north.line.fill" : "flag.checkered"))
                                .foregroundStyle(isPreferredContest(item) ? .orange : (item.isMiddleEastRelevant ? .green : .blue))
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
                        if isPreferredContest(item) {
                            Label("Matches your operating interests", systemImage: "checkmark.seal.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        Text(item.operatingSummary.isEmpty ? item.geographicFocus : item.operatingSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke((isPreferredContest(item) ? Color.orange : (item.isMiddleEastRelevant ? Color.green : Color.blue)).opacity(0.42)))
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

    private var preferredTokens: [String] {
        (contestPreferredModes + "," + contestInterestKeywords)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
    }

    private var prioritizedContests: [ContestCalendarEntry] {
        appState.contestCalendarEntries.sorted { lhs, rhs in
            let lhsScore = contestInterestScore(lhs)
            let rhsScore = contestInterestScore(rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.utcWindow < rhs.utcWindow
        }
    }

    private func contestInterestScore(_ item: ContestCalendarEntry) -> Int {
        let context = [item.title, item.operatingSummary, item.geographicFocus, item.modes]
            .joined(separator: " ")
            .uppercased()
        let matches = preferredTokens.filter { context.contains($0) }.count
        return matches * 4 + (item.isMiddleEastRelevant ? 1 : 0)
    }

    private func isPreferredContest(_ item: ContestCalendarEntry) -> Bool {
        contestInterestScore(item) >= 4
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

private struct ContestInterestSettingsView: View {
    @Binding var modes: String
    @Binding var keywords: String
    @Binding var notificationsEnabled: Bool
    @Binding var dxpeditionNotificationsEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Contest interests", systemImage: "flag.checkered.2.crossed")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            Text("Matching contests are placed first in the calendar and marked with a star.")
                .foregroundStyle(.secondary)

            TextField("Preferred modes, comma separated", text: $modes)
                .textFieldStyle(.roundedBorder)
            TextField("Interest keywords, comma separated", text: $keywords)
                .textFieldStyle(.roundedBorder)

            Toggle("Notify me when a newly listed contest matches", isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, enabled in
                    guard enabled else { return }
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }

            Toggle("Notify me when a watched DXpedition is spotted", isOn: $dxpeditionNotificationsEnabled)
                .onChange(of: dxpeditionNotificationsEnabled) { _, enabled in
                    guard enabled else { return }
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }

            Text("Examples: FT8, FT4, RTTY, CW, SSB, digital, VHF, 6m.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 520, height: 330)
    }
}
