//
//  ContestCalendarAndPropagationView.swift
//  YAAM
//

import AppKit
import SwiftUI
import UserNotifications

typealias ContestCalendarAndPropagationPanel = ContestCalendarPanel

struct ContestCalendarPanel: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("contestPreferredModes") private var contestPreferredModes = "FT8, FT4"
    @AppStorage("contestInterestKeywords") private var contestInterestKeywords = "digital, FT8, FT4"
    @AppStorage("contestInterestNotifications") private var contestInterestNotifications = false
    @AppStorage("dxpeditionSpotNotifications") private var dxpeditionSpotNotifications = false
    @State private var showContestPreferences = false
    @State private var showAllContests = false

    private let calendarURL = URL(string: "https://www.contestcalendar.com/fivewkcal.php")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: "Contest Calendar",
                    subtitle: "Contest planning, WA7BNM 5-week schedule, and DXpedition opportunities",
                    icon: "calendar",
                    color: .blue
                )

                contestCalendar
                dxpeditionWatch
            }
            .padding(22)
        }
        .onAppear {
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

                if !appState.contestCalendarEntries.isEmpty {
                    Text("(\(prioritizedContests.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if prioritizedContests.count > 12 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllContests.toggle()
                        }
                    } label: {
                        Text(showAllContests ? "Show Top 12" : "Show All (\(prioritizedContests.count))")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

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
                let visibleContests = showAllContests ? prioritizedContests : Array(prioritizedContests.prefix(12))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 12)], spacing: 12) {
                    ForEach(visibleContests) { item in
                        contestCard(item)
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

    private func contestCard(_ item: ContestCalendarEntry) -> some View {
        let isPreferred = isPreferredContest(item)
        let isME = item.isMiddleEastRelevant
        let accentColor: Color = isPreferred ? .orange : (isME ? .green : .blue)

        return VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header (Title + Icon + External Link)
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.16))
                    Image(systemName: isPreferred ? "star.fill" : (isME ? "location.north.line.fill" : "flag.checkered"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 24, height: 24)

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(item.title)

                if let url = URL(string: item.sourceURL), !item.sourceURL.isEmpty {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open official contest rules / announcement")
                }
            }
            .frame(height: 38, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // MARK: - Time Window (Pill)
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(item.utcWindow)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .separatorColor).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .help(item.utcWindow)

            // MARK: - Badges & Tags Row
            HStack(spacing: 6) {
                if isPreferred {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                        Text("Preferred")
                            .font(.caption2.bold())
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(5)
                }

                if isME {
                    HStack(spacing: 3) {
                        Image(systemName: "globe.asia.australia.fill")
                            .font(.system(size: 9))
                        Text("Middle East")
                            .font(.caption2.bold())
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.green.opacity(0.15))
                    .foregroundColor(.green)
                    .cornerRadius(5)
                }

                if !isPreferred && !isME {
                    Text(item.geographicFocus.isEmpty ? "Worldwide" : item.geographicFocus)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color(nsColor: .separatorColor).opacity(0.1))
                        .cornerRadius(5)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            Spacer(minLength: 4)

            // MARK: - Card Footer (Modes & Bands)
            HStack(spacing: 6) {
                if !item.modes.isEmpty && item.modes != "Not specified" {
                    Text(item.modes)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.12))
                        .foregroundColor(accentColor)
                        .cornerRadius(4)
                        .lineLimit(1)
                }

                if !item.bands.isEmpty && item.bands != "Not specified" {
                    Text(item.bands)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if !item.operatingSummary.isEmpty {
                    Text(item.operatingSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        }
        .frame(height: 164)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(isPreferred ? 0.55 : (isME ? 0.4 : 0.2)), lineWidth: isPreferred ? 1.4 : 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
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
        .frame(
            minWidth: 520,
            idealWidth: 620,
            maxWidth: .infinity,
            minHeight: 330,
            idealHeight: 420,
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 520, minHeight: 330)
    }
}
