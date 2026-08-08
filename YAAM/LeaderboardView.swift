//
//  LeaderboardView.swift
//  YAAM
//
//  Created by factoreal on 7/30/26.
//

import SwiftUI

// MARK: - API Response Model
struct QRZRankResponse: Codable {
    let bid: String?
    let callsign: String?
    let country_iso: String?
    let country_name: String?
    let rank_band: String?
    let rank_countries: String?
    let rank_qso: String?
    let score_band: String?
    let score_countries: String?
    let score_qso: String?
}

// MARK: - Helper to parse rank strings like "#16,278" into Int
func parseRankInt(_ rankStr: String?) -> Int? {
    guard let str = rankStr else { return nil }
    let cleaned = str.replacingOccurrences(of: "#", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
    return Int(cleaned)
}

// MARK: - Full Page Leaderboard View with VS Mode
struct LeaderboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // 1. Search Bar Area
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                TextField("Search rival callsign (e.g. W1AW, K1JT)...", text: $appState.leaderboardSearchCallsign, onCommit: {
                    appState.fetchQRZLeaderboard(for: appState.leaderboardSearchCallsign)
                })
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                
                Button(action: {
                    appState.fetchQRZLeaderboard(for: appState.leaderboardSearchCallsign)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "swords")
                        Text("Compare VS")
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 2. Main Content
            if appState.isFetchingRank {
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.4)
                    Text("Fetching global rankings & analyzing scores...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                
            } else if let searched = appState.qrzRankData {
                let owner = appState.ownerRankData
                let isSelfSearch = (owner?.callsign?.uppercased() == searched.callsign?.uppercased())
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // VS Battle Banner
                        HStack(spacing: 20) {
                            // Left Player: YOU
                            PlayerCard(
                                title: "YOU (STATION)",
                                callsign: owner?.callsign ?? "EP2AES",
                                countryIso: owner?.country_iso,
                                isOwner: true
                            )
                            
                            // Center VS Badge
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .orange.opacity(0.5), radius: 8)
                                    
                                    Text("VS")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                if isSelfSearch {
                                    Text("Self View")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Right Player: RIVAL
                            PlayerCard(
                                title: isSelfSearch ? "TARGET" : "RIVAL OPERATOR",
                                callsign: searched.callsign ?? "UNKNOWN",
                                countryIso: searched.country_iso,
                                isOwner: false
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        
                        // Comparison Categories
                        VStack(spacing: 16) {
                            Text("HEAD-TO-HEAD STANDINGS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .kerning(1.5)
                            
                            ComparisonRow(
                                category: "QSO World Rank",
                                icon: "antenna.radiowaves.left.and.right",
                                ownerRank: owner?.rank_qso,
                                searchedRank: searched.rank_qso,
                                ownerScore: owner?.score_qso,
                                searchedScore: searched.score_qso,
                                isSelf: isSelfSearch
                            )
                            
                            ComparisonRow(
                                category: "Bands World Rank",
                                icon: "waveform.path.ecg",
                                ownerRank: owner?.rank_band,
                                searchedRank: searched.rank_band,
                                ownerScore: owner?.score_band,
                                searchedScore: searched.score_band,
                                isSelf: isSelfSearch
                            )
                            
                            ComparisonRow(
                                category: "DXCC World Rank",
                                icon: "globe.americas.fill",
                                ownerRank: owner?.rank_countries,
                                searchedRank: searched.rank_countries,
                                ownerScore: owner?.score_countries,
                                searchedScore: searched.score_countries,
                                isSelf: isSelfSearch
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
                
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "trophy.circle.fill")
                        .font(.system(size: 70))
                        .foregroundColor(.orange.opacity(0.4))
                    Text("Search any Callsign to launch Head-to-Head Comparison!")
                        .font(.title3)
                        .bold()
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .onAppear {
            if appState.leaderboardSearchCallsign.isEmpty {
                appState.leaderboardSearchCallsign = "W1AW" // Example rival for fun
            }
            if appState.qrzRankData == nil {
                appState.fetchQRZLeaderboard(for: appState.leaderboardSearchCallsign)
            }
        }
    }
}

// MARK: - Player Profile Banner Card
struct PlayerCard: View {
    let title: String
    let callsign: String
    let countryIso: String?
    let isOwner: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            if isOwner {
                Text(countryToFlag(countryIso ?? ""))
                    .font(.system(size: 40))
            }
            
            VStack(alignment: isOwner ? .leading : .trailing, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isOwner ? .blue : .purple)
                
                Text(callsign)
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundColor(.primary)
            }
            
            if !isOwner {
                Text(countryToFlag(countryIso ?? ""))
                    .font(.system(size: 40))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: isOwner ? .leading : .trailing)
        .background(isOwner ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isOwner ? Color.blue.opacity(0.3) : Color.purple.opacity(0.3), lineWidth: 1.5))
    }
}

// MARK: - Head-to-Head Comparison Row Widget
struct ComparisonRow: View {
    let category: String
    let icon: String
    let ownerRank: String?
    let searchedRank: String?
    let ownerScore: String?
    let searchedScore: String?
    let isSelf: Bool
    
    // In rankings, LOWER number is BETTER! (#100 > #5000)
    private var deltaText: (text: String, color: Color, icon: String) {
        guard !isSelf,
              let oInt = parseRankInt(ownerRank),
              let sInt = parseRankInt(searchedRank) else {
            return ("Equal", .gray, "minus")
        }
        
        let diff = abs(oInt - sInt)
        let formattedDiff = NumberFormatter.localizedString(from: NSNumber(value: diff), number: .decimal)
        
        if oInt < sInt {
            return (" You lead by \(formattedDiff) ranks", .green, "arrow.up.circle.fill")
        } else if oInt > sInt {
            return ("\(formattedDiff) ranks behind", .red, "arrow.down.circle.fill")
        } else {
            return ("Tied Rank", .gray, "equal.circle.fill")
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Category Title & Delta Badge
            HStack {
                Label(category, systemImage: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !isSelf {
                    HStack(spacing: 4) {
                        Image(systemName: deltaText.icon)
                        Text(deltaText.text)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(deltaText.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(deltaText.color.opacity(0.12))
                    .cornerRadius(8)
                }
            }
            
            // Side by Side Stats Grid
            HStack(spacing: 0) {
                // Left: Owner Rank
                VStack(spacing: 2) {
                    Text(ownerRank ?? "N/A")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                    Text("Score: \(ownerScore ?? "N/A")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 30)
                
                // Right: Rival Rank
                VStack(spacing: 2) {
                    Text(searchedRank ?? "N/A")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.purple)
                    Text("Score: \(searchedScore ?? "N/A")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
}
