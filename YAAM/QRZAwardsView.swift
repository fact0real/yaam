//
//  QRZAwardsView.swift
//  YAAM
//

import SwiftUI

struct QRZAwardSummary: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let detail: String
    let percentComplete: Double
    let status: String
    let earned: Bool
    let progressAvailable: Bool
    let achievement: String
    let awardType: String
    let ribbonURL: String

    var remainingPercent: Double {
        max(0, 100 - percentComplete)
    }

    var progressText: String {
        progressAvailable ? "\(Int(percentComplete.rounded()))%" : "--"
    }
}

struct QRZAwardsFetchResult {
    let awards: [QRZAwardSummary]
    let message: String
}

struct QRZAwardsView: View {
    @EnvironmentObject var appState: AppState

    private var earnedAwards: [QRZAwardSummary] {
        appState.qrzAwardSummaries.filter(\.earned).sorted { $0.title < $1.title }
    }

    private var inProgressAwards: [QRZAwardSummary] {
        appState.qrzAwardSummaries
            .filter { !$0.earned }
            .sorted {
                if $0.progressAvailable != $1.progressAvailable {
                    return $0.progressAvailable && !$1.progressAvailable
                }
                return $0.percentComplete > $1.percentComplete
            }
    }

    private var averageProgress: Double {
        let analyzed = appState.qrzAwardSummaries.filter(\.progressAvailable)
        guard !analyzed.isEmpty else { return 0 }
        let total = analyzed.reduce(0) { $0 + $1.percentComplete }
        return total / Double(analyzed.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if appState.qrzAwardSummaries.isEmpty {
                    if appState.isFetchingQRZAwards {
                        loadingState
                    } else {
                        emptyState
                    }
                } else {
                    summaryStrip

                    if !earnedAwards.isEmpty {
                        awardSection(title: "Awarded", icon: "rosette", awards: earnedAwards)
                    }

                    if !inProgressAwards.isEmpty {
                        awardSection(title: "In Progress", icon: "chart.line.uptrend.xyaxis", awards: inProgressAwards)
                    }

                    if !appState.qrzAwardsStatus.isEmpty {
                        Label(appState.qrzAwardsStatus, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(18)
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            if appState.qrzAwardSummaries.isEmpty && appState.qrzAwardsStatus.isEmpty {
                appState.fetchQRZAwards()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.14))
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("QRZ Awards")
                    .font(.title2)
                    .bold()
                Text("Live achievement and progress from QRZ Logbook Awards")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if appState.isFetchingQRZAwards {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                appState.fetchQRZAwards()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isFetchingQRZAwards)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.62))
        .cornerRadius(8)
    }

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            awardMetric("Awarded", "\(earnedAwards.count)", "checkmark.seal.fill", .green)
            awardMetric(
                "Analyzed",
                "\(appState.qrzAwardSummaries.filter(\.progressAvailable).count)/\(appState.qrzAwardSummaries.count)",
                "square.grid.2x2.fill",
                .blue
            )
            awardMetric("Average", "\(Int(averageProgress.rounded()))%", "gauge.with.dots.needle.50percent", .purple)
            awardMetric("Closest", closestAwardText, "target", .orange)
        }
    }

    private var closestAwardText: String {
        guard let award = inProgressAwards
            .filter(\.progressAvailable)
            .max(by: { $0.percentComplete < $1.percentComplete }) else {
            return "Complete"
        }
        return "\(Int(award.remainingPercent.rounded()))% left"
    }

    private func awardMetric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(value)
                .font(.system(.title2, design: .rounded))
                .bold()
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.46))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.24), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.circle")
                .font(.system(size: 56))
                .foregroundColor(.orange.opacity(0.6))
            Text("No QRZ awards loaded yet")
                .font(.headline)
            Text(appState.qrzAwardsStatus.isEmpty ? "Use Refresh to sign in with your saved QRZ settings and inspect Logbook Awards." : appState.qrzAwardsStatus)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
            Button {
                appState.fetchQRZAwards()
            } label: {
                Label("Load QRZ Awards", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.34))
        .cornerRadius(8)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing QRZ awards")
                .font(.headline)
            Text("Loading achievements and calculating progress for every award...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.34))
        .cornerRadius(8)
    }

    private func awardSection(title: String, icon: String, awards: [QRZAwardSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(awards) { award in
                    QRZAwardCard(award: award)
                }
            }
        }
    }
}

struct QRZAwardCard: View {
    let award: QRZAwardSummary

    private var color: Color {
        if award.earned { return .green }
        if !award.progressAvailable { return .secondary }
        if award.percentComplete >= 75 { return .orange }
        if award.percentComplete >= 40 { return .blue }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if let url = URL(string: award.ribbonURL), !award.ribbonURL.isEmpty {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(color)
                        }
                    } else {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(color)
                    }
                }
                .frame(width: 88, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(award.title)
                        .font(.subheadline)
                        .bold()
                        .lineLimit(2)
                    Text(award.status)
                        .font(.caption)
                        .foregroundColor(color)
                        .bold()
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Progress")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(award.progressText)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Achievement")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(award.achievement)
                        .font(.caption)
                        .bold()
                        .lineLimit(2)
                }
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if award.progressAvailable {
                ProgressView(value: min(max(award.percentComplete, 0), 100), total: 100)
                    .tint(color)
            }

            Text(award.detail.isEmpty ? award.status : award.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)

            if !award.awardType.isEmpty {
                Text(award.awardType)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.48))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.24), lineWidth: 1))
    }
}
