//
//  ClubMembershipEngine.swift
//  YAAM
//
//  International Amateur Radio Club Memberships Database & Auto-Lookup Engine
//  High-speed O(1) offline lookup for SKCC, CWops, FISTS, LICW, 30MDG, EPC, and AGCW.
//  Provides online roster auto-updating, contest exchange prefill, and live UI badges.
//

import Combine
import Foundation
import SwiftUI

public enum HamRadioClub: String, CaseIterable, Identifiable, Codable, Sendable {
    case skcc = "SKCC"
    case cwops = "CWops"
    case fists = "FISTS"
    case licw = "LICW"
    case thirtyMDG = "30MDG"
    case epc = "EPC"
    case agcw = "AGCW"

    public var id: String { rawValue }

    public var fullName: String {
        switch self {
        case .skcc: return "Straight Key Century Club"
        case .cwops: return "CW Operators' Club"
        case .fists: return "FISTS CW Club"
        case .licw: return "Long Island CW Club"
        case .thirtyMDG: return "30 Meter Digital Group"
        case .epc: return "European PSK Club"
        case .agcw: return "Arbeinschaft Telegrafie"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .skcc: return .blue
        case .cwops: return .purple
        case .fists: return .red
        case .licw: return .teal
        case .thirtyMDG: return .green
        case .epc: return .orange
        case .agcw: return .indigo
        }
    }

    public var icon: String {
        switch self {
        case .skcc: return "key.fill"
        case .cwops: return "tuningfork"
        case .fists: return "hand.raised.fill"
        case .licw: return "waveform"
        case .thirtyMDG: return "dot.radiowaves.left.and.right"
        case .epc: return "globe.europe.africa.fill"
        case .agcw: return "antenna.radiowaves.left.and.right"
        }
    }

    public var rosterURL: URL? {
        switch self {
        case .skcc:
            return URL(string: "https://www.skccgroup.com/membership_data/membership_data.txt")
        case .cwops:
            return URL(string: "https://cwops.org/wp-content/uploads/roster/cwops-roster.csv")
        case .fists:
            return URL(string: "https://fists.co.uk/members/members.txt")
        case .licw:
            return URL(string: "https://longislandcwclub.org/roster.csv")
        default:
            return nil
        }
    }
}

public struct ClubMembershipMatch: Identifiable, Hashable, Sendable {
    public var id: String { "\(club.rawValue)_\(memberNumber)" }
    public let club: HamRadioClub
    public let memberNumber: String
    public let callsign: String
    public let name: String
    public let stateOrCountry: String

    public init(club: HamRadioClub, memberNumber: String, callsign: String, name: String = "", stateOrCountry: String = "") {
        self.club = club
        self.memberNumber = memberNumber
        self.callsign = callsign.uppercased()
        self.name = name
        self.stateOrCountry = stateOrCountry
    }
}

@MainActor
public final class ClubMembershipEngine: ObservableObject {
    public static let shared = ClubMembershipEngine()

    @Published public var isUpdatingRosters: Bool = false
    @Published public var lastUpdateDate: Date? = nil
    @Published public var statusMessage: String = "Ready"
    @Published public var totalMembersIndexed: Int = 0

    // High-speed O(1) in-memory indices: [Club: [NormalizedCallsign: Match]]
    private var database: [HamRadioClub: [String: ClubMembershipMatch]] = [:]

    private let fileManager = FileManager.default

    public init() {
        loadLocalCachedDatabases()
    }

    // MARK: - Local Cache Directory

    public var clubDataDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yaamDir = appSupport.appendingPathComponent("YAAM", isDirectory: true)
        let clubDir = yaamDir.appendingPathComponent("ClubDatabases", isDirectory: true)
        if !fileManager.fileExists(atPath: clubDir.path) {
            try? fileManager.createDirectory(at: clubDir, withIntermediateDirectories: true)
        }
        return clubDir
    }

    // MARK: - Instant O(1) Lookup API

    public func lookupMemberships(for callsign: String) -> [ClubMembershipMatch] {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCall.isEmpty else { return [] }

        // Strip portable prefixes/suffixes for matching (e.g. W1AW/P -> W1AW)
        let baseCall = cleanCall.components(separatedBy: "/").first { $0.count >= 3 } ?? cleanCall

        var matches: [ClubMembershipMatch] = []

        for club in HamRadioClub.allCases {
            if let clubDict = database[club] {
                if let match = clubDict[cleanCall] ?? clubDict[baseCall] {
                    matches.append(match)
                }
            }
        }

        return matches
    }

    public func memberCount(for club: HamRadioClub) -> Int {
        return database[club]?.count ?? 0
    }

    // MARK: - Online Roster Auto-Update

    public func updateAllRosters() async {
        self.isUpdatingRosters = true
        self.statusMessage = "Updating club rosters from international servers..."

        defer {
            self.isUpdatingRosters = false
            self.lastUpdateDate = Date()
            self.recalculateTotalCount()
        }

        for club in HamRadioClub.allCases {
            guard let url = club.rosterURL else { continue }
            do {
                self.statusMessage = "Downloading \(club.rawValue) roster..."
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }

                if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                    parseAndIndexRoster(text: text, club: club)
                    saveRosterToDisk(data: data, club: club)
                }
            } catch {
                continue
            }
        }

        self.statusMessage = "Club databases updated. \(totalMembersIndexed) members indexed."
    }

    private func parseAndIndexRoster(text: String, club: HamRadioClub) {
        var clubMap = database[club] ?? [:]
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ",|\t"))
            if parts.count >= 2 {
                let col0 = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let col1 = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

                // Detect which column is number and which is callsign
                var call = ""
                var number = ""
                let name = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""

                if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: col0.replacingOccurrences(of: "C", with: "").replacingOccurrences(of: "T", with: "").replacingOccurrences(of: "S", with: ""))) {
                    number = col0
                    call = col1
                } else {
                    call = col0
                    number = col1
                }

                if !call.isEmpty && !number.isEmpty {
                    clubMap[call] = ClubMembershipMatch(club: club, memberNumber: number, callsign: call, name: name)
                }
            }
        }

        database[club] = clubMap
    }

    private func saveRosterToDisk(data: Data, club: HamRadioClub) {
        let dest = clubDataDirectoryURL.appendingPathComponent("\(club.rawValue)_roster.txt")
        try? data.write(to: dest)
    }

    private func loadLocalCachedDatabases() {
        for club in HamRadioClub.allCases {
            let fileURL = clubDataDirectoryURL.appendingPathComponent("\(club.rawValue)_roster.txt")
            if let data = try? Data(contentsOf: fileURL),
               let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                parseAndIndexRoster(text: text, club: club)
            }
        }
        recalculateTotalCount()
    }

    private func recalculateTotalCount() {
        var total = 0
        for (_, dict) in database {
            total += dict.count
        }
        self.totalMembersIndexed = total
    }

}
