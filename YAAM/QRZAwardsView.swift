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
                lotwAwardProgress

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

    private var lotwAwardProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("LoTW Award Progress", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                Spacer()
                Button {
                    appState.downloadLoTWAndQRZConfirmations()
                } label: {
                    Label("Sync LoTW", systemImage: "arrow.clockwise.icloud")
                }
                .disabled(appState.isSyncingAPI || appState.isProcessingQSLQueue)
            }

            HStack(spacing: 10) {
                lotwMetric("Confirmed QSOs", lotwConfirmedRecords.count.formatted(), "q.circle.fill", .green)
                lotwMetric("DXCC entities", "\(lotwDXCCCount)/100", "globe.americas.fill", .blue)
                lotwMetric("US states", "\(lotwStateCount)/50", "map.fill", .purple)
                lotwMetric("6m grids", "\(lotwSixMeterGridCount)/100", "square.grid.3x3.fill", .orange)
            }

            Text("LoTW does not expose every award account page through a simple public awards API here, so YAAM calculates practical DXCC/WAS/VUCC-style progress from LoTW-confirmed records already merged into the active station log.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.56))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.22)))
    }

    private var lotwConfirmedRecords: [QSORecordModel] {
        appState.qsoRecords.filter { record in
            ["Y", "V", "C", "CONFIRMED"].contains(record["LOTW_QSL_RCVD"].uppercased())
        }
    }

    private var lotwDXCCCount: Int {
        Set(lotwConfirmedRecords.map { $0["DXCC"] }.filter { !$0.isEmpty }).count
    }

    private var lotwStateCount: Int {
        Set(lotwConfirmedRecords.map { $0["STATE"].uppercased() }.filter { !$0.isEmpty }).count
    }

    private var lotwSixMeterGridCount: Int {
        Set(lotwConfirmedRecords.filter { $0["BAND"].lowercased() == "6m" }.map { ($0["GRIDSQUARE"].isEmpty ? $0["GRID"] : $0["GRIDSQUARE"]).uppercased() }.filter { !$0.isEmpty }).count
    }

    private func lotwMetric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
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

    @Environment(\.colorScheme) private var colorScheme

    private var normalizedProgress: Double {
        min(max(award.percentComplete, 0), 100)
    }

    private var isComplete: Bool {
        award.earned || (award.progressAvailable && normalizedProgress >= 100)
    }

    private var color: Color {
        if isComplete { return .green }
        if !award.progressAvailable { return .secondary }

        let fraction = normalizedProgress / 100
        let hue = 0.015 + (0.315 * pow(fraction, 1.65))
        let brightness = colorScheme == .dark ? 0.96 : 0.78
        return Color(hue: hue, saturation: 0.86, brightness: brightness)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                AwardContinentIcon(award: award, tint: color)
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

                if isComplete {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.16))
                            .frame(width: 40, height: 40)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 31, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .accessibilityLabel("Completed")
                    .help("Completed")
                }
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
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(color.opacity(0.15))
                        Capsule()
                            .fill(color)
                            .frame(width: geometry.size.width * normalizedProgress / 100)
                    }
                }
                .frame(height: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Award progress")
                .accessibilityValue("\(Int(normalizedProgress.rounded())) percent")
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
        .background(
            ZStack {
                Color(NSColor.controlBackgroundColor).opacity(0.48)
                if award.progressAvailable {
                    color.opacity(isComplete ? 0.035 : 0.025)
                }
            }
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(isComplete ? 0.48 : 0.34), lineWidth: isComplete ? 1.4 : 1)
        )
    }
}

private struct AwardContinentIcon: View {
    let award: QRZAwardSummary
    let tint: Color

    private var signature: (symbol: String, title: String, colors: [Color]) {
        let text = "\(award.title) \(award.detail) \(award.awardType)".uppercased()
        if text.contains("AFRICA") || text.contains("AF") {
            return ("globe.europe.africa.fill", "AF", [.orange, .green])
        }
        if text.contains("ASIA") || text.contains("AS") {
            return ("globe.central.south.asia.fill", "AS", [.red, .yellow])
        }
        if text.contains("EUROPE") || text.contains("EU") {
            return ("globe.europe.africa.fill", "EU", [.blue, .indigo])
        }
        if text.contains("NORTH AMERICA") || text.contains("NA") {
            return ("globe.americas.fill", "NA", [.blue, .green])
        }
        if text.contains("SOUTH AMERICA") || text.contains("SA") {
            return ("globe.americas.fill", "SA", [.green, .yellow])
        }
        if text.contains("OCEANIA") || text.contains("OC") {
            return ("globe.asia.australia.fill", "OC", [.cyan, .blue])
        }
        if text.contains("ANTARCTICA") || text.contains("AN") {
            return ("snowflake", "AN", [.cyan, .white])
        }
        return ("trophy.fill", "DX", [tint, .yellow])
    }

    var body: some View {
        let item = signature
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: item.colors.map { $0.opacity(0.82) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: item.symbol)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .offset(x: -15)
            Text(item.title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .offset(x: 22)
        }
        .accessibilityLabel("\(item.title) award icon")
    }
}
