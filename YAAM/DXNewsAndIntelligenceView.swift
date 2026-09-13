//
//  DXNewsAndIntelligenceView.swift
//  YAAM
//
//  Created for YAAM DX News & Expeditions Intelligence Workspace.
//

import AppKit
import SwiftUI

struct DXNewsAndIntelligenceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL

    @State private var selectedSection: Int = 0 // 0: DXpeditions, 1: News Feed, 2: Weekly Bulletins
    @State private var searchText: String = ""
    @State private var expeditionFilter: ExpeditionFilter = .all
    @State private var newsCategoryFilter: String = "All"
    @State private var selectedBulletinID: String? = nil
    @State private var selectedArticleForDetail: DXNewsArticle? = nil
    @State private var bulletinSearchText: String = ""

    enum ExpeditionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case activeNow = "Active Now"
        case upcoming = "Upcoming"
        case needed = "Unworked Need"
        case digital = "FT8 / Digital"
        case sixMeters = "6m Band"
        case iota = "IOTA Islands"
        case ng3k = "NG3K ADXO"
        case dxWorld = "DX-World"
        case fourTwentyFive = "425 DX"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .activeNow: return "dot.radiowaves.left.and.right"
            case .upcoming: return "calendar"
            case .needed: return "target"
            case .digital: return "waveform"
            case .sixMeters: return "bolt.fill"
            case .iota: return "water.waves"
            case .ng3k: return "tablecells.fill"
            case .dxWorld: return "globe.americas.fill"
            case .fourTwentyFive: return "newspaper.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Workspace Header
            headerBar

            Divider()

            // Main Section Switcher
            Picker("Workspace View", selection: $selectedSection) {
                Label("DXpeditions (\(filteredExpeditions.count))", systemImage: "binoculars.fill").tag(0)
                Label("Live DX News (\(filteredArticles.count))", systemImage: "newspaper.fill").tag(1)
                Label("Weekly Bulletins (\(appState.dxBulletins.count))", systemImage: "books.vertical.fill").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            // Active Section Content
            Group {
                switch selectedSection {
                case 1:
                    newsFeedSection
                case 2:
                    weeklyBulletinsSection
                default:
                    dxpeditionsIntelligenceSection
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            if appState.dxpeditionEntries.isEmpty {
                appState.fetchDXpeditions()
            }
            if selectedBulletinID == nil, let first = appState.dxBulletins.first {
                selectedBulletinID = first.id
            }
        }
        .sheet(item: $selectedArticleForDetail) { article in
            articleDetailSheet(article)
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("DX News & Expeditions Intelligence")
                        .font(.headline)
                    Text("DX-World • 425 DX • NG3K • ARRL • ARNewsline")
                        .font(.caption2.bold())
                        .foregroundColor(.purple)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                }

                Text(appState.dxpeditionStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Global Search Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search callsign, entity, IOTA, bands, modes...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.25), lineWidth: 0.8))
            .frame(width: 280)

            // Refresh Button
            Button {
                appState.fetchDXpeditions(force: true)
            } label: {
                HStack(spacing: 5) {
                    if appState.isFetchingDXpeditions {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(appState.isFetchingDXpeditions)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 1. DXpeditions Intelligence Section
    private var dxpeditionsIntelligenceSection: some View {
        VStack(spacing: 0) {
            // Filter Pills Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExpeditionFilter.allCases) { filter in
                        Button {
                            expeditionFilter = filter
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: filter.icon)
                                Text(filter.rawValue)
                            }
                            .font(.system(size: 11.5, weight: expeditionFilter == filter ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                expeditionFilter == filter ? Color.accentColor.opacity(0.18) : Color(NSColor.controlBackgroundColor),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    expeditionFilter == filter ? Color.accentColor : Color.secondary.opacity(0.25),
                                    lineWidth: expeditionFilter == filter ? 1.4 : 0.8
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))

            Divider()

            // List of DXpeditions
            if filteredExpeditions.isEmpty {
                emptyStateView(
                    icon: "binoculars",
                    title: "No Matching DXpeditions",
                    subtitle: searchText.isEmpty
                        ? "Try selecting a different filter above or click Refresh."
                        : "No operations matched your search '\(searchText)'."
                )
            } else {
                let workIndex = appState.workIndex()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredExpeditions) { entry in
                            dxpeditionCard(entry, workIndex: workIndex)
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private func dxpeditionCard(_ entry: DXpeditionEntry, workIndex: LogWorkIndex) -> some View {
        let spot = appState.dxClusterClient.spots.first { $0.callsign.uppercased() == entry.callsign.uppercased() }
        let entityInfo = DXCCDatabase.resolve(callsign: entry.callsign, country: entry.entity)
        let isWorkedAnyBand = workIndex.summary(for: entry.callsign).total > 0
        let isCountryWorked = isWorkedAnyBand || (workIndex.summary(for: entry.callsign).confirmed > 0)

        return VStack(alignment: .leading, spacing: 8) {
            // Header Row: Flag + Callsign + Entity + Status Badge
            HStack(alignment: .top, spacing: 10) {
                Text(entityInfo.flagEmoji)
                    .font(.system(size: 26))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(entry.callsign)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)

                        Text(entry.entity)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if !entry.iota.isEmpty {
                            Text(entry.iota)
                                .font(.caption2.bold())
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                        }

                        if let g = entry.grid, !g.isEmpty {
                            Text(g)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    HStack(spacing: 8) {
                        // Continent Tag
                        Label(entityInfo.continent, systemImage: entityInfo.continentIcon)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        // Schedule Text
                        Label(entry.scheduleText, systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Status Indicator
                if let spot {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("ON AIR · \(spot.band) (\(String(format: "%.3f", spot.frequencyMHz)) MHz)")
                            .font(.caption.bold().monospaced())
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.14), in: Capsule())
                } else if entry.isActive {
                    Text("ACTIVE WINDOW")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                } else {
                    Text("PLANNED")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            // Middle Row: Bands, Modes, QSL Info Badges
            HStack(spacing: 6) {
                if let bands = entry.bands, !bands.isEmpty {
                    ForEach(bands.prefix(6), id: \.self) { band in
                        Text(band)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                if let modes = entry.modes, !modes.isEmpty {
                    ForEach(modes, id: \.self) { mode in
                        Text(mode)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                if let qsl = entry.qslInfo, !qsl.isEmpty {
                    Text("QSL: \(qsl)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Need Analysis Badge
                if !isCountryWorked {
                    Label("⭐️ NEW DXCC (ATNO)", systemImage: "star.fill")
                        .font(.caption2.bold())
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                } else {
                    Label("✓ Worked Country", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Details prose
            if !entry.details.isEmpty {
                Text(entry.details)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Bottom Action & Source Row
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    ForEach(entry.sources, id: \.self) { src in
                        Text(src)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(sourceColor(for: src))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(sourceColor(for: src).opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if !entry.bulletin.isEmpty {
                        Text(entry.bulletin)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Tune Rig if spot available and rig connected
                if let spot, appState.rigControlClient.state.isConnected {
                    Button {
                        appState.rigControlClient.setFrequencyHz(UInt64(spot.frequencyKHz * 1_000))
                    } label: {
                        Label("Tune Rig", systemImage: "radio")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }

                // Search in Log
                Button {
                    appState.selectedTab = 0
                    appState.searchText = entry.callsign
                } label: {
                    Label("Log History", systemImage: "magnifyingglass")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)

                // Open Source URL
                if let url = entry.primarySourceURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .help("Open official announcement")
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18), lineWidth: 0.8))
    }

    // MARK: - 2. Live DX News Feed Section
    private var newsFeedSection: some View {
        VStack(spacing: 0) {
            // Category filter chips
            HStack(spacing: 8) {
                Text("Category:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                ForEach(["All", "DX News", "DXpedition", "IOTA", "ARRL News", "ARNewsline"], id: \.self) { cat in
                    Button {
                        newsCategoryFilter = cat
                    } label: {
                        Text(cat)
                            .font(.system(size: 11, weight: newsCategoryFilter == cat ? .semibold : .regular))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                newsCategoryFilter == cat ? Color.accentColor.opacity(0.18) : Color(NSColor.controlBackgroundColor),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    newsCategoryFilter == cat ? Color.accentColor : Color.secondary.opacity(0.25),
                                    lineWidth: newsCategoryFilter == cat ? 1.2 : 0.6
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(filteredArticles.count) Articles")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))

            Divider()

            if filteredArticles.isEmpty {
                emptyStateView(
                    icon: "newspaper",
                    title: "No Articles Available",
                    subtitle: "Click Refresh above to download the latest DX news articles from DX-World, 425 DX News, ARRL, and ARNewsline."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredArticles) { article in
                            newsArticleCard(article)
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private func newsArticleCard(_ article: DXNewsArticle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Source Badge
                Text(article.source)
                    .font(.caption2.bold())
                    .foregroundColor(sourceColor(for: article.source))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sourceColor(for: article.source).opacity(0.14), in: RoundedRectangle(cornerRadius: 4))

                Text(article.category)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text(article.displayDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(article.title)
                .font(.headline)
                .foregroundColor(.primary)

            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                // Callsign Tags
                ForEach(article.callsigns.prefix(4), id: \.self) { call in
                    Text(call)
                        .font(.caption2.monospaced().bold())
                        .foregroundColor(.primary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }

                if !article.entity.isEmpty {
                    Text(article.entity)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let audioStr = article.audioURL, let audioURL = URL(string: audioStr) {
                    Link(destination: audioURL) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                            Text("Audio")
                        }
                        .font(.caption2.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
                    .help("Listen to audio report")
                }

                Button("Read Full Story") {
                    selectedArticleForDetail = article
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let url = article.primaryURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .help("Open in web browser")
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18), lineWidth: 0.8))
    }

    // MARK: - 3. Weekly Bulletins Archive Section
    private var weeklyBulletinsSection: some View {
        HStack(spacing: 0) {
            // Left Sidebar: Issue Picker
            VStack(alignment: .leading, spacing: 0) {
                Text("Bulletins & Magazines")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Divider()

                if appState.dxBulletins.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No bulletins downloaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedBulletinID) {
                        ForEach(appState.dxBulletins) { bulletin in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(bulletin.source)
                                        .font(.caption2.bold())
                                        .foregroundColor(bulletin.source.contains("425") ? .orange : .blue)
                                    Spacer()
                                    Text(bulletin.displayDate)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(bulletin.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text("\(bulletin.operationCount) operations extracted")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .tag(bulletin.id)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(width: 250)

            Divider()

            // Right Content Area: Bulletin Text Viewer
            if let activeBulletin = appState.dxBulletins.first(where: { $0.id == (selectedBulletinID ?? appState.dxBulletins.first?.id) }) {
                VStack(alignment: .leading, spacing: 0) {
                    // Bulletin Top Toolbar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeBulletin.title)
                                .font(.headline)
                            Text("\(activeBulletin.source) • Published: \(activeBulletin.displayDate) • \(activeBulletin.operationCount) Operations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Search in bulletin text
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("Filter text...", text: $bulletinSearchText)
                                .textFieldStyle(.plain)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 0.8))
                        .frame(width: 170)

                        // Copy Text
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(activeBulletin.content, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // Open Source URL
                        if let url = activeBulletin.primaryURL {
                            Link(destination: url) {
                                Label("Open Source", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                    Divider()

                    // Scrollable Monospace Text
                    ScrollView {
                        Text(highlightedBulletinContent(activeBulletin.content))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            } else {
                emptyStateView(
                    icon: "books.vertical",
                    title: "Select a Weekly Bulletin",
                    subtitle: "Choose an issue from the list on the left to read the full bulletin."
                )
            }
        }
    }

    private func highlightedBulletinContent(_ content: String) -> String {
        let query = bulletinSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return content }
        let lines = content.components(separatedBy: .newlines)
        let matchedLines = lines.filter { $0.localizedCaseInsensitiveContains(query) }
        guard !matchedLines.isEmpty else { return "No matches for '\(query)'.\n\nFull text:\n\(content)" }
        return "--- [\(matchedLines.count) MATCHES FOR '\(query)'] ---\n\n" + matchedLines.joined(separator: "\n\n") + "\n\n--- [FULL BULLETIN CONTENT BELOW] ---\n\n" + content
    }

    // MARK: - Article Detail Sheet Modal
    private func articleDetailSheet(_ article: DXNewsArticle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(article.source)
                    .font(.caption.bold())
                    .foregroundColor(sourceColor(for: article.source))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(sourceColor(for: article.source).opacity(0.14), in: RoundedRectangle(cornerRadius: 4))

                Spacer()

                Text(article.displayDate)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Done") {
                    selectedArticleForDetail = nil
                }
                .controlSize(.small)
            }

            Text(article.title)
                .font(.title2.bold())

            if !article.callsigns.isEmpty {
                HStack {
                    Text("Callsigns:")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    ForEach(article.callsigns, id: \.self) { call in
                        Text(call)
                            .font(.subheadline.monospaced().bold())
                            .foregroundColor(.accentColor)
                    }
                }
            }

            Divider()

            ScrollView {
                Text(article.body.isEmpty ? article.summary : article.body)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            Divider()

            HStack {
                if let url = article.primaryURL {
                    Link(destination: url) {
                        Label("View Original on \(article.source)", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let audioStr = article.audioURL, let audioURL = URL(string: audioStr) {
                    Link(destination: audioURL) {
                        Label("Listen to Audio Report", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                }

                Spacer()

                Button("Close") {
                    selectedArticleForDetail = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(minWidth: 540, idealWidth: 640, minHeight: 400, idealHeight: 520)
    }

    private func sourceColor(for source: String) -> Color {
        if source.contains("425") { return .orange }
        if source.contains("DX-World") { return .blue }
        if source.contains("NG3K") { return .green }
        if source.contains("ARRL") { return .red }
        if source.contains("Newsline") { return .purple }
        return .secondary
    }

    // MARK: - Filter Logic
    private var filteredExpeditions: [DXpeditionEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let workIndex = appState.workIndex()

        return appState.dxpeditionEntries.filter { entry in
            // Search Query Filter
            if !query.isEmpty {
                let matchesCall = entry.callsign.uppercased().contains(query)
                let matchesEntity = entry.entity.uppercased().contains(query)
                let matchesIOTA = entry.iota.uppercased().contains(query)
                let matchesBands = (entry.bands ?? []).contains { $0.uppercased().contains(query) }
                let matchesModes = (entry.modes ?? []).contains { $0.uppercased().contains(query) }
                let matchesDetails = entry.details.uppercased().contains(query)
                guard matchesCall || matchesEntity || matchesIOTA || matchesBands || matchesModes || matchesDetails else {
                    return false
                }
            }

            // Tab Filter
            switch expeditionFilter {
            case .all:
                return true
            case .activeNow:
                let isSpotted = appState.dxClusterClient.spots.contains { $0.callsign.uppercased() == entry.callsign.uppercased() }
                return isSpotted || entry.isActive
            case .upcoming:
                return !entry.isActive
            case .needed:
                return workIndex.summary(for: entry.callsign).total == 0
            case .digital:
                return (entry.modes ?? []).contains { ["FT8", "FT4", "Digital", "SuperFox", "RTTY"].contains($0) }
            case .sixMeters:
                return (entry.bands ?? []).contains("6m") || entry.details.localizedCaseInsensitiveContains("6m") || entry.details.localizedCaseInsensitiveContains("6 metre")
            case .iota:
                return !entry.iota.isEmpty || entry.details.localizedCaseInsensitiveContains("IOTA")
            case .ng3k:
                return entry.sources.contains { $0.contains("NG3K") }
            case .dxWorld:
                return entry.sources.contains { $0.contains("DX-World") }
            case .fourTwentyFive:
                return entry.sources.contains { $0.contains("425") }
            }
        }
    }

    private var filteredArticles: [DXNewsArticle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return appState.dxNewsArticles.filter { article in
            if newsCategoryFilter != "All" {
                let cat = newsCategoryFilter.lowercased()
                let matchesCategory = article.category.lowercased().contains(cat) || article.source.lowercased().contains(cat)
                if !matchesCategory {
                    return false
                }
            }
            if query.isEmpty { return true }
            return article.title.lowercased().contains(query) ||
                article.summary.lowercased().contains(query) ||
                article.body.lowercased().contains(query) ||
                article.callsigns.contains { $0.lowercased().contains(query) }
        }
    }

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
