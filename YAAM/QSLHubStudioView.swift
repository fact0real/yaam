//
//  QSLHubStudioView.swift
//  YAAM
//
//  Two-Way QSL Hub Studio & Multimedia Inbox
//  Email & File Dropzone (.eml, PDF, Images, ADIF), Vision OCR,
//  Fuzzy Matching with Time Drift Tolerance, Side-by-Side Conflict Resolution,
//  One-Click Parallel Sync All, Paper QSL Tracking, and Multi-Channel Status Matrix.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Studio Navigation Tabs

public enum QSLStudioTab: String, CaseIterable, Identifiable {
    case matrix = "Status Matrix"
    case inbox = "Inbound Inbox"
    case conflict = "Conflict Resolver"
    case gallery = "Card Gallery"
    case paper = "Paper & Bureau"
    case console = "API Console"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .matrix: return "tablecells"
        case .inbox: return "tray.and.arrow.down.fill"
        case .conflict: return "arrow.left.arrow.right"
        case .gallery: return "photo.stack"
        case .paper: return "envelope.badge"
        case .console: return "terminal.fill"
        }
    }
}

// MARK: - Main Studio View

public struct QSLHubStudioView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var inbox = QSLInboxEngine.shared
    @ObservedObject private var syncEngine = QSLSyncEngine.shared
    @ObservedObject private var eqsl = EQSLService.shared

    @State private var selectedTab: QSLStudioTab = .matrix
    @State private var isDropTargeted: Bool = false
    @State private var searchText: String = ""
    @State private var matrixFilter: String = "ALL" // ALL, UNCONFIRMED, HAS_CARD, PAPER_QUEUED
    @State private var viewingCardURL: URL? = nil
    @State private var activeConflictItem: QSLInboundItem? = nil
    @State private var selectedQSOForPaperEdit: QSORecordModel? = nil
    @State private var toastMessage: String? = nil
    @State private var gallerySearchText: String = ""
    @State private var showingEQSLCredentialsPrompt: Bool = false
    @State private var promptEQSLUsername: String = ""
    @State private var promptEQSLPassword: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Studio Header & 1-Click Sync Controls
            studioHeaderBar

            Divider()

            // 2. Drag & Drop Email/Card Dropzone Strip
            dropzoneStrip

            Divider()

            // 3. Tab Bar Navigation
            studioTabBar

            Divider()

            // 4. Tab Content Body
            Group {
                switch selectedTab {
                case .matrix:
                    multiChannelStatusMatrixView
                case .inbox:
                    inboundInboxView
                case .conflict:
                    conflictResolverView
                case .gallery:
                    cardGalleryView
                case .paper:
                    paperQSLManagerView
                case .console:
                    apiDiagnosticConsoleView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: Binding<CardViewerItem?>(
            get: { viewingCardURL.map { CardViewerItem(url: $0) } },
            set: { viewingCardURL = $0?.url }
        )) { item in
            QSLCardViewerModal(cardURL: item.url)
        }
        .sheet(isPresented: $showingEQSLCredentialsPrompt) {
            eqslCredentialsSheet
        }
        .overlay(alignment: .top) {
            if let msg = toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(msg)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
                .shadow(radius: 6)
                .padding(.top, 40)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - 1. Studio Header & Metrics Bar

    private var studioHeaderBar: some View {
        HStack(spacing: 16) {
            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    Text("Two-Way QSL Hub Studio")
                        .font(.headline.bold())
                }
                Text("Email & Card Dropzone · 1-Click Multi-Sync · Conflict Resolver · Paper QSLs")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Metrics Summary Pills
            HStack(spacing: 10) {
                metricPill(title: "Total QSOs", value: "\(appState.qsoRecords.count)", color: .blue)
                metricPill(title: "Confirmed", value: "\(confirmedCount)", color: .green)
                metricPill(title: "Card Images", value: "\(cardImageCount)", color: .cyan)
                metricPill(title: "Inbox Items", value: "\(inbox.inboundItems.count)", color: .purple)
                if conflictCount > 0 {
                    metricPill(title: "Conflicts", value: "\(conflictCount)", color: .orange)
                }
            }

            Divider().frame(height: 28)

            // DOWNLOAD ALL eQSL CARDS BUTTON
            Button {
                triggerEQSLDownload()
            } label: {
                HStack(spacing: 6) {
                    if eqsl.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "photo.badge.checkmark.fill")
                    }
                    Text(eqsl.isSyncing ? "Downloading Cards..." : "Download eQSL Cards")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 6))
                .foregroundColor(.black)
            }
            .buttonStyle(.plain)
            .disabled(eqsl.isSyncing)
            .help("Download all graphical QSL cards from your eQSL.cc inbox")

            // ONE-CLICK SYNC ALL BUTTON
            Button {
                Task {
                    await syncEngine.syncAllServices(appState: appState)
                    showToast("One-Click Sync Complete!")
                }
            } label: {
                HStack(spacing: 6) {
                    if syncEngine.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal.fill")
                    }
                    Text(syncEngine.isSyncing ? "Syncing..." : "Sync All Services")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 6))
                .foregroundColor(.black)
            }
            .buttonStyle(.plain)
            .disabled(syncEngine.isSyncing)
            .help("Synchronize LoTW, eQSL.cc, QRZ, and Club Log in parallel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func metricPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 2. Drag & Drop Email/Card Dropzone Strip

    private var dropzoneStrip: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isDropTargeted ? Color.green : Color.accentColor.opacity(0.4),
                        style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.5, dash: [6, 4])
                    )
                    .background(
                        isDropTargeted ? Color.green.opacity(0.08) : Color.accentColor.opacity(0.03)
                    )

                HStack(spacing: 14) {
                    Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "envelope.badge.shield.half.filled")
                        .font(.title2)
                        .foregroundColor(isDropTargeted ? .green : .accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drop Email Files (.eml), eQSL / Paper Scans (.jpg, .png), PDFs, or ADIF here")
                            .font(.subheadline.weight(.semibold))
                        Text("Instant MIME parsing, Vision OCR text extraction, and Fuzzy QSO matching with ±15m tolerance.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        selectFilesToImport()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                            Text("Browse Files...")
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(height: 54)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                Task {
                    var urls: [URL] = []
                    for provider in providers {
                        if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                           let data = item as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {
                            urls.append(url)
                        } else if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                            urls.append(url)
                        }
                    }
                    if !urls.isEmpty {
                        await inbox.processDroppedFiles(urls, existingQSOs: appState.qsoRecords)
                        showToast("Processed \(urls.count) dropped file(s)")
                        selectedTab = .inbox
                    }
                }
                return true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - 3. Tab Bar Navigation

    private var studioTabBar: some View {
        HStack(spacing: 6) {
            ForEach(QSLStudioTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                        if tab == .inbox && !inbox.inboundItems.isEmpty {
                            Text("\(inbox.inboundItems.count)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.blue, in: Capsule())
                                .foregroundColor(.white)
                        } else if tab == .conflict && conflictCount > 0 {
                            Text("\(conflictCount)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange, in: Capsule())
                                .foregroundColor(.white)
                        }
                    }
                    .font(.caption.weight(selectedTab == tab ? .bold : .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selectedTab == tab ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundColor(selectedTab == tab ? .white : .primary)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if selectedTab == .matrix {
                // Filter chips for matrix & search box with clean spacing
                HStack(spacing: 12) {
                    Picker("", selection: $matrixFilter) {
                        Text("All QSOs").tag("ALL")
                        Text("Unconfirmed").tag("UNCONFIRMED")
                        Text("Has Card 🖼").tag("HAS_CARD")
                        Text("Queued ✉️").tag("PAPER_QUEUED")
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()

                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                        TextField("Filter callsign...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: 150)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Tab 1: Multi-Channel Status Matrix View

    @ViewBuilder
    private var multiChannelStatusMatrixView: some View {
        let filtered = filteredQSOs

        VStack(spacing: 0) {
            // Table Header
            HStack(spacing: 8) {
                Text("DATE / TIME").frame(width: 110, alignment: .leading)
                Text("CALLSIGN").frame(width: 130, alignment: .leading)
                Text("BAND / MODE").frame(width: 100, alignment: .leading)
                Text("LoTW").frame(width: 85, alignment: .center)
                Text("eQSL").frame(width: 105, alignment: .center)
                Text("QRZ").frame(width: 85, alignment: .center)
                Text("CLUB LOG").frame(width: 85, alignment: .center)
                Text("PAPER / BUREAU").frame(width: 110, alignment: .center)
                Spacer()
                Text("ACTIONS").frame(width: 110, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No QSOs match the current filter")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(filtered) { qso in
                    matrixRow(qso: qso)
                        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                }
                .listStyle(.plain)
            }
        }
    }

    private func matrixRow(qso: QSORecordModel) -> some View {
        let call = qso["CALL"]
        let flag = DXCCDatabase.resolve(callsign: call).flagEmoji
        let date = qso["QSO_DATE"]
        let time = qso["TIME_ON"]
        let band = qso["BAND"]
        let mode = qso["MODE"]

        let isLotw = ["Y", "V", "C"].contains(qso["LOTW_QSL_RCVD"].uppercased())
        let isEqsl = ["Y", "V", "C"].contains(qso["EQSL_QSL_RCVD"].uppercased())
        let isQrz = ["Y", "V", "C"].contains(qso["QRZLOG_QSL_RCVD"].uppercased()) ||
                    ["Y", "V", "C"].contains(qso["QRZCOM_QSL_RCVD"].uppercased()) ||
                    ["Y", "V", "C"].contains(qso["QRZCOM_QSO_DOWNLOAD_STATUS"].uppercased()) ||
                    ["CONFIRMED", "C", "Y", "V"].contains(qso["APP_QRZLOG_STATUS"].uppercased())
        let isClubLog = ["Y", "V", "C"].contains(qso["CLUBLOG_LOTW_RCVD"].uppercased()) ||
                        ["C", "G"].contains(qso["APP_YAAM_CLUBLOG_LOTW_STATE"].uppercased())

        let paperRcvd = isPaperQSLReceived(qso)
        let paperSent = isPaperQSLSent(qso)
        let paperQueued = qso["QSL_SENT"].uppercased() == "Q"

        let cardPath = qso["QSL_MEDIA_PATH"]
        let hasCard = (!cardPath.isEmpty && FileManager.default.fileExists(atPath: cardPath)) || EQSLService.shared.hasCachedCard(callsign: call, date: date, band: band, mode: mode)

        return HStack(spacing: 8) {
            // Date / Time
            VStack(alignment: .leading, spacing: 1) {
                Text(date)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Text(time)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 110, alignment: .leading)

            // Callsign
            HStack(spacing: 4) {
                Text(flag).font(.caption2)
                Text(call)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .frame(width: 130, alignment: .leading)

            // Band / Mode
            VStack(alignment: .leading, spacing: 1) {
                Text(band)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                Text(mode)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(width: 100, alignment: .leading)

            // LoTW
            statusBadge(confirmed: isLotw, label: isLotw ? "LoTW" : "-")
                .frame(width: 85, alignment: .center)

            // eQSL + Card Graphic Badge
            HStack(spacing: 3) {
                statusBadge(confirmed: isEqsl, label: isEqsl ? "eQSL" : "-")
                if hasCard {
                    Button {
                        if !cardPath.isEmpty {
                            viewingCardURL = URL(fileURLWithPath: cardPath)
                        } else if let cached = EQSLService.shared.cachedCardURL(callsign: call, date: date, band: band, mode: mode) {
                            viewingCardURL = cached
                        }
                    } label: {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.cyan)
                    }
                    .buttonStyle(.plain)
                    .help("View high-resolution QSL card image")
                }
            }
            .frame(width: 105, alignment: .center)

            // QRZ
            statusBadge(confirmed: isQrz, label: isQrz ? "QRZ" : "-")
                .frame(width: 85, alignment: .center)

            // Club Log
            statusBadge(confirmed: isClubLog, label: isClubLog ? "Match" : "-")
                .frame(width: 85, alignment: .center)

            // Paper / Bureau
            HStack(spacing: 3) {
                if paperRcvd {
                    Text("📬 Recv")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                } else if paperQueued {
                    Text("⏳ Queue")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                } else if paperSent {
                    Text("✉️ Sent")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(.blue)
                } else {
                    Text("-").font(.caption2).foregroundColor(.secondary)
                }
            }
            .frame(width: 110, alignment: .center)

            Spacer()

            // Actions
            HStack(spacing: 4) {
                Button {
                    selectedQSOForPaperEdit = qso
                    selectedTab = .paper
                } label: {
                    Text("Paper")
                        .font(.system(size: 8.5, weight: .semibold))
                }
                .controlSize(.mini)

                if hasCard {
                    Button {
                        if !cardPath.isEmpty {
                            viewingCardURL = URL(fileURLWithPath: cardPath)
                        } else if let cached = EQSLService.shared.cachedCardURL(callsign: call, date: date, band: band, mode: mode) {
                            viewingCardURL = cached
                        }
                    } label: {
                        Text("Card")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .controlSize(.mini)
                }
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func statusBadge(confirmed: Bool, label: String) -> some View {
        HStack(spacing: 3) {
            if confirmed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.green)
                Text(label)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.green)
            } else {
                Text("-")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }

    // MARK: - Tab 2: Inbound Email & File Dropzone Inbox

    @ViewBuilder
    private var inboundInboxView: some View {
        VStack(spacing: 0) {
            // Subheader
            HStack {
                Text("INBOUND ITEMS (\(inbox.inboundItems.count))")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear All") {
                    inbox.inboundItems.removeAll()
                }
                .controlSize(.small)
                .disabled(inbox.inboundItems.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            Divider()

            if inbox.inboundItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Inbox is Empty")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Drag and drop email files (.eml) from eQSL.cc or other operators,\nor drop images (.jpg, .png) and PDFs to match them against your logbook.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    Button("Select Files to Import...") {
                        selectFilesToImport()
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                    Spacer()
                }
            } else {
                List(inbox.inboundItems) { item in
                    inboundItemRow(item: item)
                }
                .listStyle(.plain)
            }
        }
    }

    private func inboundItemRow(item: QSLInboundItem) -> some View {
        HStack(spacing: 12) {
            // Source icon
            Image(systemName: item.source == .email ? "envelope.fill" : (item.source == .image ? "photo.fill" : "doc.fill"))
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)

            // Detected Metadata
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.callsign.isEmpty ? "UNKNOWN CALL" : item.callsign)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text(item.source.rawValue)
                        .font(.system(size: 8.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())

                    Spacer()

                    // Match Confidence Badge
                    HStack(spacing: 3) {
                        Image(systemName: item.status == .matched ? "checkmark.seal.fill" : (item.status == .conflict ? "exclamationmark.triangle.fill" : "questionmark.circle"))
                        Text("\(item.matchConfidence)% Match")
                    }
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(item.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }

                HStack(spacing: 8) {
                    if !item.qsoDate.isEmpty {
                        Text("Date: \(item.qsoDate)")
                    }
                    if !item.qsoTime.isEmpty {
                        Text("Time: \(item.qsoTime) UTC")
                    }
                    if !item.band.isEmpty {
                        Text("Band: \(item.band)")
                    }
                    if !item.mode.isEmpty {
                        Text("Mode: \(item.mode)")
                    }
                    if !item.rst.isEmpty {
                        Text("RST: \(item.rst)")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)

                if !item.subject.isEmpty {
                    Text(item.subject)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Thumbnail if card media present
            if let mediaURL = item.mediaFileURL, let img = NSImage(contentsOf: mediaURL) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 35)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .onTapGesture {
                        viewingCardURL = mediaURL
                    }
            }

            // Action Buttons
            HStack(spacing: 6) {
                if item.status == .conflict {
                    Button("Review Conflict") {
                        activeConflictItem = item
                        selectedTab = .conflict
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                } else if item.status == .matched {
                    Button("Confirm & Attach") {
                        applyInboundMatch(item: item, adoptDiffs: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }

                Button {
                    inbox.inboundItems.removeAll { $0.id == item.id }
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Tab 3: Side-by-Side Conflict Resolver View

    @ViewBuilder
    private var conflictResolverView: some View {
        let conflictItems = inbox.inboundItems.filter { $0.status == .conflict }

        if let current = activeConflictItem ?? conflictItems.first {
            let matchedQSO = appState.qsoRecords.first { $0.id == current.matchedQSOID }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Banner
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("QSO Data Conflict Detected for \(current.callsign)")
                                .font(.headline)
                            Text("Differences found between your local log and the incoming confirmation. Choose how to resolve.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                    // Side-by-Side Cards
                    HStack(alignment: .top, spacing: 16) {
                        // Left Column: Local QSO
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LOCAL LOGBOOK QSO")
                                .font(.caption.bold())
                                .foregroundColor(.blue)

                            VStack(spacing: 6) {
                                comparisonFieldRow(label: "Callsign", value: matchedQSO?["CALL"] ?? "-", isDiff: false)
                                comparisonFieldRow(label: "Date", value: matchedQSO?["QSO_DATE"] ?? "-", isDiff: current.conflictDiffs.contains { $0.fieldName == "QSO_DATE" })
                                comparisonFieldRow(label: "Time ON", value: matchedQSO?["TIME_ON"] ?? "-", isDiff: current.conflictDiffs.contains { $0.fieldName == "TIME_ON" })
                                comparisonFieldRow(label: "Band", value: matchedQSO?["BAND"] ?? "-", isDiff: current.conflictDiffs.contains { $0.fieldName == "BAND" })
                                comparisonFieldRow(label: "Mode", value: matchedQSO?["MODE"] ?? "-", isDiff: current.conflictDiffs.contains { $0.fieldName == "MODE" })
                                comparisonFieldRow(label: "RST Rcvd", value: matchedQSO?["RST_RCVD"] ?? "-", isDiff: current.conflictDiffs.contains { $0.fieldName == "RST_RCVD" })
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .frame(maxWidth: .infinity)

                        // Center: Diff Highlights
                        VStack(spacing: 8) {
                            Text("DIFFERENCES")
                                .font(.caption.bold())
                                .foregroundColor(.orange)

                            ForEach(current.conflictDiffs) { diff in
                                VStack(spacing: 2) {
                                    Text(diff.fieldName)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        Text(diff.localValue).foregroundColor(.blue).strikethrough()
                                        Image(systemName: "arrow.right").font(.system(size: 8))
                                        Text(diff.inboundValue).foregroundColor(.orange).bold()
                                    }
                                    .font(.system(size: 10, design: .monospaced))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .frame(width: 170)

                        // Right Column: Inbound QSL Data
                        VStack(alignment: .leading, spacing: 8) {
                            Text("INCOMING CONFIRMATION (\(current.source.rawValue))")
                                .font(.caption.bold())
                                .foregroundColor(.green)

                            VStack(spacing: 6) {
                                comparisonFieldRow(label: "Callsign", value: current.callsign, isDiff: false)
                                comparisonFieldRow(label: "Date", value: current.qsoDate, isDiff: current.conflictDiffs.contains { $0.fieldName == "QSO_DATE" })
                                comparisonFieldRow(label: "Time ON", value: current.qsoTime, isDiff: current.conflictDiffs.contains { $0.fieldName == "TIME_ON" })
                                comparisonFieldRow(label: "Band", value: current.band, isDiff: current.conflictDiffs.contains { $0.fieldName == "BAND" })
                                comparisonFieldRow(label: "Mode", value: current.mode, isDiff: current.conflictDiffs.contains { $0.fieldName == "MODE" })
                                comparisonFieldRow(label: "RST", value: current.rst, isDiff: current.conflictDiffs.contains { $0.fieldName == "RST_RCVD" })
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Card Image Preview if available
                    if let mediaURL = current.mediaFileURL, let img = NSImage(contentsOf: mediaURL) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ATTACHED QSL CARD IMAGE")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 180)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                .onTapGesture { viewingCardURL = mediaURL }
                        }
                    }

                    // Action Buttons
                    HStack(spacing: 12) {
                        Button {
                            applyInboundMatch(item: current, adoptDiffs: true)
                            showToast("Adopted Inbound Data & Confirmed QSO!")
                            activeConflictItem = nil
                        } label: {
                            Label("Adopt Inbound (Replace Local Diffs & Confirm)", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button {
                            applyInboundMatch(item: current, adoptDiffs: false)
                            showToast("Kept Local Data & Attached QSL Card")
                            activeConflictItem = nil
                        } label: {
                            Label("Keep Local (Confirm QSO & Attach Card Only)", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Reject", role: .destructive) {
                            inbox.inboundItems.removeAll { $0.id == current.id }
                            activeConflictItem = nil
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundColor(.green.opacity(0.6))
                Text("No Unresolved Conflicts")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("All incoming confirmations cleanly match your logbook without field discrepancies.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private func comparisonFieldRow(label: String, value: String, isDiff: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "-" : value)
                .font(.system(size: 11, weight: isDiff ? .bold : .medium, design: .monospaced))
                .foregroundColor(isDiff ? .orange : .primary)
        }
    }

    // MARK: - Tab 4: QSL Card Gallery & Viewer

    private struct DisplayableCard: Identifiable {
        let id: String
        let fileURL: URL
        let callsign: String
        let date: String
        let band: String
        let mode: String
        let isLocalMedia: Bool
    }

    @ViewBuilder
    private var cardGalleryView: some View {
        let allCards: [DisplayableCard] = {
            var seenPaths = Set<String>()
            var cards: [DisplayableCard] = []

            // 1. Collect from QSO records
            for qso in appState.qsoRecords {
                let path = qso["QSL_MEDIA_PATH"]
                let call = qso["CALL"]
                let date = qso["QSO_DATE"]
                let band = qso["BAND"]
                let mode = qso["MODE"]

                let resolvedURL: URL? = {
                    if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                        return URL(fileURLWithPath: path)
                    }
                    return EQSLService.shared.cachedCardURL(callsign: call, date: date, band: band, mode: mode)
                }()

                if let url = resolvedURL, seenPaths.insert(url.path).inserted {
                    cards.append(DisplayableCard(
                        id: url.path,
                        fileURL: url,
                        callsign: call,
                        date: date,
                        band: band,
                        mode: mode,
                        isLocalMedia: !path.isEmpty
                    ))
                }
            }

            // 2. Collect from cached directory files
            for cached in EQSLService.shared.allCachedCards() {
                if seenPaths.insert(cached.fileURL.path).inserted {
                    cards.append(DisplayableCard(
                        id: cached.fileURL.path,
                        fileURL: cached.fileURL,
                        callsign: cached.callsign,
                        date: cached.date,
                        band: cached.band,
                        mode: cached.mode,
                        isLocalMedia: false
                    ))
                }
            }

            return cards
        }()

        let filteredCards = allCards.filter { card in
            guard !gallerySearchText.isEmpty else { return true }
            return card.callsign.localizedCaseInsensitiveContains(gallerySearchText)
        }

        VStack(spacing: 0) {
            // Gallery Toolbar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack.fill")
                        .foregroundColor(.cyan)
                    Text("QSL CARD GALLERY")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text("(\(filteredCards.count))")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                }

                Spacer()

                // Filter search
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                    TextField("Filter callsign...", text: $gallerySearchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !gallerySearchText.isEmpty {
                        Button { gallerySearchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 150)

                // Download All eQSL Cards Button
                Button {
                    triggerEQSLDownload()
                } label: {
                    HStack(spacing: 5) {
                        if eqsl.isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "tray.and.arrow.down.fill")
                        }
                        Text(eqsl.isSyncing ? "Downloading..." : "Download All eQSL Cards")
                            .font(.caption.bold())
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(eqsl.isSyncing)

                // Reveal in Finder
                Button {
                    NSWorkspace.shared.open(EQSLService.shared.cardsDirectoryURL)
                } label: {
                    Image(systemName: "folder")
                        .font(.caption)
                }
                .controlSize(.small)
                .help("Open eQSL Cards folder in Finder")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            Divider()

            // Live download progress banner
            if eqsl.isSyncing {
                VStack(spacing: 6) {
                    HStack {
                        ProgressView().controlSize(.small)
                        if let prog = eqsl.downloadProgress {
                            Text("Downloading cards from eQSL.cc: \(prog.current) / \(prog.total) [\(prog.currentCallsign)]...")
                                .font(.caption.bold())
                        } else {
                            Text(eqsl.statusMessage)
                                .font(.caption.bold())
                        }
                        Spacer()
                        Button("Cancel") {
                            eqsl.cancelDownload()
                        }
                        .controlSize(.mini)
                    }
                    if let prog = eqsl.downloadProgress {
                        ProgressView(value: prog.percentage)
                            .progressViewStyle(.linear)
                            .tint(.cyan)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.cyan.opacity(0.12))

                Divider()
            }

            // Cards Grid or Empty State
            if filteredCards.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No QSL Cards Found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Click 'Download All eQSL Cards' above to automatically retrieve cards from eQSL.cc, or drop email/image files.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button {
                        triggerEQSLDownload()
                    } label: {
                        Label("Download All eQSL Cards", systemImage: "tray.and.arrow.down.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(eqsl.isSyncing)
                    .padding(.top, 4)

                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14)], spacing: 14) {
                        ForEach(filteredCards) { card in
                            cardCell(card: card)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func cardCell(card: DisplayableCard) -> some View {
        let flag = DXCCDatabase.resolve(callsign: card.callsign).flagEmoji
        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                if let img = NSImage(contentsOf: card.fileURL) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 130)
                        .clipped()
                        .cornerRadius(6)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 130)
                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                        .cornerRadius(6)
                }

                Text(card.isLocalMedia ? "Paper / Scan" : "eQSL.cc")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .foregroundColor(card.isLocalMedia ? .orange : .cyan)
                    .padding(5)
            }

            HStack(spacing: 4) {
                Text(flag).font(.caption2)
                Text(card.callsign)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                if !card.band.isEmpty || !card.mode.isEmpty {
                    Text("\(card.band) · \(card.mode)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

            if !card.date.isEmpty {
                Text(card.date)
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            viewingCardURL = card.fileURL
        }
    }

    // MARK: - Tab 5: Traditional Paper QSL & Bureau Manager

    @ViewBuilder
    private var paperQSLManagerView: some View {
        let paperQSOs = appState.qsoRecords.filter { qso in
            isPaperQSLReceived(qso) || isPaperQSLSent(qso) || qso["QSL_SENT"].uppercased() == "Q" || qso.id == selectedQSOForPaperEdit?.id
        }

        HStack(spacing: 0) {
            // Left list of paper tracked QSOs
            VStack(spacing: 0) {
                HStack {
                    Text("PAPER & BUREAU QUEUE")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))

                Divider()

                if paperQSOs.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "envelope.badge")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Paper / Bureau QSOs")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text("Select a QSO from Matrix to queue or track physical cards")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                        Spacer()
                    }
                } else {
                    List(paperQSOs.prefix(100)) { qso in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(qso["CALL"])
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                Text("\(qso["QSO_DATE"]) · \(qso["BAND"]) \(qso["MODE"])")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if qso["QSL_SENT"].uppercased() == "Q" {
                                Text("Queued").font(.system(size: 8.5, weight: .bold)).foregroundColor(.orange)
                            } else if isPaperQSLReceived(qso) {
                                Text("Recv").font(.system(size: 8.5, weight: .bold)).foregroundColor(.green)
                            } else if isPaperQSLSent(qso) {
                                Text("Sent").font(.system(size: 8.5, weight: .bold)).foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedQSOForPaperEdit = qso
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(width: 260)

            Divider()

            // Right detail editor
            if let target = selectedQSOForPaperEdit ?? paperQSOs.first {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paper Card Tracker: \(target["CALL"])")
                                .font(.headline.bold())
                            Text("\(target["QSO_DATE"]) at \(target["TIME_ON"]) UTC · \(target["BAND"]) · \(target["MODE"])")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    Divider()

                    // Sent status
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OUTGOING PAPER QSL")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button("Queue for Bureau (Q)") {
                                updatePaperStatus(qsoID: target.id, sent: "Q", sentVia: "B", rcvd: nil, rcvdVia: nil)
                            }
                            .controlSize(.small)

                            Button("Mark Sent Direct (Y)") {
                                updatePaperStatus(qsoID: target.id, sent: "Y", sentVia: "D", rcvd: nil, rcvdVia: nil)
                            }
                            .controlSize(.small)

                            Button("Clear Sent") {
                                updatePaperStatus(qsoID: target.id, sent: "N", sentVia: "", rcvd: nil, rcvdVia: nil)
                            }
                            .controlSize(.small)
                        }
                    }

                    // Received status
                    VStack(alignment: .leading, spacing: 6) {
                        Text("INCOMING PAPER QSL")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button("Mark Received Bureau (R)") {
                                updatePaperStatus(qsoID: target.id, sent: nil, sentVia: nil, rcvd: "R", rcvdVia: "B")
                            }
                            .controlSize(.small)

                            Button("Mark Received Direct (Y)") {
                                updatePaperStatus(qsoID: target.id, sent: nil, sentVia: nil, rcvd: "Y", rcvdVia: "D")
                            }
                            .controlSize(.small)

                            Button("Clear Received") {
                                updatePaperStatus(qsoID: target.id, sent: nil, sentVia: nil, rcvd: "N", rcvdVia: "")
                            }
                            .controlSize(.small)
                        }
                    }

                    // QSL Manager & Via info
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QSL MANAGER / VIA")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        HStack {
                            Text(target["QSL_VIA"].isEmpty ? "Direct / No Manager Listed" : target["QSL_VIA"])
                                .font(.system(size: 11, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    Spacer()
                }
                .padding(18)
            } else {
                VStack {
                    Spacer()
                    Text("Select a QSO to track Paper QSL status")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func isPaperQSLReceived(_ qso: QSORecordModel) -> Bool {
        let rcvd = qso["QSL_RCVD"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard ["Y", "V", "R", "C", "CONFIRMED", "VERIFIED"].contains(rcvd) else { return false }

        // 1. Explicitly received via Bureau, Direct, or Manager
        let via = qso["QSL_RCVD_VIA"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if ["B", "D", "M", "BUREAU", "BURO", "DIRECT", "MANAGER"].contains(via) {
            return true
        }

        // 2. Physical paper card scanned and attached
        let cardPath = qso["QSL_MEDIA_PATH"]
        if !cardPath.isEmpty && FileManager.default.fileExists(atPath: cardPath) {
            return true
        }

        // 3. Explicit YAAM or Logger Paper Confirmation Source Tag
        let yaamSource = (qso["APP_YAAM_QSL_SOURCE"] + " " + qso["APP_YAAM_CONFIRMATION_SOURCE"] + " " + qso["APP_QSL_SOURCE"]).uppercased()
        if yaamSource.contains("PAPER") || yaamSource.contains("BUREAU") || yaamSource.contains("BURO") || yaamSource.contains("DIRECT") || yaamSource.contains("CARD") {
            return true
        }

        // 4. If any electronic confirmation is present without explicit paper indicators,
        // it is an electronic confirmation mirror (e.g. from LoTW, eQSL, QRZ) and NOT paper.
        let isLotw = ["Y", "V", "C"].contains(qso["LOTW_QSL_RCVD"].uppercased())
        let isEqsl = ["Y", "V", "C"].contains(qso["EQSL_QSL_RCVD"].uppercased())
        let isQrz = ["Y", "V", "C"].contains(qso["QRZLOG_QSL_RCVD"].uppercased()) ||
                    ["Y", "V", "C"].contains(qso["QRZCOM_QSL_RCVD"].uppercased()) ||
                    ["Y", "V", "C"].contains(qso["QRZCOM_QSO_DOWNLOAD_STATUS"].uppercased()) ||
                    ["CONFIRMED", "C", "Y", "V"].contains(qso["APP_QRZLOG_STATUS"].uppercased())

        if isLotw || isEqsl || isQrz {
            return false
        }

        // 5. If no electronic confirmation, but via is electronic (e.g. "E")
        if via == "E" || via == "ELECTRONIC" {
            return false
        }

        return false
    }

    private func isPaperQSLSent(_ qso: QSORecordModel) -> Bool {
        let sent = qso["QSL_SENT"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard ["Y", "S"].contains(sent) else { return false }

        let via = qso["QSL_SENT_VIA"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if ["B", "D", "M", "BUREAU", "BURO", "DIRECT", "MANAGER"].contains(via) {
            return true
        }

        let yaamSource = (qso["APP_YAAM_QSL_SOURCE"] + " " + qso["APP_YAAM_CONFIRMATION_SOURCE"] + " " + qso["APP_QSL_SOURCE"]).uppercased()
        if yaamSource.contains("PAPER") || yaamSource.contains("BUREAU") || yaamSource.contains("BURO") || yaamSource.contains("DIRECT") {
            return true
        }

        let isLotwSent = ["Y", "S"].contains(qso["LOTW_QSL_SENT"].uppercased())
        let isEqslSent = ["Y", "S"].contains(qso["EQSL_QSL_SENT"].uppercased())
        if isLotwSent || isEqslSent {
            return false
        }

        return false
    }

    private func updatePaperStatus(qsoID: UUID, sent: String?, sentVia: String? = nil, rcvd: String?, rcvdVia: String? = nil) {
        if let idx = appState.qsoRecords.firstIndex(where: { $0.id == qsoID }) {
            if let sent { appState.qsoRecords[idx].fields["QSL_SENT"] = sent }
            if let sentVia {
                if sentVia.isEmpty {
                    appState.qsoRecords[idx].fields.removeValue(forKey: "QSL_SENT_VIA")
                } else {
                    appState.qsoRecords[idx].fields["QSL_SENT_VIA"] = sentVia
                }
            }
            if let rcvd {
                appState.qsoRecords[idx].fields["QSL_RCVD"] = rcvd
                if rcvd == "N" {
                    appState.qsoRecords[idx].fields.removeValue(forKey: "QSL_RCVD_VIA")
                }
            }
            if let rcvdVia {
                if rcvdVia.isEmpty {
                    appState.qsoRecords[idx].fields.removeValue(forKey: "QSL_RCVD_VIA")
                } else {
                    appState.qsoRecords[idx].fields["QSL_RCVD_VIA"] = rcvdVia
                }
            }
            appState.autoSaveActiveWorkspace()
            showToast("Updated Paper QSL status for \(appState.qsoRecords[idx]["CALL"])")
        }
    }

    // MARK: - Tab 6: Live API Diagnostic Console View

    @ViewBuilder
    private var apiDiagnosticConsoleView: some View {
        VStack(spacing: 0) {
            // Console Toolbar
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("REAL-TIME API DIAGNOSTIC CONSOLE")
                        .font(.caption.bold())
                }

                Spacer()

                Button("Clear Console") {
                    syncEngine.clearLogs()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(red: 0.08, green: 0.10, blue: 0.14))

            Divider()

            // Console Log Output
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(syncEngine.diagnosticLogs) { log in
                        HStack(alignment: .top, spacing: 8) {
                            Text("[\(log.formattedTime)]")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(.secondary)

                            Text(log.service)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(log.level.color)
                                .frame(width: 85, alignment: .leading)

                            Text(log.message)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(12)
            }
            .background(Color(red: 0.05, green: 0.07, blue: 0.10))
        }
    }

    // MARK: - Helper Methods

    private var confirmedCount: Int {
        appState.qsoRecords.filter { $0.isConfirmed }.count
    }

    private var cardImageCount: Int {
        appState.qsoRecords.filter { qso in
            let path = qso["QSL_MEDIA_PATH"]
            let call = qso["CALL"]
            let date = qso["QSO_DATE"]
            let band = qso["BAND"]
            let mode = qso["MODE"]
            return (!path.isEmpty && FileManager.default.fileExists(atPath: path)) || EQSLService.shared.hasCachedCard(callsign: call, date: date, band: band, mode: mode)
        }.count
    }

    private var conflictCount: Int {
        inbox.inboundItems.filter { $0.status == .conflict }.count
    }

    private var filteredQSOs: [QSORecordModel] {
        appState.qsoRecords.filter { qso in
            if !searchText.isEmpty {
                let match = qso["CALL"].localizedCaseInsensitiveContains(searchText)
                guard match else { return false }
            }
            switch matrixFilter {
            case "UNCONFIRMED":
                return !qso.isConfirmed
            case "HAS_CARD":
                let path = qso["QSL_MEDIA_PATH"]
                let call = qso["CALL"]
                let date = qso["QSO_DATE"]
                let band = qso["BAND"]
                let mode = qso["MODE"]
                return (!path.isEmpty && FileManager.default.fileExists(atPath: path)) || EQSLService.shared.hasCachedCard(callsign: call, date: date, band: band, mode: mode)
            case "PAPER_QUEUED":
                return qso["QSL_SENT"].uppercased() == "Q"
            default:
                return true
            }
        }
    }

    private func applyInboundMatch(item: QSLInboundItem, adoptDiffs: Bool) {
        guard let qsoID = item.matchedQSOID,
              let idx = appState.qsoRecords.firstIndex(where: { $0.id == qsoID }) else { return }

        if adoptDiffs {
            if !item.mode.isEmpty { appState.qsoRecords[idx].fields["MODE"] = item.mode }
            if !item.qsoTime.isEmpty { appState.qsoRecords[idx].fields["TIME_ON"] = item.qsoTime }
            if !item.rst.isEmpty { appState.qsoRecords[idx].fields["RST_RCVD"] = item.rst }
        }

        // Mark confirmed
        appState.qsoRecords[idx].fields["QSL_RCVD"] = "Y"
        appState.qsoRecords[idx].fields["QSL_RCVD_VIA"] = item.source == .email ? "EMAIL" : (item.source == .eqsl ? "EQSL" : "DIRECT")
        if let mediaURL = item.mediaFileURL {
            appState.qsoRecords[idx].fields["QSL_MEDIA_PATH"] = mediaURL.path
        }

        appState.autoSaveActiveWorkspace()
        inbox.inboundItems.removeAll { $0.id == item.id }
        showToast("QSO with \(item.callsign) confirmed & card attached!")
    }

    private func selectFilesToImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "eml") ?? .data,
            .jpeg,
            .png,
            .pdf,
            UTType(filenameExtension: "adi") ?? .plainText,
            UTType(filenameExtension: "adif") ?? .plainText
        ]
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                await inbox.processDroppedFiles(urls, existingQSOs: appState.qsoRecords)
                showToast("Imported \(urls.count) file(s)")
                selectedTab = .inbox
            }
        }
    }

    private func triggerEQSLDownload() {
        let defaultCall = appState.activeStationProfile?.callsign ?? ""
        let username = (UserDefaults.standard.string(forKey: "eqslUsername") ?? defaultCall).trimmingCharacters(in: .whitespacesAndNewlines)
        let password = CredentialVault.value(for: .eqslPassword).trimmingCharacters(in: .whitespacesAndNewlines)

        if username.isEmpty || password.isEmpty {
            promptEQSLUsername = username.isEmpty ? defaultCall : username
            promptEQSLPassword = password
            showingEQSLCredentialsPrompt = true
            return
        }

        selectedTab = .gallery
        Task {
            do {
                let count = try await eqsl.downloadAllCards(
                    username: username,
                    password: password,
                    qthNickname: appState.activeStationProfile?.eqslQTHNickname,
                    appState: appState
                )
                showToast("✅ Downloaded \(count) QSL card(s) from eQSL.cc")
            } catch {
                showToast("❌ eQSL: \(error.localizedDescription)")
            }
        }
    }

    private func savePromptCredentialsAndDownload() {
        let u = promptEQSLUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = promptEQSLPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(u, forKey: "eqslUsername")
        CredentialVault.set(p, for: .eqslPassword)
        showingEQSLCredentialsPrompt = false
        triggerEQSLDownload()
    }

    private var eqslCredentialsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "photo.badge.checkmark.fill")
                    .font(.title)
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("eQSL.cc Credentials Required")
                        .font(.headline.bold())
                    Text("Enter your eQSL.cc credentials to download all your electronic QSL cards.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Callsign / Username:").font(.caption.bold())
                    TextField("Callsign (e.g. \(appState.activeStationProfile?.callsign ?? "EP2AES"))", text: $promptEQSLUsername)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("eQSL Password:").font(.caption.bold())
                    SecureField("Password", text: $promptEQSLPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    showingEQSLCredentialsPrompt = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save & Download Cards") {
                    savePromptCredentialsAndDownload()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .disabled(promptEQSLUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || promptEQSLPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func showToast(_ msg: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if toastMessage == msg { toastMessage = nil }
            }
        }
    }
}

// MARK: - Card Viewer Sheet

private struct CardViewerItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct QSLCardViewerModal: View {
    let cardURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var zoomScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0.0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text(cardURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    zoomScale = max(0.5, zoomScale - 0.25)
                } label: { Image(systemName: "minus.magnifyingglass") }
                Text("\(Int(zoomScale * 100))%").font(.caption.monospacedDigit())
                Button {
                    zoomScale = min(3.0, zoomScale + 0.25)
                } label: { Image(systemName: "plus.magnifyingglass") }
                Button {
                    rotationAngle += 90.0
                } label: { Image(systemName: "rotate.right") }

                Divider().frame(height: 18)

                Button {
                    saveImageToDisk()
                } label: {
                    Label("Save Image", systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([cardURL])
                } label: {
                    Image(systemName: "folder")
                }
                .controlSize(.small)
                .help("Reveal card in Finder")

                Divider().frame(height: 18)

                Button("Done") { dismiss() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Card Image
            ScrollView([.horizontal, .vertical]) {
                if let img = NSImage(contentsOf: cardURL) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoomScale)
                        .rotationEffect(.degrees(rotationAngle))
                        .padding(20)
                } else {
                    ContentUnavailableView("Unable to render image", systemImage: "photo.badge.exclamationmark")
                }
            }
        }
        .frame(minWidth: 680, minHeight: 480)
    }

    private func saveImageToDisk() {
        guard let img = NSImage(contentsOf: cardURL) else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.jpeg, .png]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = cardURL.lastPathComponent

        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let data = bitmap.representation(using: .jpeg, properties: [:]) {
                try? data.write(to: url)
            }
        }
    }
}
