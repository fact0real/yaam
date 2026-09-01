//
//  ClubMembershipView.swift
//  YAAM
//
//  Club Memberships Explorer & Roster Management Workspace
//  Inspects international club memberships (SKCC, CWops, FISTS, LICW, 30MDG, EPC),
//  provides multi-club search, 1-click exchange insertion, and roster updates.
//

import AppKit
import Combine
import SwiftUI

public struct ClubMembershipView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var engine = ClubMembershipEngine.shared

    @State private var searchCallsign: String = ""
    @State private var searchResults: [ClubMembershipMatch] = []

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Bar
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.3.sequence.fill")
                                .font(.title2)
                                .foregroundColor(.purple)
                            Text("International Club Memberships")
                                .font(.title2.weight(.bold))
                        }
                        Text("Auto-detect member numbers for CW & Digital clubs during QSO logging")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await engine.updateAllRosters()
                            }
                        } label: {
                            Label("Update Rosters", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(engine.isUpdatingRosters)

                        if engine.isUpdatingRosters {
                            ProgressView().controlSize(.small)
                        }
                    }
                }

                // Club Roster Statistics Cards
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(HamRadioClub.allCases) { club in
                        clubStatCard(club)
                    }
                }

                Divider()

                // Callsign Lookup Search Box
                VStack(alignment: .leading, spacing: 12) {
                    Text("Callsign Membership Lookup")
                        .font(.headline)

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Enter callsign (e.g. W1AW, K6VVA, DL1ABC, EP2AES)...", text: $searchCallsign)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit {
                                performSearch()
                            }

                        Button("Lookup") {
                            performSearch()
                        }
                        .buttonStyle(.bordered)
                        .disabled(searchCallsign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // Search Results
                    if !searchResults.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Memberships for \(searchCallsign.uppercased()):")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            ForEach(searchResults) { match in
                                HStack(spacing: 12) {
                                    Image(systemName: match.club.icon)
                                        .foregroundColor(match.club.badgeColor)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(match.club.rawValue)
                                                .font(.headline.bold())
                                            Text("#\(match.memberNumber)")
                                                .font(.system(.headline, design: .monospaced).bold())
                                                .foregroundColor(match.club.badgeColor)
                                        }

                                        Text(match.club.fullName + (match.name.isEmpty ? "" : " · \(match.name)"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button {
                                        appState.quickLogDraft.receivedExchange = match.memberNumber
                                        appState.quickLogDraft.comment = "\(match.club.rawValue) #\(match.memberNumber)"
                                        appState.selectedTab = 5
                                        appState.operatorDeskSection = 0
                                    } label: {
                                        Label("Use in Quick Log", systemImage: "arrow.down.to.line.compact")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(match.club.badgeColor.opacity(0.4), lineWidth: 1)
                                )
                            }
                        }
                        .padding(14)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(10)
                    } else if !searchCallsign.isEmpty {
                        Text("No club memberships found for \(searchCallsign.uppercased()).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }

                Divider()

                // Status & Cache Info
                HStack {
                    Text(engine.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Open Rosters Folder in Finder") {
                        NSWorkspace.shared.open(engine.clubDataDirectoryURL)
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
            .padding(22)
        }
        .onAppear {
            if searchCallsign.isEmpty && !appState.quickLogDraft.callsign.isEmpty {
                searchCallsign = appState.quickLogDraft.callsign
                performSearch()
            }
        }
    }

    private func performSearch() {
        let trimmed = searchCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        searchResults = engine.lookupMemberships(for: trimmed)
    }

    private func clubStatCard(_ club: HamRadioClub) -> some View {
        HStack(spacing: 12) {
            Image(systemName: club.icon)
                .font(.title2)
                .foregroundColor(club.badgeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(club.rawValue)
                    .font(.headline.bold())
                Text("\(engine.memberCount(for: club).formatted()) members")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(club.badgeColor.opacity(0.3), lineWidth: 1)
        )
    }
}
